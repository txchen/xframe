import Foundation
import Testing
@testable import XFrame

@Test func performanceWindowsAreBoundedAndRejectInvalidSamples() throws {
    let performance = PlaybackPerformance()
    #expect(performance.snapshot().gpu == nil)
    for value in [Double.nan, .infinity, -1] { performance.record(.gpu, seconds: value) }
    #expect(performance.snapshot().gpu == nil)
    for index in 1...1000 { performance.record(.decode, seconds: Double(index) / 1000) }
    let decode = try #require(performance.snapshot().decode)
    #expect(decode.count == 1000 && decode.recentCount == 256)
    #expect(abs(decode.meanMS - 872.5) < 0.0001)
    #expect(abs(decode.p50MS - 872) < 0.0001)
    #expect(abs(decode.p95MS - 988) < 0.0001)
    performance.stop()
    let stopped = performance.snapshot()
    performance.record(.decode, seconds: 1)
    #expect(performance.snapshot() == stopped)
}

@Test func rendererSkipsIdleDrawablesButRetainsUnsubmittedFrames() {
    var work = RenderWorkState()
    #expect(!work.needsDraw(hasSource: true, resized: false))
    #expect(work.needsDraw(hasSource: false, resized: false))
    #expect(work.needsDraw(hasSource: true, resized: true))
    let firstReplaced = work.receivedFrame()
    let nextReplaced = work.receivedFrame()
    #expect(!firstReplaced)
    #expect(nextReplaced) // A pending frame replaced before submission is a skip.
    for _ in 0..<5 { #expect(work.needsDraw(hasSource: true, resized: false)) }
    work.submitted()
    #expect(!work.pendingFrame)
    #expect(!work.needsDraw(hasSource: true, resized: false))
}

@Test func replacedRendererFramesCountAsSkipsButLateCallbacksDoNot() {
    let source = LiveVideo()
    source.didSkipFrame()
    #expect(source.snapshot().dropped == 1)
    source.stop()
    source.didSkipFrame()
    #expect(source.snapshot().dropped == 1)
}

@Test func pacingCountersDistinguishInboxAndRendererLossAndFreezeOnStop() throws {
    let performance = PlaybackPerformance()
    performance.note(.arrival, at: 1)
    performance.note(.arrival, at: 1.020)
    performance.note(.draw, at: 1)
    performance.note(.draw, at: 1.016)
    performance.note(.inboxReplaced)
    performance.note(.rendererReplaced)
    performance.note(.busy)
    performance.note(.drawableMiss)
    let pacing = performance.snapshot().pacing
    #expect(pacing.inboxReplaced == 1 && pacing.rendererReplaced == 1)
    #expect(pacing.busyTicks == 1 && pacing.drawableMisses == 1 && pacing.drawTicks == 2)
    #expect(abs(try #require(pacing.arrivalInterval).meanMS - 20) < 0.001)
    #expect(abs(try #require(pacing.drawInterval).meanMS - 16) < 0.001)
    performance.stop()
    performance.note(.inboxReplaced)
    #expect(performance.snapshot().pacing == pacing)
}
