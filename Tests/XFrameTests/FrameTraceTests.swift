import Testing
@testable import XFrame

@Test func frameTraceRetainsOrderedBoundedTailAndFreezes() {
    let trace = FrameTrace(capacity: 3)
    for i in 0..<5 { trace.note(.decoderInput, rtp: UInt32(i), at: Double(i)) }
    #expect(trace.snapshot().map(\.rtp) == [2, 3, 4])
    trace.stop()
    trace.note(.decoded, rtp: 5)
    #expect(trace.snapshot().map(\.rtp) == [2, 3, 4])
}

@Test func presentationTraceUsesDrawableTimeAndDoesNotCountRedrawTwice() {
    let source = LiveVideo()
    let sample = FramePresentation(source: source, arrivedAt: 1, submittedAt: 1.01, sourceRTP: 9000, frameID: 7)
    sample.presented(at: 1.03)
    sample.presented(at: 1.04)
    let events = source.frameTrace.snapshot()
    #expect(events.count == 1)
    #expect(events.first?.stage == .presented)
    #expect(events.first?.rtp == 9000)
    #expect(events.first?.frameID == 7)
    let missed = FramePresentation(source: source, arrivedAt: 2, submittedAt: 2.01, sourceRTP: 10500, frameID: 8)
    missed.presented(at: 0)
    #expect(source.frameTrace.snapshot().count == 1)
}
