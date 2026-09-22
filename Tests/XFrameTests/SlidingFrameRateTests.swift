import Testing
@testable import XFrame

@Test func recentFPSForgetsLongThirtyFPSHistoryWithinTwoSeconds() {
    var meter = SlidingFrameRate()
    for frame in 0..<3000 { meter.note(at: Double(frame) / 30) }
    let before = meter.rate(at: 100)
    #expect(before == 29.5 || before == 30) // Exact left boundary is excluded.
    for frame in 1...120 { meter.note(at: 100 + Double(frame) / 60) }
    let after = meter.rate(at: 102)
    #expect(after == 60)
    let stalled = meter.rate(at: 104.1)
    #expect(stalled == 0)
}

@Test func recentFPSWarmupPauseRecoveryAndFreshSource() {
    var meter = SlidingFrameRate()
    let empty = meter.rate(at: 0)
    #expect(empty == nil)
    meter.note(at: 10)
    let warmup = meter.rate(at: 10.1)
    #expect(warmup == nil)
    for frame in 1...120 { meter.note(at: 10 + Double(frame) / 60) }
    let running = meter.rate(at: 12)
    #expect(running == 60)
    let paused = meter.rate(at: 15)
    #expect(paused == 0)
    for frame in 1...60 { meter.note(at: 15 + Double(frame) / 30) }
    let recovered = meter.rate(at: 17)
    #expect(recovered == 30)
    var fresh = SlidingFrameRate()
    let freshRate = fresh.rate(at: 17)
    #expect(freshRate == nil)
}
