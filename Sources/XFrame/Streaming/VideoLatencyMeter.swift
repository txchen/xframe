import Foundation

// Jitter-buffer counters are cumulative seconds and emitted frames. Report only
// an interval average from the same inbound report with increasing timestamps.
struct VideoLatencyMeter {
    private var previous: (id: String, time: Double, delay: Double, count: Double)?
    mutating func sample(id: String?, timestampUS: Double?, delay: Double?, count: Double?) -> Double? {
        guard let id, !id.isEmpty, let time = timestampUS, time.isFinite, time > 0,
              let delay, delay.isFinite, delay >= 0, let count, count.isFinite, count >= 0 else {
            previous = nil
            return nil
        }
        if let old = previous, old.id == id, time <= old.time { return nil }
        let old = previous
        previous = (id, time, delay, count)
        guard let old, old.id == id, delay >= old.delay, count > old.count else { return nil }
        let value = (delay - old.delay) / (count - old.count) * 1000
        return value.isFinite && value >= 0 ? value : nil
    }
}
