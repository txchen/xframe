import MetalKit

final class LiveWorkerLog: @unchecked Sendable {
    static let shared=LiveWorkerLog()
    private let lock=NSLock()
    private var rows:[[String:Double]]=[]
    private var identifier=0
    private var block = -1
    private let root=URL(fileURLWithPath:"/Users/hibiki/code/vibe/xframe/.build/live-worker-probe")
    func nextID()->Int {lock.withLock {identifier+=1;return identifier}}
    func reset() {lock.withLock {rows=[];block = -1}}
    func mark(_ value:Int) {lock.withLock {block=value;rows.append(["marker":CACurrentMediaTime(),"block":Double(value)])}}
    func add(_ row:[String:Double]) {lock.withLock {guard rows.count<200000 else{return};var r=row;r["block"]=Double(block);rows.append(r)}}
    func save() {
        let data=lock.withLock {try! JSONSerialization.data(withJSONObject:rows)}
        try! data.write(to:root.appendingPathComponent("events.json"),options:.atomic)
    }
    func report(_ report:StreamDiagnosticReport,block:Int) {
        let data=try! JSONEncoder().encode(report)
        try! data.write(to:root.appendingPathComponent("block-\(block).json"),options:.atomic)
    }
}

// Probe only. The thread owns the engine, and never reads AppKit views.
final class LiveWorkerLoop: @unchecked Sendable {
    private let condition=NSCondition()
    private var stopped=false
    private var notified=true
    private let presentationSlots=DispatchSemaphore(value:2)
    private let finished=DispatchSemaphore(value:0)
    private let layer:CAMetalLayer
    private let source:LiveVideo
    private let engine:WorkerProbeEngine
    init(layer:CAMetalLayer,source:LiveVideo,engine:WorkerProbeEngine) {
        self.layer=layer;self.source=source;self.engine=engine
    }
    private func wake() {condition.lock();notified=true;condition.signal();condition.unlock()}
    func start() {
        source.setProbeWake { [weak self] in self?.wake() }
        Thread.detachNewThread { [self] in
            Thread.current.name="XFrame live rendering probe"
            Thread.current.qualityOfService = .userInteractive
            defer {finished.signal()}
            while !condition.withLock({stopped}) {
                if presentationSlots.wait(timeout:.now()+0.05) != .success {continue}
                autoreleasepool {
                    var transferred=false
                    defer {if !transferred {presentationSlots.signal()}}
                    var selected: VideoFrame?
                    while !condition.withLock({stopped}) {
                        condition.lock();notified=false;condition.unlock()
                        if let frame=source.nextFrame(at:CACurrentMediaTime()) {selected=frame;break}
                        condition.lock()
                        if !notified && !stopped {_=condition.wait(until:Date(timeIntervalSinceNow:0.01))}
                        condition.unlock()
                    }
                    guard let frame=selected,!condition.withLock({stopped}) else {return}
                    let start=CACurrentMediaTime()
                    guard let drawable=layer.nextDrawable() else {source.didSkipFrame();LiveWorkerLog.shared.add(["drawableMiss":1]);return}
                    let ready=CACurrentMediaTime()
                    source.performance.record(.drawableWait,seconds:ready-start)
                    LiveWorkerLog.shared.add(["pickedFrame":Double(frame.id),"drawableBegin":start,"drawableReady":ready])
                    source.performance.note(.draw)
                    engine.render(frame,drawable:drawable) { [presentationSlots] in presentationSlots.signal() }
                    transferred=true
                }
            }
        }
    }
    func stop()->Bool {
        source.setProbeWake(nil)
        condition.lock();stopped=true;condition.broadcast();condition.unlock()
        return finished.wait(timeout:.now()+2) == .success
    }
}
