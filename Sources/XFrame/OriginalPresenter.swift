import Foundation
import QuartzCore
import Metal
import CoreVideo
import Darwin

// Original-mode render worker (default on since 0.1.5; disable with UserDefaults "XFrame.Experimental.OriginalRenderWorker" = NO).
// A dedicated thread with a time-constraint policy wakes `lead` before the predicted VSync, takes the newest decoded
// frame from LiveVideo (queue rules unchanged) and submits it. The MTK path stays the default and the fallback.

/// Display grid estimate fed by display-link samples (main thread), read by the render thread.
/// This is the scheduler's estimate of the display-link grid, not hardware VSync.
final class VsyncLattice: @unchecked Sendable {
    private let lock = NSLock()
    private var last = 0.0, period = 1.0 / 60, updated = 0.0
    func update(timestamp: Double, target: Double, now: Double) {
        lock.withLock { let p = target - timestamp; if p > 0.004 && p < 0.05 { period = p }; last = timestamp; updated = now }
    }
    /// First grid point strictly after `t`, the sample age at `t`, and the period. Returns v == 0 before the first sample.
    func next(after t: Double) -> (v: Double, age: Double, period: Double) {
        lock.withLock {
            guard last > 0 else { return (0, .infinity, period) }
            return (last + (floor((t - last) / period) + 1) * period, t - updated, period)
        }
    }
}

enum VsyncTarget {
    /// Next target VSync. The refresh the previous submit lands on is re-derived from the *current* lattice every time,
    /// so a single off-grid display-link sample cannot carry a phase error forward (no synthetic lastTarget + period),
    /// and the refresh already used by the previous submit is never targeted again.
    static func next(lattice: VsyncLattice, now: Double, lead: Double, lastSubmit: Double) -> (v: Double, age: Double) {
        let (v0, age, period) = lattice.next(after: now + lead + 0.0003)
        guard v0 > 0, lastSubmit > 0 else { return (v0, age) }
        let landing = lattice.next(after: lastSubmit + 0.0005).v
        if v0 > landing + period / 2 { return (v0, age) }
        return (lattice.next(after: landing + period / 2).v, age)
    }
}

final class OriginalPresenter: @unchecked Sendable {
    static let staleLimit = 0.1                     // stop submitting when the newest display-link sample is older
    let lattice = VsyncLattice()
    private let lock = NSLock()
    private var active = false, stopped = false, idle = true, drawableSize = CGSize.zero
    private var scalingStatus: ScalingStatus?
    private var policyApplied: Bool?
    private var source: LiveVideo?
    private let queue: any MTLCommandQueue
    private let pipeline: any MTLRenderPipelineState
    private let inFlight: DispatchSemaphore
    private let presentationQueue: PresentationQueue
    private let layer: CAMetalLayer
    private let cache: CVMetalTextureCache
    private let lead: Double
    private let finished = DispatchSemaphore(value: 0)
    private var started = false

    init(queue: any MTLCommandQueue, pipeline: any MTLRenderPipelineState, inFlight: DispatchSemaphore,
         presentationQueue: PresentationQueue, layer: CAMetalLayer, device: any MTLDevice, lead: Double = 0.003) throws {
        self.queue = queue; self.pipeline = pipeline; self.inFlight = inFlight; self.presentationQueue = presentationQueue
        self.layer = layer; self.lead = lead
        var c: CVMetalTextureCache?
        guard CVMetalTextureCacheCreate(nil, nil, device, nil, &c) == kCVReturnSuccess, let c else {
            throw RenderError.unavailable("Unable to create the render worker texture cache.")
        }
        cache = c
    }
    func configure(source: LiveVideo?) { lock.withLock { self.source = source } }
    /// The worker only draws while active; inactive, it parks without touching the queue or drawables.
    func setActive(_ on: Bool) { lock.withLock { active = on && !stopped } }
    /// True once the thread has observed `active == false` (no render in progress).
    var isIdle: Bool { lock.withLock { idle } }
    /// Size of the last drawable rendered (diagnostic; follows CAMetalLayer.drawableSize changes).
    var lastDrawableSize: CGSize { lock.withLock { drawableSize } }
    /// Scaling status of the last rendered frame, for the main thread to forward to the UI (scalingReport).
    var lastScalingStatus: ScalingStatus? { lock.withLock { scalingStatus } }
    /// Result of applying the time-constraint policy to the render thread (nil until the thread has started).
    var timeConstraintApplied: Bool? { lock.withLock { policyApplied } }

    func start() {
        lock.withLock { guard !started else { return }; started = true }
        let t = Thread { [self] in
            let applied = applyTimeConstraintPolicy(periodMs: 16.667, computationMs: 2.0, constraintMs: 4.0)
            lock.withLock { policyApplied = applied }
            var ticks = mach_timebase_info_data_t(); mach_timebase_info(&ticks)
            let perSecond = 1e9 * Double(ticks.denom) / Double(ticks.numer)
            var lastSubmit = 0.0
            while true {
                let (on, quit) = lock.withLock { () -> (Bool, Bool) in idle = !active; return (active, stopped) }
                if quit { finished.signal(); return }
                if !on { usleep(2000); lastSubmit = 0; continue }
                let now = CACurrentMediaTime()
                let (v, age) = VsyncTarget.next(lattice: lattice, now: now, lead: lead, lastSubmit: lastSubmit)
                if v == 0 || age > Self.staleLimit { usleep(2000); continue }
                let planned = v - lead
                if planned > CACurrentMediaTime() { mach_wait_until(UInt64(planned * perSecond)) }
                guard lock.withLock({ active && !stopped }) else { continue }
                if autoreleasepool(invoking: { renderOne(at: CACurrentMediaTime()) }) { lastSubmit = CACurrentMediaTime() }
            }
        }
        t.name = "XFrame Original render worker"; t.qualityOfService = .userInteractive; t.start()
    }
    /// Stops the thread and waits (bounded). Idempotent. Returns false only on timeout.
    @discardableResult
    func stop(timeout: Double = 1.0) -> Bool {
        let wasStarted = lock.withLock { () -> Bool in let s = started && !stopped; stopped = true; active = false; source = nil; return s }
        guard wasStarted else { return true }
        return finished.wait(timeout: .now() + timeout) == .success
    }

    /// Returns true when a frame was submitted.
    private func renderOne(at now: Double) -> Bool {
        guard let live = lock.withLock({ source }) else { return false }
        // Same HUD accounting as the MTK path: one draw tick per render attempt, busy when no GPU permit is free.
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
        // nextDrawable can block (up to 1 s). If ownership was withdrawn or the worker was stopped meanwhile (e.g. a
        // timed-out stop), do not present: the MTK path may already own drawing again.
        guard lock.withLock({ active && !stopped }) else { presentation.finish(); inFlight.signal(); return false }
        lock.withLock { drawableSize = CGSize(width: drawable.texture.width, height: drawable.texture.height) }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        pass.colorAttachments[0].storeAction = .store
        let plan = ScalingPlan.make(mode: .original, source: ScalingExtent(width: video.luma.width, height: video.luma.height),
                                    canvas: ScalingExtent(width: drawable.texture.width, height: drawable.texture.height),
                                    fullscreen: false, supported: false)
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { presentation.finish(); inFlight.signal(); return false }
        live.performance.setScaling(plan.status)
        lock.withLock { scalingStatus = plan.status }
        encoder.setViewport(MTLViewport(originX: plan.x, originY: plan.y, width: plan.width, height: plan.height, znear: 0, zfar: 1))
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(video.luma, index: 0); encoder.setFragmentTexture(video.chroma, index: 1)
        var conversion = video.conversion
        encoder.setFragmentBytes(&conversion, length: MemoryLayout<SIMD4<Float>>.size, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        let sample = FramePresentation(source: live, arrivedAt: frame.arrivedAt, submittedAt: CACurrentMediaTime(),
                                       sourceRTP: frame.sourceRTP, frameID: frame.id)
        let permit = inFlight
        command.addCompletedHandler { command in
            withExtendedLifetime(video) {}
            if command.status == .error {
                presentation.finish(); live.fail("Metal rendering failed: \(command.error?.localizedDescription ?? "Unknown GPU error")")
            }
            if command.status == .completed, command.gpuStartTime > 0, command.gpuEndTime >= command.gpuStartTime {
                sample.gpuCompleted(start: command.gpuStartTime, end: command.gpuEndTime)
            }
            permit.signal()
        }
        drawable.addPresentedHandler { presented in sample.presented(at: presented.presentedTime) }
        drawable.addPresentedHandler { _ in presentation.finish() }
        command.present(drawable)
        command.commit()
        return true
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
