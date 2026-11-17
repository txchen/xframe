import MetalKit

final class PhaseWorker: @unchecked Sendable {
    private let condition = NSCondition()
    private var stopped = false
    private var pendingTarget: Double?
    private let finished = DispatchSemaphore(value:0)
    private let layer: CAMetalLayer
    private let source: LiveVideo
    private let engine: WorkerProbeEngine
    init(layer: CAMetalLayer, source: LiveVideo, engine: WorkerProbeEngine) {
        self.layer=layer;self.source=source;self.engine=engine
    }
    func wake(target: Double) {
        condition.lock();pendingTarget=target;condition.signal();condition.unlock()
    }
    func start() {
        Thread.detachNewThread { [self] in
            Thread.current.name="XFrame phase rendering probe"
            Thread.current.qualityOfService = .userInteractive
            defer { finished.signal() }
            while true {
                condition.lock()
                while pendingTarget == nil && !stopped { condition.wait() }
                if stopped { condition.unlock(); return }
                let target = pendingTarget!;pendingTarget=nil;condition.unlock()
                let deadline=target-0.004
                if deadline>CACurrentMediaTime() {mach_wait_until(UInt64(deadline*CVGetHostClockFrequency()))}
                if condition.withLock({stopped}) {return}
                autoreleasepool {
                    let now=CACurrentMediaTime()
                    guard target-now>=0.002 else {LiveWorkerLog.shared.add(["missedDeadline":now,"target":target]);return}
                    let start=CACurrentMediaTime()
                    guard let drawable=layer.nextDrawable() else {LiveWorkerLog.shared.add(["drawableMiss":1]);return}
                    source.performance.record(.drawableWait,seconds:CACurrentMediaTime()-start)
                    guard target-CACurrentMediaTime()>=0.002 else {LiveWorkerLog.shared.add(["missedDeadline":CACurrentMediaTime(),"target":target]);return}
                    LiveWorkerLog.shared.add(["tick":CACurrentMediaTime(),"target":target])
                    guard let frame=source.nextFrame(at:CACurrentMediaTime()) else {return}
                    source.performance.note(.draw)
                    engine.render(frame,drawable:drawable,presented:{})
                }
            }
        }
    }
    func stop() -> Bool {
        condition.lock();stopped=true;condition.broadcast();condition.unlock()
        return finished.wait(timeout:.now()+2) == .success
    }
}
