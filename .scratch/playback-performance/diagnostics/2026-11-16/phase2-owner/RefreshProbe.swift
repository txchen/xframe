import MetalKit

final class LiveWorkerLog: @unchecked Sendable {
    static let shared=LiveWorkerLog()
    private let lock=NSLock()
    private var rows:[[String:Double]]=[]
    private var identifier=0
    private var block = -1
    private let root=URL(fileURLWithPath:"/Users/hibiki/code/vibe/xframe/.build/phase2-owner-probe")
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

