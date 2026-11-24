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
    private let fsr1EasuPipeline: any MTLRenderPipelineState
    private let fsr1RcasPipeline: any MTLRenderPipelineState
    private let videoPipeline: any MTLRenderPipelineState
    private let nearestPipeline: any MTLRenderPipelineState
    private let integerVideoPipeline: any MTLRenderPipelineState
    private let supportsSpatial: Bool
    private var spatial: SpatialUpscaler?
    private var fsrIntermediate: (any MTLTexture)?
    private var failedSpatialStatus: ScalingStatus?
    private var invalidated = true
    var scalingMode: VideoScalingMode = .original { didSet { invalidated = true; failedSpatialStatus = nil } }
    var sharpening: SharpeningPreset = .off { didSet { invalidated = true } }
    var scalingReport: ((ScalingStatus) -> Void)?
    private var lastScalingStatus: ScalingStatus?
    private let cache: CVMetalTextureCache
    private let interpolator: LiveFrameInterpolator
    private var currentVideo: VideoTextures?
    private var currentInterpolatedTexture: (box: InterpolatedTextureBox, sourceFrame: VideoFrame)?
    private var source: (any VideoSource)?
    var frameGenerationMode: FrameGenerationMode = FrameGenerationMode.load() {
        didSet {
            interpolator.setMode(frameGenerationMode)
            currentInterpolatedTexture = nil
            invalidated = true
        }
    }
    var frameGenerationStatusNote: String? { interpolator.statusNote }
    static let vrrKey = "XFrame.Experimental.VRRAdaptiveSync"
    static func vrrPreference(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: vrrKey)
    }
    var vrrEnabled = MetalRenderer.vrrPreference() {
        didSet {
            (playView?.layer as? CAMetalLayer)?.displaySyncEnabled = !vrrEnabled
        }
    }
    private let inFlight = DispatchSemaphore(value: 3)
    private let presentationQueue = PresentationQueue()
    private var lastDrawableSize = CGSize.zero
    private let hudSampler = HUDSampler()
    var hudPreset: PerformanceHUDPreset = .compact { didSet { restartHUD() } }
    private var work = RenderWorkState()
    var report: ((HUDDocument) -> Void)?
    var firstFrameReady: (() -> Void)?
    private var presentationGeneration = UUID()
    private var awaitingFirstFrame = false
    // Original render worker, on by default since 0.1.5 (View > Low-Latency Original Rendering). MTK remains the
    // fallback owner: turning it off hands drawing back through the same path as leaving Original scaling.
    static let renderWorkerKey = "XFrame.Experimental.OriginalRenderWorker" // Name kept so earlier choices persist.
    static func renderWorkerPreference(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: renderWorkerKey) as? Bool ?? true
    }
    var renderWorkerEnabled = MetalRenderer.renderWorkerPreference() {
        didSet {
            guard renderWorkerEnabled, workerSlot.worker == nil, let live = source as? LiveVideo, let view = playView else { return }
            startRenderWorker(live: live, view: view)
        }
    }
    private weak var playView: MTKView?
    private let workerSlot = RenderWorkerSlot()
    private var workerLink: CADisplayLink?
    private var workerOwnsDrawing = false, workerHandingBack = false
    private weak var workerView: MTKView?

    private func restartHUD() {
        hudSampler.stop()
        guard let source, hudPreset != .hidden else { return }
        let preset = hudPreset
        hudSampler.start(collect: { HUDDocument(stats: source.snapshot(), preset: preset) },
                         deliver: { [weak self] in self?.report?($0) })
    }

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
        descriptor.fragmentFunction = library.makeFunction(name: "fsr1EasuVideoFragment")
        fsr1EasuPipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        descriptor.fragmentFunction = library.makeFunction(name: "fsr1RcasFragment")
        fsr1RcasPipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        supportsSpatial = MTLFXSpatialScalerDescriptor.supportsDevice(device)
        var cache: CVMetalTextureCache?
        guard CVMetalTextureCacheCreate(nil, nil, device, nil, &cache) == kCVReturnSuccess, let cache else {
            throw RenderError.unavailable("Unable to create the video texture cache.")
        }
        self.cache = cache
        interpolator = LiveFrameInterpolator(device: device, resourceBundle: resourceBundle)
        interpolator.setMode(frameGenerationMode)
        texture = try TestPattern.makeTexture(device: device)
        self.queue = queue
        super.init()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { invalidated = true }

    func invalidate() { invalidated = true }

    deinit { workerSlot.stop() }

    func play(_ source: (any VideoSource)?, in view: MTKView) {
        stopRenderWorker()
        self.source = source
        playView = view
        (view.layer as? CAMetalLayer)?.displaySyncEnabled = !vrrEnabled
        if renderWorkerEnabled, let live = source as? LiveVideo { startRenderWorker(live: live, view: view) }
        presentationGeneration = UUID()
        awaitingFirstFrame = source != nil
        restartHUD()
        interpolator.reset()
        currentVideo = nil
        currentInterpolatedTexture = nil
        CVMetalTextureCacheFlush(cache, 0)
        spatial = nil
        fsrIntermediate = nil
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
        // While the render worker owns Original drawing, MTK callbacks return before reserving or dequeuing.
        if workerOwnsDrawing { return }
        let now = CACurrentMediaTime()
        source?.performance.note(.draw, at: now)
        if let state = source?.playbackState, state == "Ended" || state.hasPrefix("Failed:") {
            view.isPaused = true
            view.enableSetNeedsDisplay = true
            return
        }
        guard inFlight.wait(timeout: .now()) == .success else { source?.performance.note(.busy); return }
        var committed = false
        defer { if !committed { inFlight.signal() } }
        guard view.drawableSize.width > 0, view.drawableSize.height > 0 else { return }

        guard let presentation = presentationQueue.reserve(
            enforcingLimit: source is LiveVideo && scalingMode == .original
        ) else { return }

        let next = source?.nextFrame(at: now)
        let displayOutput: FrameInterpolationScheduler.Output?
        if frameGenerationMode != .off {
            if let next {
                displayOutput = interpolator.ingest(frame: next, at: now, isLive: source is LiveVideo)
                    ?? interpolator.pollDisplay(at: now)
            } else {
                displayOutput = interpolator.pollDisplay(at: now)
            }
        } else {
            displayOutput = next.map { .real($0) }
        }
        if let displayOutput {
            switch displayOutput {
            case .real(let frame):
                do {
                    let textures = try VideoTextures(frame: frame, cache: cache)
                    if work.receivedFrame() {
                        source?.didSkipFrame()
                        if let live = source as? LiveVideo, let previous = currentVideo?.frame, let rtp = previous.sourceRTP {
                            live.frameTrace.note(.rendererReplaced, rtp: rtp, frameID: previous.id)
                        }
                    }
                    currentVideo = textures
                    currentInterpolatedTexture = nil
                } catch {
                    source?.fail(error.localizedDescription)
                    view.isPaused = true
                    return
                }
            case .interpolated(let box, _, _, let sourceFrame):
                if work.receivedFrame() { source?.didSkipFrame() }
                currentInterpolatedTexture = (box, sourceFrame)
            }
        }
        if source != nil && currentVideo == nil && currentInterpolatedTexture == nil { return }
        guard work.needsDraw(hasSource: source != nil, resized: invalidated || lastDrawableSize != view.drawableSize) else { return }
        // Acquire scarce drawables only after determining that work is necessary.
        let drawableStarted = CACurrentMediaTime()
        let renderPass = view.currentRenderPassDescriptor
        let acquiredDrawable = view.currentDrawable
        source?.performance.record(.drawableWait, seconds: CACurrentMediaTime() - drawableStarted)
        guard let pass = renderPass, let drawable = acquiredDrawable,
              let command = queue.makeCommandBuffer() else { source?.performance.note(.drawableMiss); return }
        let sourceExtent = ScalingExtent(
            width: currentInterpolatedTexture?.box.texture.width ?? currentVideo?.luma.width ?? texture.width,
            height: currentInterpolatedTexture?.box.texture.height ?? currentVideo?.luma.height ?? texture.height
        )
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
        let activeFSR: (any MTLTexture)?
        if plan.status.effective == .fsr1, currentVideo != nil, currentInterpolatedTexture == nil {
            if fsrIntermediate?.width != plan.status.output.width || fsrIntermediate?.height != plan.status.output.height {
                let d = MTLTextureDescriptor.texture2DDescriptor(
                    pixelFormat: view.colorPixelFormat,
                    width: plan.status.output.width, height: plan.status.output.height, mipmapped: false
                )
                d.storageMode = .private
                d.usage = [.renderTarget, .shaderRead]
                fsrIntermediate = view.device?.makeTexture(descriptor: d)
            }
            activeFSR = fsrIntermediate
        } else {
            fsrIntermediate = nil
            activeFSR = nil
        }
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
        if let activeFSR, let video = currentVideo {
            let easuPass = MTLRenderPassDescriptor()
            easuPass.colorAttachments[0].texture = activeFSR
            easuPass.colorAttachments[0].loadAction = .dontCare
            easuPass.colorAttachments[0].storeAction = .store
            guard let easu = command.makeRenderCommandEncoder(descriptor: easuPass) else { return }
            easu.setRenderPipelineState(fsr1EasuPipeline)
            easu.setFragmentTexture(video.luma, index: 0)
            easu.setFragmentTexture(video.chroma, index: 1)
            var conversion = video.conversion
            easu.setFragmentBytes(&conversion, length: MemoryLayout<SIMD4<Float>>.size, index: 0)
            easu.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            easu.endEncoding()
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
        } else if let activeFSR {
            encoder.setRenderPipelineState(fsr1RcasPipeline)
            var sharpness = sharpening == .off ? Float(0.35) : min(1.0, 0.35 + sharpening.amount * 0.65)
            encoder.setFragmentBytes(&sharpness, length: MemoryLayout<Float>.size, index: 0)
            encoder.setFragmentTexture(activeFSR, index: 0)
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
        let retainedInterpolated = currentInterpolatedTexture?.box
        let permit = inFlight
        let activeSource = source
        let isInterpolated = currentInterpolatedTexture != nil
        let sample: FramePresentation?
        if work.pendingFrame, !isInterpolated, let source, let frame = currentVideo?.frame {
            sample = FramePresentation(source: source, arrivedAt: frame.arrivedAt, submittedAt: CACurrentMediaTime(), sourceRTP: frame.sourceRTP, frameID: frame.id)
        } else { sample = nil }
        let generatedPending = work.pendingFrame && isInterpolated
        let generation = presentationGeneration
        command.addCompletedHandler { [weak self] command in
            withExtendedLifetime(retainedVideo) {}
            withExtendedLifetime(retainedInterpolated) {}
            if let counter {
                if command.status == .completed, let seconds = SpatialUpscaler.scalerSeconds(counter), let scalingRevision {
                    activeSource?.performance.recordScaler(seconds: seconds, revision: scalingRevision)
                }
                activeSpatial?.returnCounter(counter)
            }
            withExtendedLifetime(activeSpatial) {}
            if command.status == .error {
                presentation.finish()
                activeSource?.fail("Metal rendering failed: \(command.error?.localizedDescription ?? "Unknown GPU error")")
            }
            if command.status == .completed, command.gpuStartTime > 0, command.gpuEndTime >= command.gpuStartTime {
                sample?.gpuCompleted(start: command.gpuStartTime, end: command.gpuEndTime)
            }
            if command.status == .completed, sample != nil {
                Task { @MainActor [weak self] in
                    guard let self, self.presentationGeneration == generation, self.awaitingFirstFrame else { return }
                    self.awaitingFirstFrame = false
                    self.invalidated = true
                    self.firstFrameReady?()
                }
            }
            permit.signal()
        }
        if let sample {
            drawable.addPresentedHandler { presented in sample.presented(at: presented.presentedTime) }
        } else if generatedPending, let activeSource {
            drawable.addPresentedHandler { presented in
                if presented.presentedTime > 0 { activeSource.didPresentGeneratedFrame() }
            }
        }
        drawable.addPresentedHandler { _ in presentation.finish() }
        command.present(drawable)
        counterSubmitted = true
        committed = true
        work.submitted()
        command.commit()
    }

    // MARK: Render worker ownership (main thread)
    private func startRenderWorker(live: LiveVideo, view: MTKView) {
        guard let layer = view.layer as? CAMetalLayer, let device = view.device,
              let worker = try? OriginalPresenter(queue: queue, pipeline: videoPipeline, inFlight: inFlight,
                                                   presentationQueue: presentationQueue, layer: layer, device: device,
                                                   integerPipeline: integerVideoPipeline, patternPipeline: pipeline,
                                                   sharpenPipeline: sharpenPipeline, fsr1EasuPipeline: fsr1EasuPipeline,
                                                   fsr1RcasPipeline: fsr1RcasPipeline, supportsSpatial: supportsSpatial) else { return }
        worker.configure(source: live)
        worker.configureRender(scalingMode: scalingMode, sharpening: sharpening,
                               fullscreen: view.window?.styleMask.contains(.fullScreen) == true)
        worker.start(); workerSlot.set(worker)
        workerView = view
        let link = view.displayLink(target: RenderWorkerTick(self), selector: #selector(RenderWorkerTick.tick(_:)))
        link.add(to: .main, forMode: .common); workerLink = link
    }
    private func stopRenderWorker() {
        workerLink?.invalidate(); workerLink = nil
        workerSlot.stop()
        workerOwnsDrawing = false; workerHandingBack = false; workerView = nil
    }
    fileprivate func renderWorkerTick(_ link: CADisplayLink) {
        guard let worker = workerSlot.worker, let view = workerView else { return }
        worker.lattice.update(timestamp: link.timestamp, target: link.targetTimestamp, now: CACurrentMediaTime())
        // The worker cannot call UI closures; forward its scaling status (e.g. after a resize) from the main thread.
        if workerOwnsDrawing, let status = worker.lastScalingStatus, status != lastScalingStatus {
            lastScalingStatus = status
            scalingReport?(status)
        }
        worker.configureRender(scalingMode: scalingMode, sharpening: sharpening,
                               fullscreen: view.window?.styleMask.contains(.fullScreen) == true)
        let state = source?.playbackState ?? "Ended"
        let wanted = renderWorkerEnabled && frameGenerationMode == .off && source is LiveVideo && !awaitingFirstFrame && view.window != nil
            && view.drawableSize.width > 0 && view.drawableSize.height > 0 && state != "Ended" && !state.hasPrefix("Failed:")
        if wanted, !workerOwnsDrawing, !workerHandingBack {
            workerOwnsDrawing = true; worker.setActive(true)
        } else if !wanted, workerOwnsDrawing {
            if !workerHandingBack { workerHandingBack = true; worker.setActive(false) }
            if worker.isIdle {
                workerOwnsDrawing = false; workerHandingBack = false
                currentVideo = nil; work = RenderWorkState(); invalidated = true
                if !renderWorkerEnabled { stopRenderWorker() }
            }
        } else if !renderWorkerEnabled, !workerOwnsDrawing, worker.isIdle {
            stopRenderWorker()
        }
    }

    private func encodeSource(_ encoder: any MTLRenderCommandEncoder, integer: Bool) {
        if let interp = currentInterpolatedTexture {
            encoder.setRenderPipelineState(integer ? nearestPipeline : pipeline)
            encoder.setFragmentTexture(interp.box.texture, index: 0)
        } else if let video = currentVideo {
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

// Holds the worker so the nonisolated deinit can stop its thread.
final class RenderWorkerSlot: @unchecked Sendable {
    private let lock = NSLock(); private var current: OriginalPresenter?
    var worker: OriginalPresenter? { lock.withLock { current } }
    func set(_ w: OriginalPresenter) { lock.withLock { current = w } }
    func stop() { let w = lock.withLock { () -> OriginalPresenter? in let w = current; current = nil; return w }; w?.stop() }
}

// Display-link target that does not retain the renderer; invalidates itself once the renderer is gone.
@MainActor final class RenderWorkerTick: NSObject {
    private weak var renderer: MetalRenderer?
    init(_ renderer: MetalRenderer) { self.renderer = renderer }
    @objc func tick(_ link: CADisplayLink) {
        guard let renderer else { link.invalidate(); return }
        renderer.renderWorkerTick(link)
    }
}
