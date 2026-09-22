import Testing
@testable import XFrame

@Test func zeroDrawableTimeDoesNotCountAsDisplayed() {
    let source = LiveVideo()
    let sample = FramePresentation(source: source, arrivedAt: 1, submittedAt: 1.01)
    sample.presented(at: 0)
    #expect(source.snapshot().presented == 0)
    #expect(source.snapshot().timings.presentation == nil)
}

@Test func presentationJoinsReversedCallbacksWithoutOverlappingIntervals() throws {
    let source = LiveVideo()
    let sample = FramePresentation(source: source, arrivedAt: 1, submittedAt: 1.010)
    sample.presented(at: 1.030)
    sample.gpuCompleted(start: 1.011, end: 1.013)
    sample.gpuCompleted(start: 1.011, end: 1.013)
    sample.presented(at: 1.030)
    let stats = source.snapshot()
    #expect(stats.presented == 1)
    let timings = stats.timings
    let sum = try #require(timings.frameWait).meanMS + #require(timings.gpuQueue).meanMS + #require(timings.gpu).meanMS + #require(timings.displayWait).meanMS
    #expect(abs(sum - 30) < 0.001)
    #expect(abs(try #require(timings.presentation).meanMS - sum) < 0.001)
}

@Test func missingOrLatePresentationDoesNotInventLatencyOrChangeStoppedReports() throws {
    let source = LiveVideo()
    let sample = FramePresentation(source: source, arrivedAt: 1, submittedAt: 1.01)
    sample.gpuCompleted(start: 1.011, end: 1.012)
    sample.presented(at: 0)
    #expect(source.snapshot().dropped == 1)
    #expect(source.snapshot().timings.pacing.notPresented == 1)
    #expect(source.snapshot().timings.displayWait == nil)
    let pending = FramePresentation(source: source, arrivedAt: 2, submittedAt: 2.01)
    source.stop()
    let before = try source.diagnosticReport().encoded()
    pending.presented(at: 2.03)
    pending.gpuCompleted(start: 2.011, end: 2.012)
    #expect(try source.diagnosticReport().encoded() == before)
}
