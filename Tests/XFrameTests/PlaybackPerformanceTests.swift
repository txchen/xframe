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
