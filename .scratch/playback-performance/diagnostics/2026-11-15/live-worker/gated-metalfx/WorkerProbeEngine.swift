import MetalKit
import MetalFX

// Experimental engine: initialized on main, then exclusively owned by its rendering thread.
final class WorkerProbeEngine: @unchecked Sendable {
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
    let scalingMode: VideoScalingMode
    let sharpening: SharpeningPreset
    let fullscreen: Bool
    let device: any MTLDevice
    let source: LiveVideo
    let cache: CVMetalTextureCache
    var currentVideo: VideoTextures?
    let inFlight = DispatchSemaphore(value: 3)
    @MainActor init(view: MTKView, source: LiveVideo, mode: VideoScalingMode, sharpening: SharpeningPreset) throws {
        self.source=source;self.scalingMode=mode;self.sharpening=sharpening
        self.fullscreen=view.window?.styleMask.contains(.fullScreen) == true
        self.device=view.device!
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

    }

    func render(_ frame: VideoFrame, drawable: any CAMetalDrawable, presented: @escaping @Sendable () -> Void) {
        guard inFlight.wait(timeout: .now()) == .success else {source.didSkipFrame();presented();return}
        var committed=false
        defer {if !committed {inFlight.signal();presented()}}
        do {currentVideo=try VideoTextures(frame:frame,cache:cache)} catch {source.fail(error.localizedDescription);return}
        let pass=MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture=drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor=MTLClearColor(red:0,green:0,blue:0,alpha:1)
        guard let command=queue.makeCommandBuffer() else {source.fail("Probe command allocation failed");return}
        let sourceExtent = ScalingExtent(width: currentVideo?.luma.width ?? texture.width,
                                         height: currentVideo?.luma.height ?? texture.height)
        var plan = ScalingPlan.make(mode: scalingMode, source: sourceExtent,
            canvas: ScalingExtent(width: drawable.texture.width, height: drawable.texture.height),
            fullscreen: fullscreen, supported: supportsSpatial)
        if plan.status.effective == .metalFX {
            if failedSpatialStatus == plan.status {
                plan.status.effective = .original; plan.status.bypass = .initializationFailed
            } else {
                do {
                    if spatial?.sourceExtent != sourceExtent || spatial?.outputExtent != plan.status.output {
                        spatial = nil
                        spatial = try SpatialUpscaler(device: device, source: sourceExtent, output: plan.status.output)
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
        let scalingRevision = source.performance.setScaling(plan.status)
        let retainedVideo = currentVideo
        let permit = inFlight
        let activeSource = source
        let sample = FramePresentation(source: source, arrivedAt: frame.arrivedAt, submittedAt: CACurrentMediaTime(), sourceRTP: frame.sourceRTP, frameID: frame.id)
        command.addCompletedHandler { command in
            withExtendedLifetime(retainedVideo) {}
            if let counter {
                if command.status == .completed, let seconds = SpatialUpscaler.scalerSeconds(counter){
                    activeSource.performance.recordScaler(seconds: seconds, revision: scalingRevision)
                }
                activeSpatial?.returnCounter(counter)
            }
            withExtendedLifetime(activeSpatial) {}
            if command.status == .error {
                activeSource.fail("Metal rendering failed: \(command.error?.localizedDescription ?? "Unknown GPU error")")
            }
            if command.status == .completed, command.gpuStartTime > 0, command.gpuEndTime >= command.gpuStartTime {
                sample.gpuCompleted(start: command.gpuStartTime, end: command.gpuEndTime)
            }
            permit.signal()
        }
        drawable.addPresentedHandler { drawable in sample.presented(at: drawable.presentedTime);presented() }
        command.present(drawable)
        counterSubmitted = true
        committed = true
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

