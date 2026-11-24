import Foundation
import QuartzCore
@preconcurrency import Metal
import MetalFX
import CoreVideo
import Darwin

/// Display grid estimate fed by display-link samples (main thread), read by the render thread.
final class VsyncLattice: @unchecked Sendable {
    private let lock = NSLock()
    private var last = 0.0, period = 1.0 / 60, updated = 0.0
    func update(timestamp: Double, target: Double, now: Double) {
        lock.withLock { let p = target - timestamp; if p > 0.004 && p < 0.05 { period = p }; last = timestamp; updated = now }
    }
    func next(after t: Double) -> (v: Double, age: Double, period: Double) {
        lock.withLock {
            guard last > 0 else { return (0, .infinity, period) }
            return (last + (floor((t - last) / period) + 1) * period, t - updated, period)
        }
    }
}

enum VsyncTarget {
    /// Re-derives the previous submit's landing refresh from the current lattice so one off-grid sample cannot
    /// carry a phase error forward and the same refresh is never targeted twice.
    static func next(lattice: VsyncLattice, now: Double, lead: Double, lastSubmit: Double) -> (v: Double, age: Double) {
        let (v0, age, period) = lattice.next(after: now + lead + 0.0003)
        guard v0 > 0, lastSubmit > 0 else { return (v0, age) }
        let landing = lattice.next(after: lastSubmit + 0.0005).v
        if v0 > landing + period / 2 { return (v0, age) }
        return (lattice.next(after: landing + period / 2).v, age)
    }
}

final class OriginalPresenter: @unchecked Sendable {
    static let staleLimit = 0.1
    let lattice = VsyncLattice()
    private let condition = NSCondition()
    private var active = false, stopped = false, idle = true, drawableSize = CGSize.zero
    private var scalingMode: VideoScalingMode = .original
    private var sharpening: SharpeningPreset = .off
    private var fullscreen = false
    private var metalFXGpuEMA = 0.0040
    private var scalingStatus: ScalingStatus?
    private var policyApplied: Bool?
    private var source: LiveVideo?
    private let device: any MTLDevice
    private let queue: any MTLCommandQueue
    private let pipeline: any MTLRenderPipelineState
    private let integerPipeline: (any MTLRenderPipelineState)?
    private let patternPipeline: (any MTLRenderPipelineState)?
    private let sharpenPipeline: (any MTLRenderPipelineState)?
    private let fsr1EasuPipeline: (any MTLRenderPipelineState)?
    private let fsr1RcasPipeline: (any MTLRenderPipelineState)?
    private let supportsSpatial: Bool
    private var spatial: SpatialUpscaler?
    private var fsrIntermediate: (any MTLTexture)?
    private var failedSpatialStatus: ScalingStatus?
    private let inFlight: DispatchSemaphore
    private let presentationQueue: PresentationQueue
    private let layer: CAMetalLayer
    private let cache: CVMetalTextureCache
    private let lead: Double
    private let finished = DispatchSemaphore(value: 0)
    private var started = false

    init(queue: any MTLCommandQueue, pipeline: any MTLRenderPipelineState, inFlight: DispatchSemaphore,
         presentationQueue: PresentationQueue, layer: CAMetalLayer, device: any MTLDevice, lead: Double = 0.003,
         integerPipeline: (any MTLRenderPipelineState)? = nil,
         patternPipeline: (any MTLRenderPipelineState)? = nil,
         sharpenPipeline: (any MTLRenderPipelineState)? = nil,
         fsr1EasuPipeline: (any MTLRenderPipelineState)? = nil,
         fsr1RcasPipeline: (any MTLRenderPipelineState)? = nil,
         supportsSpatial: Bool = false) throws {
        self.device = device
        self.queue = queue; self.pipeline = pipeline; self.inFlight = inFlight; self.presentationQueue = presentationQueue
        self.layer = layer; self.lead = lead
        self.integerPipeline = integerPipeline
        self.patternPipeline = patternPipeline
        self.sharpenPipeline = sharpenPipeline
        self.fsr1EasuPipeline = fsr1EasuPipeline
        self.fsr1RcasPipeline = fsr1RcasPipeline
        self.supportsSpatial = supportsSpatial && patternPipeline != nil && sharpenPipeline != nil
        var c: CVMetalTextureCache?
        guard CVMetalTextureCacheCreate(nil, nil, device, nil, &c) == kCVReturnSuccess, let c else {
            throw RenderError.unavailable("Unable to create the render worker texture cache.")
        }
        cache = c
    }

    private func withState<T>(_ body: () -> T) -> T {
        condition.lock(); defer { condition.unlock() }
        return body()
    }

    func configure(source: LiveVideo?) { withState { self.source = source } }
    func configureRender(scalingMode: VideoScalingMode, sharpening: SharpeningPreset, fullscreen: Bool) {
        withState {
            if self.scalingMode != scalingMode { failedSpatialStatus = nil }
            self.scalingMode = scalingMode
            self.sharpening = sharpening
            self.fullscreen = fullscreen
        }
    }
    func setActive(_ on: Bool) {
        withState {
            active = on && !stopped
            condition.broadcast()
        }
    }
    var isIdle: Bool { withState { idle } }
    var lastDrawableSize: CGSize { withState { drawableSize } }
    var lastScalingStatus: ScalingStatus? { withState { scalingStatus } }
    var timeConstraintApplied: Bool? { withState { policyApplied } }

    static func effectiveLead(baseLead: Double, scalingMode: VideoScalingMode, metalFXGpuEMA: Double) -> Double {
        guard scalingMode == .metalFX || scalingMode == .fsr1 else { return baseLead }
        return min(0.011, max(0.004, metalFXGpuEMA + 0.0025))
    }

    private func currentLead() -> Double {
        withState { Self.effectiveLead(baseLead: lead, scalingMode: scalingMode, metalFXGpuEMA: metalFXGpuEMA) }
    }

    func start() {
        let shouldStart = withState { () -> Bool in
            guard !started else { return false }
            started = true
            return true
        }
        guard shouldStart else { return }
        let t = Thread { [self] in
            var appliedPeriodMs = 16.667
            let applied = applyTimeConstraintPolicy(periodMs: appliedPeriodMs, computationMs: 2.0, constraintMs: 4.0)
            withState { policyApplied = applied }
            var ticks = mach_timebase_info_data_t(); mach_timebase_info(&ticks)
            let perSecond = 1e9 * Double(ticks.denom) / Double(ticks.numer)
            var lastSubmit = 0.0
            while true {
                let quit = withState { () -> Bool in
                    while !active && !stopped {
                        idle = true
                        condition.wait()
                    }
                    idle = !active
                    return stopped
                }
                if quit {
                    spatial = nil
                    CVMetalTextureCacheFlush(cache, 0)
                    finished.signal()
                    return
                }
                let now = CACurrentMediaTime()
                let (_, _, rawPeriod) = lattice.next(after: now)
                let targetPeriodMs = min(25.0, max(4.0, rawPeriod * 1000.0))
                if abs(targetPeriodMs - appliedPeriodMs) > 1.0 {
                    appliedPeriodMs = targetPeriodMs
                    let comp = min(2.0, targetPeriodMs * 0.25)
                    let constraint = min(4.0, targetPeriodMs * 0.45)
                    _ = applyTimeConstraintPolicy(periodMs: appliedPeriodMs, computationMs: comp, constraintMs: constraint)
                }
                let activeLead = currentLead()
                let (v, age) = VsyncTarget.next(lattice: lattice, now: now, lead: activeLead, lastSubmit: lastSubmit)
                if v == 0 || age > Self.staleLimit {
                    withState {
                        if active && !stopped {
                            _ = condition.wait(until: Date().addingTimeInterval(0.005))
                        }
                    }
                    if !withState({ active }) {
                        lastSubmit = 0
                        spatial = nil
                        CVMetalTextureCacheFlush(cache, 0)
                    }
                    continue
                }
                let planned = v - activeLead
                if planned > CACurrentMediaTime() { mach_wait_until(UInt64(planned * perSecond)) }
                guard withState({ active && !stopped }) else {
                    lastSubmit = 0
                    spatial = nil
                    CVMetalTextureCacheFlush(cache, 0)
                    continue
                }
                if autoreleasepool(invoking: { renderOne(at: CACurrentMediaTime()) }) { lastSubmit = CACurrentMediaTime() }
            }
        }
        t.name = "XFrame render worker"; t.qualityOfService = .userInteractive; t.start()
    }

    @discardableResult
    func stop(timeout: Double = 1.0) -> Bool {
        let wasStarted = withState { () -> Bool in
            let s = started && !stopped
            stopped = true; active = false; source = nil
            condition.broadcast()
            return s
        }
        guard wasStarted else { return true }
        return finished.wait(timeout: .now() + timeout) == .success
    }

    private func renderOne(at now: Double) -> Bool {
        guard let live = withState({ source }) else { return false }
        live.performance.note(.draw, at: now)
        guard inFlight.wait(timeout: .now()) == .success else { live.performance.note(.busy); return false }
        guard let presentation = presentationQueue.reserve(enforcingLimit: true) else { inFlight.signal(); return false }
        guard let frame = live.nextFrame(at: now) else { presentation.finish(); inFlight.signal(); return false }
        let video: VideoTextures
        do { video = try VideoTextures(frame: frame, cache: cache) } catch {
            presentation.finish(); inFlight.signal(); live.fail(error.localizedDescription); return false
        }
        let drawableStarted = CACurrentMediaTime()
        guard let drawable = layer.nextDrawable(), let command = queue.makeCommandBuffer() else {
            live.performance.note(.drawableMiss)
            presentation.finish(); inFlight.signal(); return false
        }
        live.performance.record(.drawableWait, seconds: CACurrentMediaTime() - drawableStarted)
        let config: (mode: VideoScalingMode, sharpening: SharpeningPreset, fullscreen: Bool, stillActive: Bool) = withState {
            (scalingMode, sharpening, fullscreen, active && !stopped)
        }
        guard config.stillActive else { presentation.finish(); inFlight.signal(); return false }

        let sourceExtent = ScalingExtent(width: video.luma.width, height: video.luma.height)
        let canvasExtent = ScalingExtent(width: drawable.texture.width, height: drawable.texture.height)
        var plan = ScalingPlan.make(mode: config.mode, source: sourceExtent, canvas: canvasExtent,
                                    fullscreen: config.fullscreen, supported: supportsSpatial)
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
        } else {
            spatial = nil
        }

        let activeFSR: (any MTLTexture)?
        if plan.status.effective == .fsr1, fsr1EasuPipeline != nil, fsr1RcasPipeline != nil {
            if fsrIntermediate?.width != plan.status.output.width || fsrIntermediate?.height != plan.status.output.height {
                let d = MTLTextureDescriptor.texture2DDescriptor(
                    pixelFormat: drawable.texture.pixelFormat,
                    width: plan.status.output.width, height: plan.status.output.height, mipmapped: false
                )
                d.storageMode = .private
                d.usage = [.renderTarget, .shaderRead]
                fsrIntermediate = device.makeTexture(descriptor: d)
            }
            activeFSR = fsrIntermediate
        } else {
            fsrIntermediate = nil
            activeFSR = nil
        }

        let activeSpatial = plan.status.effective == .metalFX ? spatial : nil
        let counter = activeSpatial?.takeCounter()
        var counterSubmitted = false
        defer { if !counterSubmitted, let counter { activeSpatial?.returnCounter(counter) } }

        if let activeSpatial {
            let conversionPass = MTLRenderPassDescriptor()
            conversionPass.colorAttachments[0].texture = activeSpatial.input
            conversionPass.colorAttachments[0].loadAction = .dontCare
            conversionPass.colorAttachments[0].storeAction = .store
            if let counter, let attachment = conversionPass.sampleBufferAttachments[0] {
                attachment.sampleBuffer = counter.buffer
                attachment.startOfVertexSampleIndex = MTLCounterDontSample
                attachment.endOfVertexSampleIndex = MTLCounterDontSample
                attachment.startOfFragmentSampleIndex = MTLCounterDontSample
                attachment.endOfFragmentSampleIndex = 0
            }
            guard let conversion = command.makeRenderCommandEncoder(descriptor: conversionPass) else {
                presentation.finish(); inFlight.signal(); return false
            }
            encodeVideo(conversion, video: video, integer: false)
            conversion.endEncoding()
            activeSpatial.scaler.encode(commandBuffer: command)
        }

        if let activeFSR, let fsr1EasuPipeline {
            let easuPass = MTLRenderPassDescriptor()
            easuPass.colorAttachments[0].texture = activeFSR
            easuPass.colorAttachments[0].loadAction = .dontCare
            easuPass.colorAttachments[0].storeAction = .store
            guard let easu = command.makeRenderCommandEncoder(descriptor: easuPass) else {
                presentation.finish(); inFlight.signal(); return false
            }
            easu.setRenderPipelineState(fsr1EasuPipeline)
            easu.setFragmentTexture(video.luma, index: 0)
            easu.setFragmentTexture(video.chroma, index: 1)
            var conversion = video.conversion
            easu.setFragmentBytes(&conversion, length: MemoryLayout<SIMD4<Float>>.size, index: 0)
            easu.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            easu.endEncoding()
        }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        pass.colorAttachments[0].storeAction = .store
        if let counter, let attachment = pass.sampleBufferAttachments[0] {
            attachment.sampleBuffer = counter.buffer
            attachment.startOfVertexSampleIndex = MTLCounterDontSample
            attachment.endOfVertexSampleIndex = MTLCounterDontSample
            attachment.startOfFragmentSampleIndex = 1
            attachment.endOfFragmentSampleIndex = MTLCounterDontSample
        }
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else {
            presentation.finish(); inFlight.signal(); return false
        }
        let scalingRevision = live.performance.setScaling(plan.status)
        withState {
            drawableSize = CGSize(width: drawable.texture.width, height: drawable.texture.height)
            scalingStatus = plan.status
        }
        encoder.setViewport(MTLViewport(originX: plan.x, originY: plan.y, width: plan.width, height: plan.height, znear: 0, zfar: 1))
        if let activeSpatial, let patternPipeline, let sharpenPipeline {
            encoder.setRenderPipelineState(config.sharpening == .off ? patternPipeline : sharpenPipeline)
            var amount = config.sharpening.amount
            encoder.setFragmentBytes(&amount, length: MemoryLayout<Float>.size, index: 0)
            encoder.setFragmentTexture(activeSpatial.output, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        } else if let activeFSR, let fsr1RcasPipeline {
            encoder.setRenderPipelineState(fsr1RcasPipeline)
            var sharpness = config.sharpening == .off ? Float(0.35) : min(1.0, 0.35 + config.sharpening.amount * 0.65)
            encoder.setFragmentBytes(&sharpness, length: MemoryLayout<Float>.size, index: 0)
            encoder.setFragmentTexture(activeFSR, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        } else {
            encodeVideo(encoder, video: video, integer: plan.status.effective == .integer)
        }
        encoder.endEncoding()

        let sample = FramePresentation(source: live, arrivedAt: frame.arrivedAt, submittedAt: CACurrentMediaTime(),
                                       sourceRTP: frame.sourceRTP, frameID: frame.id)
        let permit = inFlight
        let isUpscaled = activeSpatial != nil || activeFSR != nil
        command.addCompletedHandler { [weak self] command in
            withExtendedLifetime(video) {}
            withExtendedLifetime(activeFSR) {}
            if let counter {
                if command.status == .completed, let seconds = SpatialUpscaler.scalerSeconds(counter) {
                    live.performance.recordScaler(seconds: seconds, revision: scalingRevision)
                }
                activeSpatial?.returnCounter(counter)
            }
            withExtendedLifetime(activeSpatial) {}
            if command.status == .error {
                presentation.finish(); live.fail("Metal rendering failed: \(command.error?.localizedDescription ?? "Unknown GPU error")")
            }
            if command.status == .completed, command.gpuStartTime > 0, command.gpuEndTime >= command.gpuStartTime {
                let gpuDuration = command.gpuEndTime - command.gpuStartTime
                sample.gpuCompleted(start: command.gpuStartTime, end: command.gpuEndTime)
                if isUpscaled, gpuDuration < 0.025 {
                    self?.withState {
                        if let self { self.metalFXGpuEMA = self.metalFXGpuEMA * 0.8 + gpuDuration * 0.2 }
                    }
                }
            }
            permit.signal()
        }
        drawable.addPresentedHandler { presented in sample.presented(at: presented.presentedTime) }
        drawable.addPresentedHandler { _ in presentation.finish() }
        command.present(drawable)
        counterSubmitted = true
        command.commit()
        return true
    }

    private func encodeVideo(_ encoder: any MTLRenderCommandEncoder, video: VideoTextures, integer: Bool) {
        encoder.setRenderPipelineState(integer ? (integerPipeline ?? pipeline) : pipeline)
        encoder.setFragmentTexture(video.luma, index: 0)
        encoder.setFragmentTexture(video.chroma, index: 1)
        var conversion = video.conversion
        encoder.setFragmentBytes(&conversion, length: MemoryLayout<SIMD4<Float>>.size, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }
}

/// Applies THREAD_TIME_CONSTRAINT_POLICY to the calling thread only.
@discardableResult
func applyTimeConstraintPolicy(periodMs: Double, computationMs: Double, constraintMs: Double) -> Bool {
    var tb = mach_timebase_info_data_t(); mach_timebase_info(&tb)
    let perSecond = 1e9 * Double(tb.denom) / Double(tb.numer)
    let count = mach_msg_type_number_t(MemoryLayout<thread_time_constraint_policy_data_t>.size / MemoryLayout<integer_t>.size)
    let t = { (ms: Double) in UInt32(ms / 1000 * perSecond) }
    var policy = thread_time_constraint_policy_data_t(period: t(periodMs), computation: t(computationMs), constraint: t(constraintMs), preemptible: 1)
    let result = withUnsafeMutablePointer(to: &policy) { p in p.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        thread_policy_set(pthread_mach_thread_np(pthread_self()), thread_policy_flavor_t(THREAD_TIME_CONSTRAINT_POLICY), $0, count) } }
    return result == KERN_SUCCESS
}
