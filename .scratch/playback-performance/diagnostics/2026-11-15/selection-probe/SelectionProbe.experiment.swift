import Foundation
import QuartzCore

final class SelectionProbe: @unchecked Sendable {
    static let shared = SelectionProbe()
    private let lock = NSLock()
    private var block = -1
    private var rows: [[String: Double]] = []
    var latest: Bool { lock.withLock { block >= 0 && block % 2 == 1 } }
    func transition(_ value: Int) {
        lock.withLock {
            block = value
            rows.append(["block": Double(value), "marker": CACurrentMediaTime()])
        }
        save()
    }
    func note(_ id: Int, stage: Int, at: Double = CACurrentMediaTime(), _ values: [String: Double] = [:]) {
        lock.withLock {
            guard block >= 0, rows.count < 200000 else { return }
            var row = values
            row["id"] = Double(id); row["stage"] = Double(stage); row["time"] = at; row["block"] = Double(block)
            rows.append(row)
        }
    }
    func save() {
        let snapshot = lock.withLock { rows }
        let url = URL(fileURLWithPath: "/Users/hibiki/code/vibe/xframe/.build/selection-probe/events.json")
        if let data = try? JSONSerialization.data(withJSONObject: snapshot) { try? data.write(to: url, options: .atomic) }
    }
}
