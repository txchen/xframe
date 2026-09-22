import Foundation
import QuartzCore

/// Numeric timing replay, deliberately separate from media capture. RTP uses a
/// 90 kHz source clock; local times share CACurrentMediaTime's monotonic clock.
final class FrameTrace: @unchecked Sendable {
    struct Event: Codable, Sendable {
        enum Stage: String, Codable, Sendable { case decoderInput, decoded, delivered, presented }
        let stage: Stage
        let rtp: UInt32
        let seconds: Double
        let frameID: Int?
    }
    private let lock = NSLock()
    private let origin = CACurrentMediaTime()
    private let capacity: Int
    private var events: [Event] = []
    private var cursor = 0
    private var stopped = false
    init(capacity: Int = 16_384) { self.capacity = max(1, capacity) }
    func note(_ stage: Event.Stage, rtp: UInt32, frameID: Int? = nil, at time: Double = CACurrentMediaTime()) {
        lock.withLock {
            guard !stopped, time.isFinite else { return }
            let event = Event(stage: stage, rtp: rtp, seconds: time - origin, frameID: frameID)
            if events.count < capacity { events.append(event) }
            else { events[cursor] = event; cursor = (cursor + 1) % capacity }
        }
    }
    func stop() { lock.withLock { stopped = true } }
    func snapshot() -> [Event] {
        lock.withLock { Array(events[cursor...]) + Array(events[..<cursor]) }
    }
}
