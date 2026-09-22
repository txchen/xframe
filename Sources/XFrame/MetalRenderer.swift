import MetalKit
import MetalFX

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
    private let sharpenPipeline: any MTLRenderPipelineState
    private let videoPipeline: any MTLRenderPipelineState
    private let nearestPipeline: any MTLRenderPipelineState
    private let integerVideoPipeline: any MTLRenderPipelineState
    private let supportsSpatial: Bool
    private var spatial: SpatialUpscaler?
    private var failedSpatialStatus: ScalingStatus?
    private var invalidated = true
    var scalingMode: VideoScalingMode = .original { didSet { invalidated = true; failedSpatialStatus = nil } }
    var sharpening: SharpeningPreset = .off { didSet { invalidated = true } }
    var scalingReport: ((ScalingStatus) -> Void)?
    private var lastScalingStatus: ScalingStatus?
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
        descriptor.fragmentFunction = library.makeFunction(name: "nearestFragment")
        nearestPipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        descriptor.fragmentFunction = library.makeFunction(name: "integerVideoFragment")
        integerVideoPipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        descriptor.fragmentFunction = library.makeFunction(name: "sharpenFragment")
        sharpenPipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        supportsSpatial = MTLFXSpatialScalerDescriptor.supportsDevice(device)
        var cache: CVMetalTextureCache?
        guard CVMetalTextureCacheCreate(nil, nil, device, nil, &cache) == kCVReturnSuccess, let cache else {
            throw RenderError.unavailable("Unable to create the video texture cache.")
        }
        self.cache = cache
        texture = try TestPattern.makeTexture(device: device)
        self.queue = queue
        super.init()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { invalidated = true }

    func invalidate() { invalidated = true }

    func play(_ source: (any VideoSource)?, in view: MTKView) {
        self.source?.stop()
        self.source = source
        currentVideo = nil
        spatial = nil
        failedSpatialStatus = nil
        invalidated = true
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
        guard work.needsDraw(hasSource: source != nil, resized: invalidated || lastDrawableSize != view.drawableSize) else { return }
        // Acquire scarce drawables only after determining that work is necessary.
        let drawableStarted = CACurrentMediaTime()
        let renderPass = view.currentRenderPassDescriptor
        let acquiredDrawable = view.currentDrawable
        source?.performance.record(.drawableWait, seconds: CACurrentMediaTime() - drawableStarted)
        guard let pass = renderPass, let drawable = acquiredDrawable,
              let command = queue.makeCommandBuffer() else { source?.performance.note(.drawableMiss); return }
        let sourceExtent = ScalingExtent(width: currentVideo?.luma.width ?? texture.width,
                                         height: currentVideo?.luma.height ?? texture.height)
        var plan = ScalingPlan.make(mode: scalingMode, source: sourceExtent,
            canvas: ScalingExtent(width: drawable.texture.width, height: drawable.texture.height),
            fullscreen: view.window?.styleMask.contains(.fullScreen) == true, supported: supportsSpatial)
        if plan.status.effective == .metalFX {
            if failedSpatialStatus == plan.status {
                plan.status.effective = .original; plan.status.bypass = .initializationFailed
            } else {
                do {
                    if spatial?.sourceExtent != sourceExtent || spatial?.outputExtent != plan.status.output {
                        spatial = nil
                        spatial = try SpatialUpscaler(device: view.device!, source: sourceExtent, output: plan.status.output)
                    }
                } catch {
                    failedSpatialStatus = plan.status
                    plan.status.effective = .original; plan.status.bypass = .initializationFailed
                }
            }
        } else { spatial = nil }
        let activeSpatial = plan.status.effective == .metalFX ? spatial : nil
        let counter = activeSpatial?.takeCounter()
        var counterSubmitted = false
        defer {
            if !counterSubmitted, let counter { activeSpatial?.returnCounter(counter) }
        }
        if let activeSpatial {
            let conversionPass = MTLRenderPassDescriptor()
            conversionPass.colorAttachments[0].texture = activeSpatial.input
            conversionPass.colorAttachments[0].loadAction = .dontCare
            conversionPass.colorAttachments[0].storeAction = .store
            if let counter {
                let attachment = conversionPass.sampleBufferAttachments[0]!
                attachment.sampleBuffer = counter.buffer
                attachment.startOfVertexSampleIndex = MTLCounterDontSample
                attachment.endOfVertexSampleIndex = MTLCounterDontSample
                attachment.startOfFragmentSampleIndex = MTLCounterDontSample
                attachment.endOfFragmentSampleIndex = 0
            }
            guard let conversion = command.makeRenderCommandEncoder(descriptor: conversionPass) else { return }
            encodeSource(conversion, integer: false)
            conversion.endEncoding()
            activeSpatial.scaler.encode(commandBuffer: command)
        }
        // MTKView may reuse its pass descriptor across modes. Never leave a
        // retired counter attached when this submission has no counter lease.
        pass.sampleBufferAttachments[0]!.sampleBuffer = nil
        if let counter {
            let attachment = pass.sampleBufferAttachments[0]!
            attachment.sampleBuffer = counter.buffer
            attachment.startOfVertexSampleIndex = MTLCounterDontSample
            attachment.endOfVertexSampleIndex = MTLCounterDontSample
            attachment.startOfFragmentSampleIndex = 1
            attachment.endOfFragmentSampleIndex = MTLCounterDontSample
        }
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.setViewport(MTLViewport(originX: plan.x, originY: plan.y,
            width: plan.width, height: plan.height, znear: 0, zfar: 1))
        if let activeSpatial {
            encoder.setRenderPipelineState(sharpening == .off ? pipeline : sharpenPipeline)
            var amount = sharpening.amount
            encoder.setFragmentBytes(&amount, length: MemoryLayout<Float>.size, index: 0)
            encoder.setFragmentTexture(activeSpatial.output, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        } else { encodeSource(encoder, integer: plan.status.effective == .integer) }
        encoder.endEncoding()
        lastDrawableSize = view.drawableSize
        invalidated = false
        if lastScalingStatus != plan.status {
            lastScalingStatus = plan.status
            scalingReport?(plan.status)
        }
        let scalingRevision = source?.performance.setScaling(plan.status)
        let retainedVideo = currentVideo
        let permit = inFlight
        let activeSource = source
        let sample: FramePresentation?
        if work.pendingFrame, let source, let frame = currentVideo?.frame {
            sample = FramePresentation(source: source, arrivedAt: frame.arrivedAt, submittedAt: CACurrentMediaTime())
        } else { sample = nil }
        command.addCompletedHandler { command in
            withExtendedLifetime(retainedVideo) {}
            if let counter {
                if command.status == .completed, let seconds = SpatialUpscaler.scalerSeconds(counter), let scalingRevision {
                    activeSource?.performance.recordScaler(seconds: seconds, revision: scalingRevision)
                }
                activeSpatial?.returnCounter(counter)
            }
            withExtendedLifetime(activeSpatial) {}
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
        counterSubmitted = true
        committed = true
        work.submitted()
        command.commit()
    }

    private func encodeSource(_ encoder: any MTLRenderCommandEncoder, integer: Bool) {
        if let video = currentVideo {
            encoder.setRenderPipelineState(integer ? integerVideoPipeline : videoPipeline)
            encoder.setFragmentTexture(video.luma, index: 0)
            encoder.setFragmentTexture(video.chroma, index: 1)
            var conversion = video.conversion
            encoder.setFragmentBytes(&conversion, length: MemoryLayout<SIMD4<Float>>.size, index: 0)
        } else {
            encoder.setRenderPipelineState(integer ? nearestPipeline : pipeline)
            encoder.setFragmentTexture(texture, index: 0)
        }
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
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
