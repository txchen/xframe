import MetalKit

enum RenderError: LocalizedError {
    case unavailable(String)
    var errorDescription: String? {
        switch self { case .unavailable(let message): message }
    }
}

@MainActor
final class MetalRenderer: NSObject, MTKViewDelegate {
    private let queue: any MTLCommandQueue
    private let pipeline: any MTLRenderPipelineState
    private let texture: any MTLTexture
    private let videoPipeline: any MTLRenderPipelineState
    private let cache: CVMetalTextureCache
    private var currentVideo: VideoTextures?
    private var source: (any VideoSource)?
    private let inFlight = DispatchSemaphore(value: 3)
    private var lastDrawableSize = CGSize.zero
    private var lastReport = 0.0
    private var work = RenderWorkState()
    var report: ((PlaybackStats) -> Void)?

    init(view: MTKView) throws {
        guard let device = view.device, let queue = device.makeCommandQueue() else {
            throw RenderError.unavailable("Unable to create the Metal command queue.")
        }
        let resourceBundle: Bundle
        if Bundle.main.bundleURL.pathExtension == "app" {
            guard let resources = Bundle.main.resourceURL,
                  let bundled = Bundle(url: resources.appendingPathComponent("XFrame_XFrame.bundle")) else {
                throw RenderError.unavailable("The app's rendering resource bundle is missing.")
            }
            resourceBundle = bundled
        } else {
            resourceBundle = Bundle.module
        }
        guard let url = resourceBundle.url(forResource: "Shaders", withExtension: "metal") else {
            throw RenderError.unavailable("The rendering shaders are missing.")
        }
        let source = try String(contentsOf: url, encoding: .utf8)
        let library = try device.makeLibrary(source: source, options: nil)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "patternVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "patternFragment")
        descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        descriptor.fragmentFunction = library.makeFunction(name: "videoFragment")
        videoPipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        var cache: CVMetalTextureCache?
        guard CVMetalTextureCacheCreate(nil, nil, device, nil, &cache) == kCVReturnSuccess, let cache else {
            throw RenderError.unavailable("Unable to create the video texture cache.")
        }
        self.cache = cache
        texture = try TestPattern.makeTexture(device: device)
        self.queue = queue
        super.init()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func play(_ source: (any VideoSource)?, in view: MTKView) {
        self.source?.stop()
        self.source = source
        currentVideo = nil
        work = RenderWorkState()
        lastDrawableSize = .zero
        view.enableSetNeedsDisplay = source == nil
        view.isPaused = source == nil
        view.preferredFramesPerSecond = 120
        view.needsDisplay = true
    }

    func draw(in view: MTKView) {
        let now = CACurrentMediaTime()
        source?.performance.note(.draw, at: now)
        if let source, now - lastReport >= 1.0 {
            lastReport = now
            let stats = source.snapshot()
            report?(stats)
            if stats.state == "Ended" || stats.state.hasPrefix("Failed:") {
                view.isPaused = true
                view.enableSetNeedsDisplay = true
            }
        }
        guard inFlight.wait(timeout: .now()) == .success else { source?.performance.note(.busy); return }
        var committed = false
        defer { if !committed { inFlight.signal() } }
        guard view.drawableSize.width > 0, view.drawableSize.height > 0 else { return }

        let next = source?.nextFrame(at: now)
        if let next {
            do {
                currentVideo = try VideoTextures(frame: next, cache: cache)
                if work.receivedFrame() { source?.didSkipFrame() }
            }
            catch {
                source?.fail(error.localizedDescription)
                if let source { report?(source.snapshot()) }
                view.isPaused = true
                return
            }
        }
        guard work.needsDraw(hasSource: source != nil, resized: lastDrawableSize != view.drawableSize) else { return }
        // Acquire scarce drawables only after determining that work is necessary.
        let drawableStarted = CACurrentMediaTime()
        let renderPass = view.currentRenderPassDescriptor
        let acquiredDrawable = view.currentDrawable
        source?.performance.record(.drawableWait, seconds: CACurrentMediaTime() - drawableStarted)
        guard let pass = renderPass, let drawable = acquiredDrawable,
              let command = queue.makeCommandBuffer() else { source?.performance.note(.drawableMiss); return }
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return }
        lastDrawableSize = view.drawableSize

        // Use the actual drawable's pixels, never the window's logical points.
        let width = Double(drawable.texture.width)
        let height = Double(drawable.texture.height)
        let imageWidth = currentVideo?.luma.width ?? texture.width
        let imageHeight = currentVideo?.luma.height ?? texture.height
        let scale = min(width / Double(imageWidth), height / Double(imageHeight))
        let fittedWidth = Double(imageWidth) * scale
        let fittedHeight = Double(imageHeight) * scale
        encoder.setViewport(MTLViewport(
            originX: (width - fittedWidth) / 2, originY: (height - fittedHeight) / 2,
            width: fittedWidth, height: fittedHeight, znear: 0, zfar: 1
        ))
        if let video = currentVideo {
            encoder.setRenderPipelineState(videoPipeline)
            encoder.setFragmentTexture(video.luma, index: 0)
            encoder.setFragmentTexture(video.chroma, index: 1)
            var conversion = video.conversion
            encoder.setFragmentBytes(&conversion, length: MemoryLayout<SIMD4<Float>>.size, index: 0)
        } else {
            encoder.setRenderPipelineState(pipeline)
            encoder.setFragmentTexture(texture, index: 0)
        }
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        let retainedVideo = currentVideo
        let permit = inFlight
        let activeSource = source
        let sample: FramePresentation?
        if work.pendingFrame, let source, let frame = currentVideo?.frame {
            sample = FramePresentation(source: source, arrivedAt: frame.arrivedAt, submittedAt: CACurrentMediaTime())
        } else { sample = nil }
        command.addCompletedHandler { command in
            withExtendedLifetime(retainedVideo) {}
            if command.status == .error {
                activeSource?.fail("Metal rendering failed: \(command.error?.localizedDescription ?? "Unknown GPU error")")
            }
            if command.status == .completed, command.gpuStartTime > 0, command.gpuEndTime >= command.gpuStartTime {
                sample?.gpuCompleted(start: command.gpuStartTime, end: command.gpuEndTime)
            }
            permit.signal()
        }
        if let sample {
            drawable.addPresentedHandler { presented in sample.presented(at: presented.presentedTime) }
        }
        command.present(drawable)
        committed = true
        work.submitted()
        command.commit()
    }
}

// Retain both CoreVideo texture wrappers and the decode surface until GPU completion.
final class VideoTextures: @unchecked Sendable {
    let frame: VideoFrame
    let planes: [CVMetalTexture]
    let luma: any MTLTexture
    let chroma: any MTLTexture
    let conversion: SIMD4<Float>

    init(frame: VideoFrame, cache: CVMetalTextureCache) throws {
        self.frame = frame
        let buffer = frame.buffer
        guard CVPixelBufferGetPlaneCount(buffer) == 2,
              CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange else {
            throw RenderError.unavailable("The decoder did not return video-range NV12.")
        }
        let matrix = CVBufferCopyAttachment(buffer, kCVImageBufferYCbCrMatrixKey, nil) as? String
        if matrix == kCVImageBufferYCbCrMatrix_ITU_R_601_4 as String {
            conversion = SIMD4(0.299, 0.114, 0, 0)
        } else if matrix == nil || matrix == kCVImageBufferYCbCrMatrix_ITU_R_709_2 as String {
            conversion = SIMD4(0.2126, 0.0722, 0, 0)
        } else {
            throw RenderError.unavailable("Only SDR BT.601 and BT.709 color matrices are supported.")
        }
        var wrapped: [CVMetalTexture] = []
        for index in 0..<2 {
            var result: CVMetalTexture?
            let status = CVMetalTextureCacheCreateTextureFromImage(nil, cache, buffer, nil,
                index == 0 ? .r8Unorm : .rg8Unorm,
                CVPixelBufferGetWidthOfPlane(buffer, index), CVPixelBufferGetHeightOfPlane(buffer, index), index, &result)
            guard status == kCVReturnSuccess, let result else {
                throw RenderError.unavailable("Cannot import the decoded video surface into Metal (\(status)).")
            }
            wrapped.append(result)
        }
        guard let luma = CVMetalTextureGetTexture(wrapped[0]), let chroma = CVMetalTextureGetTexture(wrapped[1]) else {
            throw RenderError.unavailable("The decoded surface has no Metal texture.")
        }
        planes = wrapped
        self.luma = luma
        self.chroma = chroma
    }
}
