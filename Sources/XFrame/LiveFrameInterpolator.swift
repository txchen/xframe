import CoreImage
import CoreML
import CryptoKit
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
    init(_ texture: any MTLTexture) { self.texture = texture }
}

/// Pure cadence/ordering state machine for 30 → 60 fps real-time frame interpolation.
/// Enforces monotonic presentation order (A → mid(A,B) → B), bypasses ~60 fps streams,
/// and drops stale interpolations when a newer real frame arrives before completion.
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
    static let maximumSourceInterval: Double = 0.065  // > ~15.4 fps resets reference after stalls
    static let fallbackWaitLimit: Double = 0.028      // Never hold a real frame longer than 28 ms

    private(set) var mode: FrameGenerationMode = .off
    private var previousReal: VideoFrame?
    private var previousTime: Double?
    private var pendingReal: VideoFrame?
    private var pendingSince: Double = 0
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
        readyInterpolated = nil
        inFlightGeneration = nil
    }

    /// Ingest a newly dequeued real frame. Returns an immediate output if it should be displayed now,
    /// and an optional background interpolation job to run for (previous → current).
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
            // Stream is already ~60 fps or recovering from a long stall: pass through directly.
            clearPending()
            return (.real(frame), nil)
        }

        // If a previous real frame was still held waiting for an unfinished interpolation,
        // flush it immediately so we never accumulate backlog.
        let flushed: Output? = pendingReal.map { .real($0) }
        if inFlightGeneration != nil {
            skippedInterpolations += 1
        }
        generation &+= 1
        let jobGen = generation
        pendingReal = frame
        pendingSince = hostTime
        readyInterpolated = nil
        inFlightGeneration = jobGen

        return (flushed, ReadyJob(generation: jobGen, previous: prev, current: frame, profile: profile))
    }

    mutating func complete(generation jobGen: UInt64, texture: any MTLTexture, width: Int, height: Int) {
        guard jobGen == inFlightGeneration, let current = pendingReal else { return }
        inFlightGeneration = nil
        readyInterpolated = (InterpolatedTextureBox(texture), width, height, current, jobGen)
        generatedFrames += 1
    }

    mutating func fail(generation jobGen: UInt64) {
        guard jobGen == inFlightGeneration else { return }
        inFlightGeneration = nil
        skippedInterpolations += 1
    }

    /// Called on each display tick (60 Hz) when no new real frame was dequeued yet.
    /// Delivers the interpolated midpoint first, then the held real frame on the next tick.
    mutating func pollDisplay(at hostTime: Double) -> Output? {
        if let mid = readyInterpolated {
            readyInterpolated = nil
            return .interpolated(box: mid.box, width: mid.width, height: mid.height, sourceFrame: mid.sourceFrame)
        }
        if let held = pendingReal {
            if inFlightGeneration == nil {
                pendingReal = nil
                return .real(held)
            }
            if hostTime - pendingSince >= Self.fallbackWaitLimit {
                // Interpolation took too long: release real frame now and abandon stale mid-frame.
                generation &+= 1
                inFlightGeneration = nil
                skippedInterpolations += 1
                pendingReal = nil
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
    }
}

/// Thread-safe live Core ML (ANE) + Metal 30 → 60 fps interpolator used by MetalRenderer.
final class LiveFrameInterpolator: @unchecked Sendable {
    private let lock = NSLock()
    private let worker = DispatchQueue(label: "win.xframe.live-frame-generation", qos: .userInitiated)
    private var scheduler = FrameInterpolationScheduler()
    private var weightsURL: URL?
    private var downloadingWeights = false
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

    func setMode(_ mode: FrameGenerationMode) {
        let shouldFetch: Bool = lock.withLock {
            scheduler.setMode(mode)
            failedProfile = nil
            if mode != .off, weightsURL == nil, !downloadingWeights {
                downloadingWeights = true
                return true
            }
            return false
        }
        if shouldFetch {
            Task.detached(priority: .userInitiated) { [weak self] in
                guard let self else { return }
                let downloaded = try? await BenchmarkModelCache().download(from: BenchmarkReleaseModels.fgURL)
                self.lock.withLock {
                    self.downloadingWeights = false
                    if let downloaded { self.weightsURL = downloaded }
                }
            }
        }
    }

    func reset() {
        lock.withLock {
            scheduler.reset()
        }
    }

    func stats() -> (generated: Int, skipped: Int) {
        lock.withLock { (scheduler.generatedFrames, scheduler.skippedInterpolations) }
    }

    func ingest(frame: VideoFrame, at hostTime: Double, isLive: Bool) -> FrameInterpolationScheduler.Output? {
        let width = CVPixelBufferGetWidth(frame.buffer)
        let height = CVPixelBufferGetHeight(frame.buffer)
        let (result, weights): ((immediate: FrameInterpolationScheduler.Output?, job: FrameInterpolationScheduler.ReadyJob?), URL?) = lock.withLock {
            guard scheduler.mode != .off else {
                return ((.real(frame), nil), nil)
            }
            guard let weights = weightsURL else {
                return ((.real(frame), nil), nil)
            }
            if let profile = scheduler.mode.profile(width: width, height: height), profile == failedProfile {
                return ((.real(frame), nil), nil)
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
            let texture = try activeEngine.interpolate(previous: job.previous.buffer, current: job.current.buffer)
            lock.withLock {
                scheduler.complete(
                    generation: job.generation,
                    texture: texture,
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

/// Stateful per-profile Core ML (ANE) + Metal live frame generator.
/// Confined to LiveFrameInterpolator's serial worker queue.
private final class CoreMLFGLiveEngine {
    let profile: CoreMLFGProfile
    private let queue: any MTLCommandQueue
    private let ciContext: CIContext
    private let colorSpace = CGColorSpaceCreateDeviceRGB()
    private let pipes: [any MTLComputePipelineState]
    private var biasUniform: FGBiasUniform
    private let texA: any MTLTexture
    private let texB: any MTLTexture
    private let outputRing: [any MTLTexture]
    private var outputIndex = 0

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
        self.ciContext = CIContext(mtlCommandQueue: queue, options: [.cacheIntermediates: false])

        let templateRoot = try CoreMLFrameGenerationBenchmark.templateDirectory(in: resourceBundle)
        let shaderURL = templateRoot.appendingPathComponent("CoreMLFG.metal")
        let shaderSource = try String(contentsOf: shaderURL, encoding: .utf8)
        let library = try device.makeLibrary(source: shaderSource, options: nil)
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

        func makeTexture() throws -> any MTLTexture {
            let desc = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba8Unorm,
                width: profile.width,
                height: profile.height,
                mipmapped: false
            )
            desc.usage = [.shaderRead, .shaderWrite, .renderTarget]
            desc.storageMode = .shared
            guard let tex = device.makeTexture(descriptor: desc) else {
                throw RenderError.unavailable("Cannot allocate live FG Metal texture.")
            }
            return tex
        }

        self.texA = try makeTexture()
        self.texB = try makeTexture()
        // Triple-buffered output textures so the renderer can safely read the previous
        // interpolated texture while the worker synthesizes the next one.
        self.outputRing = [try makeTexture(), try makeTexture(), try makeTexture()]

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

    func interpolate(previous: CVPixelBuffer, current: CVPixelBuffer) throws -> any MTLTexture {
        let w = profile.width
        let h = profile.height
        let pw = profile.paddedWidth
        let ph = profile.paddedHeight
        let scale = profile.scale

        let outTex = outputRing[outputIndex]
        outputIndex = (outputIndex + 1) % outputRing.count

        func renderToTexture(_ pb: CVPixelBuffer, _ tex: any MTLTexture, cb: any MTLCommandBuffer) {
            let image = CIImage(cvPixelBuffer: pb)
            let flipped = image.transformed(by: CGAffineTransform(
                a: CGFloat(w) / image.extent.width, b: 0,
                c: 0, d: -CGFloat(h) / image.extent.height,
                tx: 0, ty: CGFloat(h)
            ))
            ciContext.render(
                flipped, to: tex, commandBuffer: cb,
                bounds: CGRect(x: 0, y: 0, width: w, height: h),
                colorSpace: colorSpace
            )
        }

        func dispatch(
            _ cb: any MTLCommandBuffer,
            pipelineIndex: Int,
            textures: [any MTLTexture],
            buffers: [any MTLBuffer],
            includeBias: Bool = false,
            fullRes: Bool = false
        ) {
            let encoder = cb.makeComputeCommandEncoder()!
            encoder.setComputePipelineState(pipes[pipelineIndex])
            for (idx, tex) in textures.enumerated() { encoder.setTexture(tex, index: idx) }
            for (idx, buf) in buffers.enumerated() { encoder.setBuffer(buf, offset: 0, index: idx) }
            var sizeUniform: [UInt32] = [UInt32(w), UInt32(h), UInt32(pw), UInt32(ph), UInt32(scale)]
            encoder.setBytes(&sizeUniform, length: MemoryLayout<UInt32>.stride * sizeUniform.count, index: buffers.count)
            if includeBias {
                withUnsafeBytes(of: &biasUniform) { bytes in
                    encoder.setBytes(bytes.baseAddress!, length: bytes.count, index: buffers.count + 1)
                }
            }
            encoder.dispatchThreads(
                MTLSize(width: fullRes ? w : pw, height: fullRes ? h : ph, depth: 1),
                threadsPerThreadgroup: MTLSize(width: 16, height: 8, depth: 1)
            )
            encoder.endEncoding()
        }

        func finish(_ cb: any MTLCommandBuffer) throws {
            cb.commit()
            cb.waitUntilCompleted()
            if let error = cb.error { throw error }
        }

        try autoreleasepool {
            let cb0 = queue.makeCommandBuffer()!
            renderToTexture(previous, texA, cb: cb0)
            renderToTexture(current, texB, cb: cb0)
            dispatch(cb0, pipelineIndex: 0, textures: [texA, texB], buffers: [cand.buffer])
            try finish(cb0)

            try stage0.run()

            let cb1 = queue.makeCommandBuffer()!
            dispatch(cb1, pipelineIndex: 1, textures: [], buffers: [cand.buffer, coarse.buffer, feat.buffer], includeBias: true)
            try finish(cb1)

            try stage1.run()

            let cb2 = queue.makeCommandBuffer()!
            dispatch(cb2, pipelineIndex: 2, textures: [], buffers: [feat.buffer, fine.buffer, field.buffer], includeBias: true)
            dispatch(cb2, pipelineIndex: 3, textures: [texA, texB, outTex], buffers: [field.buffer], fullRes: true)
            try finish(cb2)
        }
        return outTex
    }
}
