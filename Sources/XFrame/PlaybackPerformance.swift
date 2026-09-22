import Foundation

struct TimingSummary: Codable, Equatable, Sendable {
    let count: Int
    let recentCount: Int
    let meanMS, p50MS, p95MS, maxMS: Double
}

struct PlaybackTimingSnapshot: Codable, Equatable, Sendable {
    var decode: TimingSummary?
    var frameWait: TimingSummary?
    var gpu: TimingSummary?
    var presentation: TimingSummary?
}

// All distributions describe the latest 256 valid samples, not a lifetime p95.
// Empty stages stay nil; unavailable GPU/presentation timestamps are not zero.
final class PlaybackPerformance: @unchecked Sendable {
    enum Stage { case decode, frameWait, gpu, presentation }
    private struct Window {
        var samples: [Double] = []
        var count = 0
        mutating func append(_ value: Double) {
            if samples.count < 256 { samples.append(value) }
            else { samples[count % 256] = value }
            count += 1
        }
        var summary: TimingSummary? {
            guard !samples.isEmpty else { return nil }
            let sorted = samples.sorted()
            return TimingSummary(count: count, recentCount: sorted.count,
                meanMS: sorted.reduce(0, +) / Double(sorted.count),
                p50MS: sorted[Int(ceil(Double(sorted.count) * 0.50)) - 1],
                p95MS: sorted[Int(ceil(Double(sorted.count) * 0.95)) - 1], maxMS: sorted.last!)
        }
    }
    private let lock = NSLock()
    private var windows: [Stage: Window] = [:]
    private var stopped = false
    func record(_ stage: Stage, seconds: Double) {
        guard seconds.isFinite, seconds >= 0, (seconds * 1000).isFinite else { return }
        lock.withLock {
            guard !stopped else { return }
            windows[stage, default: Window()].append(seconds * 1000)
        }
    }
    func stop() { lock.withLock { stopped = true } }
    func snapshot() -> PlaybackTimingSnapshot {
        lock.withLock { PlaybackTimingSnapshot(decode: windows[.decode]?.summary,
            frameWait: windows[.frameWait]?.summary, gpu: windows[.gpu]?.summary,
            presentation: windows[.presentation]?.summary) }
    }
}

// Preserve a newly consumed frame when the drawable is temporarily unavailable.
struct RenderWorkState {
    private(set) var pendingFrame = false
    mutating func receivedFrame() { pendingFrame = true }
    func needsDraw(hasSource: Bool, resized: Bool) -> Bool { !hasSource || pendingFrame || resized }
    mutating func submitted() { pendingFrame = false }
}
