import AVFoundation
import MetalFX
import QuartzCore
import VideoToolbox

enum BenchmarkGrade: String, Codable, Sendable {
    case headroom, tight, overBudget, unavailable, failed

    static func assess(p95MS: Double, budgetMS: Double) -> Self {
        if p95MS <= budgetMS * 0.7 { return .headroom }
        if p95MS <= budgetMS { return .tight }
        return .overBudget
    }

    var title: String {
        switch self {
        case .headroom: "Headroom"
        case .tight: "Tight"
        case .overBudget: "Over budget"
        case .unavailable: "Unavailable"
        case .failed: "Failed"
        }
    }
}

struct BenchmarkMeasurement: Codable, Identifiable, Sendable {
    let id: String
    let title: String
    let detail: String
    let timing: String
    let samples: Int
    let medianMS: Double?
    let p95MS: Double?
    let budgetMS: Double
    let grade: BenchmarkGrade

    static func unavailable(_ id: String, _ title: String, detail: String, budgetMS: Double) -> Self {
        Self(id: id, title: title, detail: detail, timing: "none", samples: 0,
             medianMS: nil, p95MS: nil, budgetMS: budgetMS, grade: .unavailable)
    }
    static func failed(_ id: String, _ title: String, error: Error, budgetMS: Double) -> Self {
        Self(id: id, title: title, detail: error.localizedDescription, timing: "none", samples: 0,
             medianMS: nil, p95MS: nil, budgetMS: budgetMS, grade: .failed)
    }
    static func measured(_ id: String, _ title: String, detail: String, timing: String,
                         values: [Double], budgetMS: Double) -> Self {
        let sorted = values.sorted()
        let median = sorted[sorted.count / 2]
        let p95 = sorted[Int(ceil(Double(sorted.count) * 0.95)) - 1]
        return Self(id: id, title: title, detail: detail, timing: timing, samples: values.count,
                    medianMS: median, p95MS: p95, budgetMS: budgetMS,
                    grade: .assess(p95MS: p95, budgetMS: budgetMS))
    }
}

struct PostProcessingBenchmarkReport: Codable, Sendable {
    let date: Date
    let device: String
    let macOS: String
    let fixture: String
    let measurements: [BenchmarkMeasurement]
    let notes: [String]

    var capacitySummary: String {
        let spatial = measurements.reversed().first {
            $0.id.hasPrefix("spatial") && $0.grade == .headroom
        }
        let spatialText = spatial.map { "\($0.title) has measured headroom" }
            ?? "No tested MetalFX tier has clear 60 Hz headroom"
        let frameText: String
        if let best = measurements.reversed().first(where: {
            $0.id.hasPrefix("vt") && $0.grade == .headroom
        }) {
            frameText = "\(best.title) has measured headroom at that input size"
        } else if let tight = measurements.first(where: {
            $0.id.hasPrefix("vt") && $0.grade == .tight
        }) {
            frameText = "\(tight.title) is close to its time budget"
        } else {
            frameText = "No tested frame-generation tier has clear time-budget headroom"
        }
        let mlxText: String
        if let best = measurements.reversed().first(where: {
            $0.id.hasPrefix("mlx") && $0.grade == .headroom
        }) {
            mlxText = "; \(best.title) has research-path headroom"
        } else if measurements.contains(where: { $0.id.hasPrefix("mlx") }) {
            mlxText = "; no tested MLX-DLSS video tier has 30 → 60 fps headroom"
        } else {
            mlxText = ""
        }
        return "\(spatialText); \(frameText)\(mlxText)."
    }
}

private struct BenchmarkVideoFrame {
    let buffer: CVPixelBuffer
    let pts: CMTime
}

// The interface is one bounded run. Setup/decode is separate from timed work;
// unsupported backends return an explicit row rather than a synthetic score.
enum PostProcessingBenchmark {
    static let fixtureSHA256 = "5872055dcb979f5d469ede9c575e60418bc9d7731e0528c05ee0817cc0b08633"
    static let spatialBudgetMS = 1000.0 / 60.0
    static let interpolationBudgetMS = 1000.0 / 30.0

    static func run(weightsURL: URL? = nil,
                    progress: @Sendable (String) -> Void) async throws -> PostProcessingBenchmarkReport {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw RenderError.unavailable("No Metal device is available.")
        }
        progress("Preparing bundled video…")
        let frames = try await decodeFixture()
        try Task.checkCancellation()
        var textureCache: CVMetalTextureCache?
        guard CVMetalTextureCacheCreate(nil, nil, device, nil, &textureCache) == kCVReturnSuccess,
              let textureCache else {
            throw RenderError.unavailable("Cannot import the benchmark video into Metal.")
        }
        let source = try VideoTextures(frame: VideoFrame(buffer: frames[30].buffer, time: 0, id: 30),
                                       cache: textureCache)
        var measurements: [BenchmarkMeasurement] = []
        for (id, title, width, height, sharpen) in [
            ("spatial1440", "MetalFX 1080p → 1440p", 2560, 1440, false),
            ("spatial4k", "MetalFX 1080p → 4K", 3840, 2160, false),
            ("spatial4kSharpen", "MetalFX 1080p → 4K + High sharpening", 3840, 2160, true)
        ] {
            try Task.checkCancellation()
            progress("Testing \(title)…")
            do {
                measurements.append(try measureSpatial(device: device, source: source, id: id,
                    title: title, output: ScalingExtent(width: width, height: height), sharpen: sharpen))
            } catch is CancellationError { throw CancellationError() }
            catch { measurements.append(.failed(id, title, error: error, budgetMS: spatialBudgetMS)) }
        }
        for (width, height) in [(1280, 720), (1920, 1080), (2560, 1440)] {
            try Task.checkCancellation()
            let id = "vt\(height)", title = "VideoToolbox \(height)p 30 → 60 fps"
            progress("Testing \(title)…")
            do { measurements.append(try await measureInterpolation(frames: frames, width: width, height: height)) }
            catch is CancellationError { throw CancellationError() }
            catch { measurements.append(.failed(id, title, error: error, budgetMS: interpolationBudgetMS)) }
        }
        var notes = [
            "Headroom uses at most 70% of the relevant frame interval; Tight uses up to 100%. Frame-generation grades apply to a native stream at the tested input size; resizing the fixture is outside timing. These are offline capacity hints, not an in-game FPS or latency guarantee.",
            "MetalFX timings are GPU command intervals on a decoded NV12 video still, including color conversion. VideoToolbox timings are processor completion wall time over consecutive real video frames resized before timing where needed; its internal GPU time is not exposed."
        ]
        if let weightsURL {
            do {
                let digest = try MLXFrameGenerationBenchmark.modelDigest(weightsURL)
                notes.append("Selected MLX-DLSS model SHA-256: \(digest). The selected file remains at its original location and is not copied into the app or report.")
                for (width, height) in [(1280, 720), (1920, 1080), (2560, 1440)] {
                    try Task.checkCancellation()
                    let id = "mlx\(height)", title = "MLX-DLSS video \(height)p 30 → 60 fps"
                    progress("Testing \(title)…")
                    do {
                        measurements.append(try await MLXFrameGenerationBenchmark.measure(
                            frames: frames.map(\.buffer), width: width, height: height, weightsURL: weightsURL))
                    } catch is CancellationError { throw CancellationError() }
                    catch { measurements.append(.failed(id, title, error: error, budgetMS: interpolationBudgetMS)) }
                }
            } catch is CancellationError { throw CancellationError() }
            catch {
                for height in [720, 1080, 1440] {
                    measurements.append(.failed("mlx\(height)", "MLX-DLSS video \(height)p 30 → 60 fps",
                        error: RenderError.unavailable("Cannot read the selected model file."),
                        budgetMS: interpolationBudgetMS))
                }
            }
            notes.append("MLX-DLSS is a separate video research port with no game motion vectors or depth. Its helper round-trip wall time includes RGB transfer, not decoder or display latency; it is not a live XFrame backend.")
        } else {
            notes.append("MLX-DLSS was not selected. Its proprietary weights are not bundled; choose a local model file to run its optional research-path benchmark.")
        }
        return PostProcessingBenchmarkReport(date: Date(), device: device.name,
            macOS: ProcessInfo.processInfo.operatingSystemVersionString,
            fixture: "Big Buck Bunny, silent 1920×1080 H.264, 30 fps, SHA-256 \(fixtureSHA256)",
            measurements: measurements, notes: notes)
    }

    private static func resourceBundle() throws -> Bundle {
        if Bundle.main.bundleURL.pathExtension == "app" {
            guard let root = Bundle.main.resourceURL,
                  let bundle = Bundle(url: root.appendingPathComponent("XFrame_XFrame.bundle")) else {
                throw RenderError.unavailable("The XFrame resource bundle is missing.")
            }
            return bundle
        }
        return Bundle.module
    }

    private static func decodeFixture() async throws -> [BenchmarkVideoFrame] {
        let bundle = try resourceBundle()
        guard let url = bundle.url(forResource: "BigBuckBunny-1080p30", withExtension: "mp4") else {
            throw RenderError.unavailable("The benchmark video is missing from the app.")
        }
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw RenderError.unavailable("The benchmark video has no video track.")
        }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any]
        ])
        reader.add(output)
        guard reader.startReading() else {
            throw reader.error ?? RenderError.unavailable("Cannot decode the benchmark video.")
        }
        var frames: [BenchmarkVideoFrame] = []
        while frames.count < 61, let sample = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            if let buffer = CMSampleBufferGetImageBuffer(sample) {
                frames.append(BenchmarkVideoFrame(buffer: buffer,
                                                  pts: CMSampleBufferGetPresentationTimeStamp(sample)))
            }
        }
        reader.cancelReading()
        guard frames.count == 61 else {
            throw RenderError.unavailable("The benchmark video decoded only \(frames.count) of 61 required frames.")
        }
        return frames
    }

    private static func measureSpatial(device: any MTLDevice, source: VideoTextures,
                                       id: String, title: String, output: ScalingExtent,
                                       sharpen: Bool) throws -> BenchmarkMeasurement {
        guard MTLFXSpatialScalerDescriptor.supportsDevice(device),
              let queue = device.makeCommandQueue() else {
            return .unavailable(id, title, detail: "MetalFX Spatial is unavailable on this GPU.",
                                budgetMS: spatialBudgetMS)
        }
        let scaler = try SpatialUpscaler(device: device, source: ScalingExtent(width: 1920, height: 1080),
                                        output: output)
        let shaderURL = try resourceBundle().url(forResource: "Shaders", withExtension: "metal")
        guard let shaderURL else { throw RenderError.unavailable("Rendering shaders are missing.") }
        let shader = try String(contentsOf: shaderURL, encoding: .utf8)
        let library = try device.makeLibrary(source: shader, options: nil)
        func pipeline(_ fragment: String) throws -> any MTLRenderPipelineState {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "patternVertex")
            descriptor.fragmentFunction = library.makeFunction(name: fragment)
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            return try device.makeRenderPipelineState(descriptor: descriptor)
        }
        let conversion = try pipeline("videoFragment")
        let composition = try pipeline(sharpen ? "sharpenFragment" : "patternFragment")
        let targetDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
            width: output.width, height: output.height, mipmapped: false)
        targetDescriptor.storageMode = .private
        targetDescriptor.usage = .renderTarget
        guard let target = device.makeTexture(descriptor: targetDescriptor) else {
            throw RenderError.unavailable("Cannot allocate the \(title) output texture.")
        }
        var gpu: [Double] = [], wall: [Double] = []
        for iteration in 0..<65 {
            try Task.checkCancellation()
            guard let command = queue.makeCommandBuffer() else {
                throw RenderError.unavailable("Cannot create a Metal command buffer.")
            }
            let firstPass = MTLRenderPassDescriptor()
            firstPass.colorAttachments[0].texture = scaler.input
            firstPass.colorAttachments[0].loadAction = .dontCare
            firstPass.colorAttachments[0].storeAction = .store
            guard let first = command.makeRenderCommandEncoder(descriptor: firstPass) else {
                throw RenderError.unavailable("Cannot encode MetalFX input conversion.")
            }
            first.setRenderPipelineState(conversion)
            first.setFragmentTexture(source.luma, index: 0)
            first.setFragmentTexture(source.chroma, index: 1)
            var colorConversion = source.conversion
            first.setFragmentBytes(&colorConversion, length: MemoryLayout<SIMD4<Float>>.size, index: 0)
            first.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            first.endEncoding()
            scaler.scaler.encode(commandBuffer: command)
            let finalPass = MTLRenderPassDescriptor()
            finalPass.colorAttachments[0].texture = target
            finalPass.colorAttachments[0].loadAction = .dontCare
            finalPass.colorAttachments[0].storeAction = .store
            guard let final = command.makeRenderCommandEncoder(descriptor: finalPass) else {
                throw RenderError.unavailable("Cannot encode MetalFX output composition.")
            }
            final.setRenderPipelineState(composition)
            final.setFragmentTexture(scaler.output, index: 0)
            if sharpen {
                var amount = SharpeningPreset.high.amount
                final.setFragmentBytes(&amount, length: MemoryLayout<Float>.size, index: 0)
            }
            final.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            final.endEncoding()
            let started = CACurrentMediaTime()
            command.commit()
            command.waitUntilCompleted()
            guard command.status == .completed else {
                throw command.error ?? RenderError.unavailable("MetalFX GPU processing failed.")
            }
            if iteration >= 5 {
                wall.append((CACurrentMediaTime() - started) * 1000)
                if command.gpuStartTime > 0, command.gpuEndTime >= command.gpuStartTime {
                    gpu.append((command.gpuEndTime - command.gpuStartTime) * 1000)
                }
            }
        }
        let values = gpu.count == 60 ? gpu : wall
        return .measured(id, title, detail: "60 offscreen submissions after five warmups; includes input conversion, MetalFX and final composition.",
                         timing: gpu.count == 60 ? "GPU command" : "GPU completion wall (fallback)",
                         values: values, budgetMS: spatialBudgetMS)
    }

    private static func resizeVideoFrames(_ frames: [BenchmarkVideoFrame], width: Int, height: Int) throws -> [BenchmarkVideoFrame] {
        if width == 1920 && height == 1080 { return frames }
        var session: VTPixelTransferSession?
        let sessionStatus = VTPixelTransferSessionCreate(allocator: kCFAllocatorDefault,
                                                        pixelTransferSessionOut: &session)
        guard sessionStatus == noErr, let session else {
            throw RenderError.unavailable("Cannot create a video resize session (\(sessionStatus)).")
        }
        defer { VTPixelTransferSessionInvalidate(session) }
        let attributes: [String: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any],
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]
        return try frames.map { frame in
            try Task.checkCancellation()
            var output: CVPixelBuffer?
            let allocation = CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, attributes as CFDictionary, &output)
            guard allocation == kCVReturnSuccess, let output else {
                throw RenderError.unavailable("Cannot allocate \(width)×\(height) video surface (\(allocation)).")
            }
            let transfer = VTPixelTransferSessionTransferImage(session, from: frame.buffer, to: output)
            guard transfer == noErr else {
                throw RenderError.unavailable("Cannot resize benchmark video (\(transfer)).")
            }
            return BenchmarkVideoFrame(buffer: output, pts: frame.pts)
        }
    }

    private static func measureInterpolation(frames: [BenchmarkVideoFrame], width: Int, height: Int) async throws -> BenchmarkMeasurement {
        let id = "vt\(height)", title = "VideoToolbox \(height)p 30 → 60 fps"
        guard VTLowLatencyFrameInterpolationConfiguration.isSupported,
              let config = VTLowLatencyFrameInterpolationConfiguration(frameWidth: width,
                  frameHeight: height, numberOfInterpolatedFrames: 1) else {
            return .unavailable(id, title, detail: "VideoToolbox low-latency interpolation is unavailable.",
                                budgetMS: interpolationBudgetMS)
        }
        if let maxPixels = VTLowLatencyFrameInterpolationConfiguration.maximumPixelCount(forSpatialScaleFactor: 1),
           maxPixels < width * height {
            return .unavailable(id, title, detail: "This device supports at most \(maxPixels) pixels for interpolation.",
                                budgetMS: interpolationBudgetMS)
        }
        if let maxDimension = VTLowLatencyFrameInterpolationConfiguration.maximumDimension(forSpatialScaleFactor: 1),
           maxDimension < max(width, height) {
            return .unavailable(id, title, detail: "This device supports at most \(maxDimension) pixels per dimension for interpolation.",
                                budgetMS: interpolationBudgetMS)
        }
        let input = try resizeVideoFrames(frames, width: width, height: height)
        let processor = VTFrameProcessor()
        try processor.startSession(configuration: config)
        defer { processor.endSession() }
        let attrs = config.destinationPixelBufferAttributes
        guard let format = attrs[kCVPixelBufferPixelFormatTypeKey as String] as? OSType else {
            throw RenderError.unavailable("VideoToolbox did not specify an output pixel format.")
        }
        var times: [Double] = []
        for index in 1..<61 {
            try Task.checkCancellation()
            var destination: CVPixelBuffer?
            let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, format,
                                             attrs as CFDictionary, &destination)
            guard status == kCVReturnSuccess, let destination,
                  let before = VTFrameProcessorFrame(buffer: input[index - 1].buffer,
                                                     presentationTimeStamp: input[index - 1].pts),
                  let after = VTFrameProcessorFrame(buffer: input[index].buffer,
                                                    presentationTimeStamp: input[index].pts),
                  let middle = VTFrameProcessorFrame(buffer: destination,
                       presentationTimeStamp: CMTimeMultiplyByFloat64(
                           CMTimeAdd(input[index - 1].pts, input[index].pts), multiplier: 0.5)),
                  let params = VTLowLatencyFrameInterpolationParameters(sourceFrame: after,
                      previousFrame: before, interpolationPhase: [0.5], destinationFrames: [middle]) else {
                throw RenderError.unavailable("Cannot prepare VideoToolbox interpolation surfaces (\(status)).")
            }
            let started = CACurrentMediaTime()
            var outputs = 0
            for try await _ in processor.process(parameters: params) { outputs += 1 }
            guard outputs == 1 else {
                throw RenderError.unavailable("VideoToolbox returned \(outputs) output frames.")
            }
            if index > 5 { times.append((CACurrentMediaTime() - started) * 1000) }
        }
        return .measured(id, title, detail: "55 consecutive video-frame pairs after five warmups; native-size stream assumed; fixture resizing is outside timing; processor wall time, not GPU kernel time.",
                         timing: "Processor wall", values: times, budgetMS: interpolationBudgetMS)
    }
}
