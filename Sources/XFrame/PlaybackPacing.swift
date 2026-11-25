import Foundation
import QuartzCore

enum FramePacingMode: String, CaseIterable, Codable, Sendable {
    case balanced, adaptive
    var title: String {
        switch self {
        case .balanced: "Balanced"
        case .adaptive: "Adaptive smoothing"
        }
    }
    var shortTitle: String {
        switch self {
        case .balanced: "Balanced"
        case .adaptive: "Adaptive"
        }
    }
    var capacity: Int {
        switch self { case .balanced: 2; case .adaptive: 4 }
    }
}

// Receiver-relative scheduling only: RTP cannot establish capture-to-screen latency.
// One-second transit buckets keep estimator memory bounded independently of FPS.
struct RTPFramePacer {
    private struct TransitBucket {
        var second: Int
        var minimum: Double
        var maximum: Double
    }
    static let minimumBuffer = 0.004
    static let maximumBuffer = 0.040
    private(set) var buffer = minimumBuffer
    private var previousRTP: UInt32?
    private var previousArrival = 0.0
    private var mediaTime = 0.0
    private var origin = 0.0
    private var buckets: [TransitBucket] = []

    // Missing/backward RTP falls back to immediate delivery. A pause or large
    // timestamp jump starts a new clock epoch instead of building a long queue.
    mutating func deadline(rtp: UInt32, arrival: Double) -> Double {
        guard arrival.isFinite else { return arrival }
        let elapsed = arrival - previousArrival
        let ticks = previousRTP.map { Int32(bitPattern: rtp &- $0) }
        if previousRTP == nil || elapsed > 1 || elapsed < 0 || (ticks.map { $0 > 90_000 || $0 < -90_000 } ?? false) {
            self = Self()
            previousRTP = rtp
            previousArrival = arrival
            origin = arrival
            buckets = [TransitBucket(second: 0, minimum: 0, maximum: 0)]
            return arrival + buffer
        }
        guard let ticks, ticks > 0 else { return arrival }
        previousRTP = rtp
        previousArrival = arrival
        mediaTime += Double(ticks) / 90_000
        let transit = arrival - origin - mediaTime
        let second = Int((arrival - origin).rounded(.down))
        buckets.removeAll { $0.second < second - 5 }
        if buckets.last?.second == second {
            buckets[buckets.count - 1].minimum = min(buckets[buckets.count - 1].minimum, transit)
            buckets[buckets.count - 1].maximum = max(buckets[buckets.count - 1].maximum, transit)
        } else {
            buckets.append(TransitBucket(second: second, minimum: transit, maximum: transit))
        }
        let baseline = buckets.map(\.minimum).min() ?? transit
        let worst = buckets.map(\.maximum).max() ?? transit
        let target = min(Self.maximumBuffer, max(Self.minimumBuffer, worst - baseline + Self.minimumBuffer))
        buffer = max(target, buffer - max(0, elapsed) * 0.002)
        return min(arrival + Self.maximumBuffer, max(arrival, origin + mediaTime + baseline + buffer))
    }
}

struct PlaybackPacingSnapshot: Codable, Equatable, Sendable {
    var inboxReplaced = 0
    var rendererReplaced = 0
    var drawTicks = 0
    var busyTicks = 0
    var drawableMisses = 0
    var notPresented = 0
    var arrivalInterval: TimingSummary?
    var drawInterval: TimingSummary?
    var drawableWait: TimingSummary?
}
