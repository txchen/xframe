import CoreVideo
import Foundation
import QuartzCore
import Testing
@preconcurrency import WebRTC
@testable import XFrame

@Test func rtpPacingUsesMediaIntervalsAndUnwrapsTheClock() {
    var pacer = RTPFramePacer()
    let first = pacer.deadline(rtp: UInt32.max - 749, arrival: 10)
    let second = pacer.deadline(rtp: 750, arrival: 10 + 1.0 / 60)
    #expect(abs(first - 10.004) < 0.000001)
    #expect(abs(second - first - 1.0 / 60) < 0.000001)
    #expect(abs(pacer.buffer - RTPFramePacer.minimumBuffer) < 0.000001)
}

@Test func rtpPacingAbsorbsBurstJitterWithBoundedDelayAndSlowRecovery() {
    var pacer = RTPFramePacer()
    _ = pacer.deadline(rtp: 0, arrival: 0)
    _ = pacer.deadline(rtp: 1500, arrival: 1.0 / 60 + 0.025)
    let peak = pacer.buffer
    #expect(abs(peak - 0.029) < 0.000001)
    let next = pacer.deadline(rtp: 3000, arrival: 1.0 / 60 + 0.025)
    #expect(next > 1.0 / 60 + 0.025)
    for index in 3...1500 {
        let arrival = Double(index) / 60
        let deadline = pacer.deadline(rtp: UInt32(index * 1500), arrival: arrival)
        #expect(deadline >= arrival)
        #expect(deadline <= arrival + RTPFramePacer.maximumBuffer + 0.000001)
        #expect(pacer.buffer <= RTPFramePacer.maximumBuffer)
        if index == 360 { #expect(pacer.buffer > RTPFramePacer.minimumBuffer) }
    }
    #expect(pacer.buffer < peak)
    #expect(abs(pacer.buffer - RTPFramePacer.minimumBuffer) < 0.000001)
}

@Test func rtpPacingFallsBackForInvalidOrderAndResetsAcrossPausesOrClockJumps() {
    var pacer = RTPFramePacer()
    _ = pacer.deadline(rtp: 3000, arrival: 1)
    #expect(pacer.deadline(rtp: 3000, arrival: 1.01) == 1.01)
    #expect(pacer.deadline(rtp: 1500, arrival: 1.02) == 1.02)
    #expect(abs(pacer.deadline(rtp: 4500, arrival: 5) - 5.004) < 0.000001)
    #expect(abs(pacer.deadline(rtp: 500_000, arrival: 5.01) - 5.014) < 0.000001)
    #expect(abs(pacer.deadline(rtp: 0, arrival: 5.02) - 5.024) < 0.000001)
}

@Test func adaptiveLiveVideoWaitsForRTPDeadlineBoundsBacklogAndKeepsActualPresentationStats() throws {
    var buffer: CVPixelBuffer?
    #expect(CVPixelBufferCreate(kCFAllocatorDefault, 16, 16,
        kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, nil, &buffer) == kCVReturnSuccess)
    let pixelBuffer = try #require(buffer)
    let source = LiveVideo(framePacing: .adaptive)
    let start = CACurrentMediaTime()
    func deliver(_ index: Int) {
        let frame = RTCVideoFrame(buffer: RTCCVPixelBuffer(pixelBuffer: pixelBuffer), rotation: ._0, timeStampNs: Int64(index) * 16_666_667)
        frame.timeStamp = Int32(index * 1500)
        source.renderFrame(frame)
    }
    deliver(0)
    #expect(source.nextFrame(at: start) == nil)
    let first = try #require(source.nextFrame(at: CACurrentMediaTime() + 0.005))
    #expect(first.sourceRTP == 0 && first.presentationDeadline != nil)
    #expect(source.snapshot().presented == 0)
    #expect(source.snapshot().timings.presentation == nil)
    for index in 1...100 { deliver(index) }
    #expect(source.snapshot().queued == 4 && source.snapshot().peakQueue == 4)
    #expect(source.snapshot().dropped == 96)
    #expect(source.nextFrame(at: CACurrentMediaTime() + 1) == nil)
    #expect(source.snapshot().queued == 0 && source.snapshot().dropped == 100)
    let fresh = LiveVideo(framePacing: .adaptive)
    #expect(fresh.snapshot().queued == 0)
    source.stop()
    deliver(101)
    #expect(source.snapshot().queued == 0)
}
