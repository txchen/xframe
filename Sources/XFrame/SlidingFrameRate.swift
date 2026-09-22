import Foundation

// Event timestamps give a true recent window, independent of HUD refresh cadence.
// Owner serializes access. Storage is bounded even if callbacks misbehave.
struct SlidingFrameRate {
    static let window = 2.0
    private var beganAt: Double?
    private var timestamps: [Double] = []
    private var overflowAt: Double?
    private static let capacity = 2048

    mutating func note(at time: Double) {
        guard time.isFinite, time >= (timestamps.last ?? beganAt ?? time) else { return }
        if beganAt == nil { beganAt = time }
        prune(at: time)
        if timestamps.count == Self.capacity {
            overflowAt = time
            timestamps.removeFirst()
        }
        timestamps.append(time)
    }

    mutating func rate(at time: Double) -> Double? {
        guard time.isFinite, let beganAt, time >= beganAt else { return nil }
        prune(at: time)
        let span = min(Self.window, time - beganAt)
        guard span >= 0.5, overflowAt.map({ time - $0 >= Self.window }) ?? true else { return nil }
        return Double(timestamps.count) / span
    }

    private mutating func prune(at time: Double) {
        let cutoff = time - Self.window
        if let first = timestamps.firstIndex(where: { $0 > cutoff }) {
            if first > 0 { timestamps.removeFirst(first) }
        } else { timestamps.removeAll(keepingCapacity: true) }
    }
}
