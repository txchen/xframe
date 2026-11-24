import CoreML
import CoreVideo
import Foundation
import Metal
import QuartzCore

enum FrameGenerationMode: String, CaseIterable, Sendable {
    case off
    case balanced
    case quality

    static let defaultsKey = "XFrame.FrameGenerationMode"

    var title: String {
        switch self {
        case .off: "Off"
        case .balanced: "Core ML Balanced (360p/480p flow)"
        case .quality: "Core ML Quality (540p/720p flow)"
        }
    }

    var shortTitle: String {
        switch self {
        case .off: "Off"
        case .balanced: "Core ML Balanced"
        case .quality: "Core ML Quality"
        }
    }

    static func load(_ defaults: UserDefaults = .standard) -> Self {
        defaults.string(forKey: defaultsKey).flatMap(Self.init(rawValue:)) ?? .off
    }

    func save(_ defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.defaultsKey)
    }

    func profile(width: Int, height: Int) -> CoreMLFGProfile? {
        switch (self, width, height) {
        case (.off, _, _): nil
        case (_, 1280, 720): .p720
        case (.balanced, 1920, 1080): .p1080Balanced
        case (.quality, 1920, 1080): .p1080Quality
        case (.balanced, 2560, 1440): .p1440Balanced
        case (.quality, 2560, 1440): .p1440Quality
        default: nil
        }
    }
}

final class InterpolatedTextureBox: @unchecked Sendable {
    let texture: any MTLTexture
    private let onRelease: (@Sendable (any MTLTexture) -> Void)?

    init(_ texture: any MTLTexture, onRelease: (@Sendable (any MTLTexture) -> Void)? = nil) {
        self.texture = texture
        self.onRelease = onRelease
    }

    deinit {
        onRelease?(texture)
    }
}

/// Fast sparse luma fingerprint on an NV12 CVPixelBuffer for detecting repeated 30 fps frames inside 60 Hz streams.
struct LumaFingerprint: Equatable, Sendable {
    let samples: [UInt8]

    static func capture(from buffer: CVPixelBuffer) -> LumaFingerprint? {
        guard CVPixelBufferGetPlaneCount(buffer) >= 1,
              CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0) else { return nil }
        let width = CVPixelBufferGetWidthOfPlane(buffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(buffer, 0)
        let stride = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        guard width >= 16, height >= 16, stride >= width else { return nil }
        let ptr = base.assumingMemoryBound(to: UInt8.self)
        var out = [UInt8]()
        out.reserveCapacity(64)
        for row in 0..<8 {
            let y = (height * (row + 1)) / 9
            let rowPtr = ptr.advanced(by: y * stride)
            for col in 0..<8 {
                let x = (width * (col + 1)) / 9
                out.append(rowPtr[x])
            }
        }
        return LumaFingerprint(samples: out)
    }

    /// Mean absolute luma difference (0...255) across the 8x8 sparse grid.
    func meanAbsDiff(to other: LumaFingerprint) -> Double {
        guard samples.count == other.samples.count, !samples.isEmpty else { return 0 }
        var diff = 0
        for i in 0..<samples.count {
            diff += abs(Int(samples[i]) - Int(other.samples[i]))
        }
        return Double(diff) / Double(samples.count)
    }

    /// Mean absolute luma difference <= 1.0 treats consecutive 60 Hz frames as duplicate 30 fps content.
    func isNearlyIdentical(to other: LumaFingerprint) -> Bool {
        meanAbsDiff(to: other) <= 1.0
    }

    /// Large global luminance jump (>= 48 / 255) indicates a scene cut or black fade; skip interpolation to avoid ghosting.
    func isSceneCut(from other: LumaFingerprint) -> Bool {
        meanAbsDiff(to: other) >= 48.0
    }
}

/// Pure cadence/ordering state machine for 30 -> 60 fps real-time frame interpolation.
/// Enforces monotonic presentation order (A -> mid(A,B) -> B), paces midpoint vs real frame for 60/120 Hz displays,
/// bypasses native 60 fps motion, and drops stale interpolations when a newer real frame arrives.
struct FrameInterpolationScheduler: @unchecked Sendable {
    enum Output: Sendable {
        case real(VideoFrame)
        case interpolated(box: InterpolatedTextureBox, width: Int, height: Int, sourceFrame: VideoFrame)
    }

    struct ReadyJob: Sendable {
        let generation: UInt64
        let previous: VideoFrame
        let current: VideoFrame
        let profile: CoreMLFGProfile
    }

    static let minimumSourceInterval: Double = 0.024  // > ~41.6 fps bypasses interpolation
    static let maximumSourceInterval: Double = 0.065  // < ~15.4 fps resets reference after stalls
    static let fallbackWaitLimit: Double = 0.028      // Never hold a real frame longer than 28 ms

    private(set) var mode: FrameGenerationMode = .off
    private var previousReal: VideoFrame?
    private var previousTime: Double?
    private var pendingReal: VideoFrame?
    private var pendingSince: Double = 0
    private var pendingPairInterval: Double = 1.0 / 30.0
    private var realNotBefore: Double = 0
    private var readyInterpolated: (box: InterpolatedTextureBox, width: Int, height: Int, sourceFrame: VideoFrame, generation: UInt64)?
    private var inFlightGeneration: UInt64?
    private var generation: UInt64 = 0
    private(set) var generatedFrames: Int = 0
    private(set) var skippedInterpolations: Int = 0

    mutating func setMode(_ newMode: FrameGenerationMode) {
        guard newMode != mode else { return }
        mode = newMode
        reset()
    }

    mutating func reset() {
        generation &+= 1
        previousReal = nil
        previousTime = nil
        pendingReal = nil
        pendingSince = 0
        pendingPairInterval = 1.0 / 30.0
        realNotBefore = 0
        readyInterpolated = nil
        inFlightGeneration = nil
    }

    mutating func ingest(
        frame: VideoFrame,
        at hostTime: Double,
        isLive: Bool,
        width: Int,
        height: Int
    ) -> (immediate: Output?, job: ReadyJob?) {
        let timestamp = isLive ? frame.arrivedAt : frame.time
        defer {
            previousReal = frame
            previousTime = timestamp
        }

        guard let profile = mode.profile(width: width, height: height),
              let prev = previousReal,
              let prevTime = previousTime else {
            clearPending()
            return (.real(frame), nil)
        }

        let dt = timestamp - prevTime
        guard dt >= Self.minimumSourceInterval, dt <= Self.maximumSourceInterval else {
            clearPending()
            return (.real(frame), nil)
        }

        let flushed: Output? = pendingReal.map { .real($0) }
        if inFlightGeneration != nil || readyInterpolated != nil {
            skippedInterpolations += 1
        }
        generation &+= 1
        let jobGen = generation
        pendingReal = frame
        pendingSince = hostTime
        pendingPairInterval = dt
        realNotBefore = 0
        readyInterpolated = nil
        inFlightGeneration = jobGen

        return (flushed, ReadyJob(generation: jobGen, previous: prev, current: frame, profile: profile))
    }

    mutating func complete(generation jobGen: UInt64, box: InterpolatedTextureBox, width: Int, height: Int) {
        guard jobGen == inFlightGeneration, let current = pendingReal else { return }
        inFlightGeneration = nil
        readyInterpolated = (box, width, height, current, jobGen)
        generatedFrames += 1
    }

    mutating func complete(generation jobGen: UInt64, texture: any MTLTexture, width: Int, height: Int) {
        complete(generation: jobGen, box: InterpolatedTextureBox(texture), width: width, height: height)
    }

    mutating func fail(generation jobGen: UInt64) {
        guard jobGen == inFlightGeneration else { return }
        inFlightGeneration = nil
        skippedInterpolations += 1
    }

    mutating func pollDisplay(at hostTime: Double) -> Output? {
        if let mid = readyInterpolated {
            readyInterpolated = nil
            // Space the held real frame by roughly half the source interval to avoid 1-1-0-0 judder on 120 Hz displays.
            let spacing = min(0.015, max(0.011, pendingPairInterval * 0.45))
            realNotBefore = hostTime + spacing
            return .interpolated(box: mid.box, width: mid.width, height: mid.height, sourceFrame: mid.sourceFrame)
        }
        if let held = pendingReal {
            if inFlightGeneration == nil {
                if hostTime >= realNotBefore || hostTime - pendingSince >= Self.fallbackWaitLimit {
                    pendingReal = nil
                    realNotBefore = 0
                    return .real(held)
                }
                return nil
            }
            if hostTime - pendingSince >= Self.fallbackWaitLimit {
                generation &+= 1
                inFlightGeneration = nil
                skippedInterpolations += 1
                pendingReal = nil
                realNotBefore = 0
                return .real(held)
            }
        }
        return nil
    }

    private mutating func clearPending() {
        generation &+= 1
        inFlightGeneration = nil
        readyInterpolated = nil
        pendingReal = nil
        pendingSince = 0
        realNotBefore = 0
    }
}

final class LiveFrameInterpolator: @unchecked Sendable {
    private let lock = NSLock()
    private let worker = DispatchQueue(label: "win.xframe.live-frame-generation", qos: .userInitiated)
    private var scheduler = FrameInterpolationScheduler()
    private var lastLiveFingerprint: LumaFingerprint?
    private var lastLiveUniqueTime: Double = 0
    private var weightsURL: URL?
    private var downloadingWeights = false
    private var downloadError: String?
    private var engine: CoreMLFGLiveEngine?
    private var failedProfile: CoreMLFGProfile?
    private let device: any MTLDevice
    private let resourceBundle: Bundle

    init(device: any MTLDevice, resourceBundle: Bundle) {
        self.device = device
        self.resourceBundle = resourceBundle
        self.weightsURL = try? BenchmarkModelCache().cachedModel()
    }

    var mode: FrameGenerationMode {
        lock.withLock { scheduler.mode }
    }

    var isEnabled: Bool { mode != .off }

    var statusNote: String? {
        lock.withLock {
            guard scheduler.mode != .off else { return nil }
            if downloadingWeights { return "Downloading frame-generation model…" }
            if let downloadError { return downloadError }
            if failedProfile != nil { return "Frame generation unavailable for this stream" }
            return nil
        }
    }

    func setMode(_ mode: FrameGenerationMode) {
        let shouldFetch: Bool = lock.withLock {
            scheduler.setMode(mode)
            lastLiveFingerprint = nil
            lastLiveUniqueTime = 0
            failedProfile = nil
            downloadError = nil
            if mode != .off, weightsURL == nil, !downloadingWeights {
                downloadingWeights = true
                return true
            }
            return false
        }
        if shouldFetch {
            Task.detached(priority: .userInitiated) { [weak self] in
                guard let self else { return }
                do {
                    let downloaded = try await BenchmarkModelCache().download(from: BenchmarkReleaseModels.fgURL)
                    self.lock.withLock {
                        self.downloadingWeights = false
                        self.downloadError = nil
                        self.weightsURL = downloaded
                    }
                } catch {
                    self.lock.withLock {
                        self.downloadingWeights = false
                        self.downloadError = "Frame-generation model download failed"
                    }
                }
            }
        }
    }

    func reset() {
        lock.withLock {
            scheduler.reset()
            lastLiveFingerprint = nil
            lastLiveUniqueTime = 0
        }
    }

    func stats() -> (generated: Int, skipped: Int) {
        lock.withLock { (scheduler.generatedFrames, scheduler.skippedInterpolations) }
    }

    func ingest(frame: VideoFrame, at hostTime: Double, isLive: Bool) -> FrameInterpolationScheduler.Output? {
        let width = CVPixelBufferGetWidth(frame.buffer)
        let height = CVPixelBufferGetHeight(frame.buffer)
        let fingerprint = isLive ? LumaFingerprint.capture(from: frame.buffer) : nil

        let (result, weights): ((immediate: FrameInterpolationScheduler.Output?, job: FrameInterpolationScheduler.ReadyJob?), URL?) = lock.withLock {
            guard scheduler.mode != .off, let weights = weightsURL else {
                return ((.real(frame), nil), nil)
            }
            guard let profile = scheduler.mode.profile(width: width, height: height), profile != failedProfile else {
                return ((.real(frame), nil), nil)
            }
            // Suppress duplicated frames emitted by 60 Hz encoders running 30 fps games so unique frames trigger 30->60 FG.
            if isLive, let fingerprint, let previous = lastLiveFingerprint {
                if frame.arrivedAt - lastLiveUniqueTime < FrameInterpolationScheduler.minimumSourceInterval,
                   fingerprint.isNearlyIdentical(to: previous) {
                    return ((nil, nil), nil)
                }
                if fingerprint.isSceneCut(from: previous) {
                    lastLiveFingerprint = fingerprint
                    lastLiveUniqueTime = frame.arrivedAt
                    scheduler.reset()
                    return (scheduler.ingest(frame: frame, at: hostTime, isLive: isLive, width: width, height: height), weights)
                }
            }
            if isLive {
                lastLiveFingerprint = fingerprint
                lastLiveUniqueTime = frame.arrivedAt
            }
            return (scheduler.ingest(frame: frame, at: hostTime, isLive: isLive, width: width, height: height), weights)
        }

        if let job = result.job, let weights {
            worker.async { [weak self] in
                self?.runJob(job, weightsURL: weights)
            }
        }
        return result.immediate
    }

    func pollDisplay(at hostTime: Double) -> FrameInterpolationScheduler.Output? {
        lock.withLock { scheduler.pollDisplay(at: hostTime) }
    }

    private func runJob(_ job: FrameInterpolationScheduler.ReadyJob, weightsURL: URL) {
        let stillCurrent: Bool = lock.withLock {
            scheduler.mode != .off && job.profile != failedProfile
        }
        guard stillCurrent else { return }

        do {
            let activeEngine: CoreMLFGLiveEngine
            if let existing = engine, existing.profile == job.profile {
                activeEngine = existing
            } else {
                engine = nil
                activeEngine = try CoreMLFGLiveEngine(
                    device: device,
                    profile: job.profile,
                    weightsURL: weightsURL,
                    resourceBundle: resourceBundle
                )
                engine = activeEngine
            }
            let box = try activeEngine.interpolate(previous: job.previous, current: job.current)
            lock.withLock {
                scheduler.complete(
                    generation: job.generation,
                    box: box,
                    width: job.profile.width,
                    height: job.profile.height
                )
            }
        } catch {
            lock.withLock {
                failedProfile = job.profile
                scheduler.fail(generation: job.generation)
            }
        }
    }
}

/// Thread-safe texture pool ensuring the renderer never reads a texture while the worker overwrites it.
private final class FGTexturePool: @unchecked Sendable {
    private let lock = NSLock()
    private var available: [any MTLTexture] = []
    private let device: any MTLDevice
    private let width: Int
    private let height: Int

    init(device: any MTLDevice, width: Int, height: Int, initialCount: Int = 3) throws {
        self.device = device
        self.width = width
        self.height = height
        for _ in 0..<initialCount {
            available.append(try Self.makeTexture(device: device, width: width, height: height))
        }
    }

    func acquire() throws -> any MTLTexture {
        if let tex = lock.withLock({ available.popLast() }) {
            return tex
        }
        return try Self.makeTexture(device: device, width: width, height: height)
    }

    func release(_ texture: any MTLTexture) {
        lock.withLock {
            if available.count < 4 { available.append(texture) }
        }
    }

    private static func makeTexture(device: any MTLDevice, width: Int, height: Int) throws -> any MTLTexture {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        desc.usage = [.shaderRead, .shaderWrite]
        desc.storageMode = .private
        guard let tex = device.makeTexture(descriptor: desc) else {
            throw RenderError.unavailable("Cannot allocate live FG output texture.")
        }
        return tex
    }
}

/// Stateful per-profile Core ML (ANE) + Metal live frame generator, confined to LiveFrameInterpolator's serial worker.
private final class CoreMLFGLiveEngine {
    let profile: CoreMLFGProfile
    private let queue: any MTLCommandQueue
    private let cache: CVMetalTextureCache
    private let nv12Pipe: any MTLComputePipelineState
    private let pipes: [any MTLComputePipelineState]
    private var biasUniform: FGBiasUniform
    private var texA: any MTLTexture
    private var texB: any MTLTexture
    private var lastCurrentID: Int?
    private let outputPool: FGTexturePool

    private let cand: SharedTensor
    private let coarse: SharedTensor
    private let feat: SharedTensor
    private let fine: SharedTensor
    private let field: SharedTensor
    private let stage0: CompiledStage
    private let stage1: CompiledStage

    private struct SharedTensor {
        let buffer: any MTLBuffer
        let array: MLMultiArray
        init(device: any MTLDevice, rows: Int, cols: Int, channels: Int) throws {
            let count = rows * cols * channels
            guard let buf = device.makeBuffer(length: count * 2, options: .storageModeShared) else {
                throw RenderError.unavailable("Cannot allocate shared Metal/CoreML tensor buffer.")
            }
            buffer = buf
            array = try MLMultiArray(
                dataPointer: buf.contents(),
                shape: [1, rows, cols, channels].map(NSNumber.init),
                dataType: .float16,
                strides: [count, cols * channels, channels, 1].map(NSNumber.init),
                deallocator: nil
            )
        }
    }

    private struct CompiledStage {
        let model: MLModel
        let input: MLDictionaryFeatureProvider
        let options: MLPredictionOptions
        let output: SharedTensor
        let outputKey: String

        init(compiledURL: URL, inputTensor: SharedTensor, outputTensor: SharedTensor) throws {
            let cfg = MLModelConfiguration()
            cfg.computeUnits = .cpuAndNeuralEngine
            model = try MLModel(contentsOf: compiledURL, configuration: cfg)
            input = try MLDictionaryFeatureProvider(dictionary: ["x": inputTensor.array])
            output = outputTensor
            guard let key = model.modelDescription.outputDescriptionsByName.keys.first else {
                throw RenderError.unavailable("Compiled Core ML FG stage has no output description.")
            }
            outputKey = key
            let opts = MLPredictionOptions()
            opts.outputBackings = [key: outputTensor.array]
            options = opts
        }

        func run() throws {
            let result = try model.prediction(from: input, options: options)
            guard result.featureValue(for: outputKey)?.multiArrayValue?.dataPointer == output.buffer.contents() else {
                throw RenderError.unavailable("Core ML did not honor shared Metal output backing.")
            }
        }
    }

    init(device: any MTLDevice, profile: CoreMLFGProfile, weightsURL: URL, resourceBundle: Bundle) throws {
        self.profile = profile
        guard let queue = device.makeCommandQueue() else {
            throw RenderError.unavailable("Cannot create Metal queue for live frame generation.")
        }
        self.queue = queue
        var cache: CVMetalTextureCache?
        guard CVMetalTextureCacheCreate(nil, nil, device, nil, &cache) == kCVReturnSuccess, let cache else {
            throw RenderError.unavailable("Cannot create CVMetalTextureCache for live frame generation.")
        }
        self.cache = cache

        let templateRoot = try CoreMLFrameGenerationBenchmark.templateDirectory(in: resourceBundle)
        let shaderURL = templateRoot.appendingPathComponent("CoreMLFG.metal")
        let shaderSource = try String(contentsOf: shaderURL, encoding: .utf8)
        let library = try device.makeLibrary(source: shaderSource, options: nil)

        guard let nv12Fn = library.makeFunction(name: "fgNV12ToRGBA") else {
            throw RenderError.unavailable("Missing Metal kernel fgNV12ToRGBA.")
        }
        self.nv12Pipe = try device.makeComputePipelineState(function: nv12Fn)

        let pipeNames = ["fgCandidates", "fgFeatures", "fgMergeFields", "fgCompose"]
        self.pipes = try pipeNames.map { name in
            guard let fn = library.makeFunction(name: name) else {
                throw RenderError.unavailable("Missing Metal kernel \(name).")
            }
            return try device.makeComputePipelineState(function: fn)
        }

        let (b0URL, b1URL, bias) = try CoreMLFrameGenerationBenchmark.prepareCompiledStages(
            profile: profile,
            weightsURL: weightsURL,
            resourceBundle: resourceBundle
        )
        self.biasUniform = bias

        func makeWorkTexture() throws -> any MTLTexture {
            let desc = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba8Unorm,
                width: profile.width,
                height: profile.height,
                mipmapped: false
            )
            desc.usage = [.shaderRead, .shaderWrite]
            desc.storageMode = .private
            guard let tex = device.makeTexture(descriptor: desc) else {
                throw RenderError.unavailable("Cannot allocate live FG Metal texture.")
            }
            return tex
        }

        self.texA = try makeWorkTexture()
        self.texB = try makeWorkTexture()
        self.outputPool = try FGTexturePool(device: device, width: profile.width, height: profile.height)

        let pw = profile.paddedWidth
        let ph = profile.paddedHeight
        self.cand = try SharedTensor(device: device, rows: ph, cols: pw, channels: 16)
        self.coarse = try SharedTensor(device: device, rows: ph / 2, cols: pw / 2, channels: 8)
        self.feat = try SharedTensor(device: device, rows: ph, cols: pw, channels: 18)
        self.fine = try SharedTensor(device: device, rows: ph, cols: pw, channels: 8)
        self.field = try SharedTensor(device: device, rows: ph, cols: pw, channels: 5)
        self.stage0 = try CompiledStage(compiledURL: b0URL, inputTensor: cand, outputTensor: coarse)
        self.stage1 = try CompiledStage(compiledURL: b1URL, inputTensor: feat, outputTensor: fine)
    }

    deinit {
        CVMetalTextureCacheFlush(cache, 0)
    }

    func interpolate(previous: VideoFrame, current: VideoFrame) throws -> InterpolatedTextureBox {
        let w = profile.width
        let h = profile.height
        let pw = profile.paddedWidth
        let ph = profile.paddedHeight
        let scale = profile.scale

        let outTex = try outputPool.acquire()
        var releasedToCaller = false
        defer { if !releasedToCaller { outputPool.release(outTex) } }

        let reusePrevious = lastCurrentID == previous.id
        if reusePrevious { swap(&texA, &texB) }

        func encodeNV12(_ frame: VideoFrame, to dst: any MTLTexture, cb: any MTLCommandBuffer) throws -> VideoTextures {
            let imported = try VideoTextures(frame: frame, cache: cache)
            guard let encoder = cb.makeComputeCommandEncoder() else {
                throw RenderError.unavailable("Cannot create Metal compute encoder for NV12 conversion.")
            }
            encoder.setComputePipelineState(nv12Pipe)
            encoder.setTexture(imported.luma, index: 0)
            encoder.setTexture(imported.chroma, index: 1)
            encoder.setTexture(dst, index: 2)
            var conversion = imported.conversion
            encoder.setBytes(&conversion, length: MemoryLayout<SIMD4<Float>>.size, index: 0)
            encoder.dispatchThreads(
                MTLSize(width: w, height: h, depth: 1),
                threadsPerThreadgroup: MTLSize(width: 16, height: 8, depth: 1)
            )
            encoder.endEncoding()
            return imported
        }

        func dispatch(
            _ cb: any MTLCommandBuffer,
            pipelineIndex: Int,
            textures: [any MTLTexture],
            buffers: [any MTLBuffer],
            includeBias: Bool = false,
            fullRes: Bool = false
        ) throws {
            guard let encoder = cb.makeComputeCommandEncoder() else {
                throw RenderError.unavailable("Cannot create Metal compute encoder for live frame generation.")
            }
            encoder.setComputePipelineState(pipes[pipelineIndex])
            for (idx, tex) in textures.enumerated() { encoder.setTexture(tex, index: idx) }
            for (idx, buf) in buffers.enumerated() { encoder.setBuffer(buf, offset: 0, index: idx) }
            var sizeUniform: [UInt32] = [UInt32(w), UInt32(h), UInt32(pw), UInt32(ph), UInt32(scale)]
            encoder.setBytes(&sizeUniform, length: MemoryLayout<UInt32>.stride * sizeUniform.count, index: buffers.count)
            if includeBias {
                withUnsafeBytes(of: &biasUniform) { bytes in
                    if let base = bytes.baseAddress {
                        encoder.setBytes(base, length: bytes.count, index: buffers.count + 1)
                    }
                }
            }
            encoder.dispatchThreads(
                MTLSize(width: fullRes ? w : pw, height: fullRes ? h : ph, depth: 1),
                threadsPerThreadgroup: MTLSize(width: 16, height: 8, depth: 1)
            )
            encoder.endEncoding()
        }

        func makeCommandBuffer() throws -> any MTLCommandBuffer {
            guard let cb = queue.makeCommandBuffer() else {
                throw RenderError.unavailable("Cannot create Metal command buffer for live frame generation.")
            }
            return cb
        }

        func finish(_ cb: any MTLCommandBuffer) throws {
            cb.commit()
            cb.waitUntilCompleted()
            if let error = cb.error { throw error }
        }

        try autoreleasepool {
            let cb0 = try makeCommandBuffer()
            var retained: [VideoTextures] = []
            if !reusePrevious {
                retained.append(try encodeNV12(previous, to: texA, cb: cb0))
            }
            retained.append(try encodeNV12(current, to: texB, cb: cb0))
            try dispatch(cb0, pipelineIndex: 0, textures: [texA, texB], buffers: [cand.buffer])
            try finish(cb0)
            withExtendedLifetime(retained) {}

            try stage0.run()

            let cb1 = try makeCommandBuffer()
            try dispatch(cb1, pipelineIndex: 1, textures: [], buffers: [cand.buffer, coarse.buffer, feat.buffer], includeBias: true)
            try finish(cb1)

            try stage1.run()

            let cb2 = try makeCommandBuffer()
            try dispatch(cb2, pipelineIndex: 2, textures: [], buffers: [feat.buffer, fine.buffer, field.buffer], includeBias: true)
            try dispatch(cb2, pipelineIndex: 3, textures: [texA, texB, outTex], buffers: [field.buffer], fullRes: true)
            try finish(cb2)
        }

        lastCurrentID = current.id
        releasedToCaller = true
        let pool = outputPool
        return InterpolatedTextureBox(outTex) { tex in pool.release(tex) }
    }
}
