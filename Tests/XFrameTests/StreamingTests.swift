import Foundation
import CoreVideo
import VideoToolbox
import Testing
@preconcurrency import WebRTC
@testable import XFrame

@Test func lateErrorsDoNotInvalidateANewerRecoveryKeyframe() {
    var recovery = H264RecoveryState()
    recovery.submittedIDR(unit: 1)
    recovery.failed(unit: 2)
    #expect(recovery.needsIDR)
    recovery.submittedIDR(unit: 10)
    recovery.failed(unit: 3)
    #expect(!recovery.needsIDR)
    recovery.failed(unit: 10)
    #expect(recovery.needsIDR)
}

@Test func streamEventTimelineIsBoundedOrderedAndCorrelatesFailures() {
    let source = LiveVideo()
    source.decoderConfigured()
    let unit = source.submittedAccessUnit(keyframe: true, missingFrames: false)
    source.recoverableDecodeError(synchronous: true, keyframe: true, unit: unit)
    source.recoverableDecodeError(synchronous: false, keyframe: true, unit: unit)
    let initial = source.diagnosticEvents()
    #expect(initial.map(\.kind) == [.configured, .idrSubmitted, .badData, .badData])
    #expect(initial.suffix(2).allSatisfy { $0.accessUnit == unit })
    #expect(source.takeKeyframeRequest())
    #expect(source.diagnosticEvents().last?.kind == .keyframeRequestDequeued)
    for index in 0..<300 { source.networkSample(received: index, lost: index, nacks: index) }
    let bounded = source.diagnosticEvents()
    #expect(bounded.count == LiveVideo.eventLimit)
    #expect(zip(bounded, bounded.dropFirst()).allSatisfy { $0.milliseconds <= $1.milliseconds })
    source.stop()
    let stopped = source.diagnosticsText()
    source.decoderConfigured()
    source.recoverableDecodeError()
    #expect(!source.takeKeyframeRequest())
    #expect(source.diagnosticsText() == stopped)
}

@Test func hardwareDecoderRecoversAfterDamagedAndMissingAccessUnits() throws {
    let bytes = try Data(contentsOf: URL(fileURLWithPath: ".build/fixtures/h264-1080p60.h264"))
    var accessUnits: [Data] = []
    var current = Data()
    for nal in H264AccessUnit.nalUnits(bytes) {
        if nal.first! & 31 == 9, !current.isEmpty { accessUnits.append(current); current = Data() }
        current.append(contentsOf: [0, 0, 0, 1]); current.append(nal)
    }
    if !current.isEmpty { accessUnits.append(current) }
    let laterIDR = try #require(accessUnits.indices.dropFirst().first { index in
        H264AccessUnit.nalUnits(accessUnits[index]).contains { $0.first! & 31 == 5 }
    })
    let source = LiveVideo()
    let decoder = HardwareH264Decoder(output: source)
    decoder.setCallback { source.renderFrame($0) }
    _ = decoder.startDecode(withNumberOfCores: 1)
    for (index, data) in accessUnits.enumerated() {
        if (1..<20).contains(index) { continue }
        let image = RTCEncodedImage()
        // Keep the first format/IDR intact, then inject a truncated delta slice.
        image.buffer = index == 20 ? Data([0, 0, 0, 1, 0x41, 0]) : data
        image.timeStamp = UInt32(index * 1500)
        image.rotation = ._0
        _ = decoder.decode(image, missingFrames: index == 20, codecSpecificInfo: nil,
                           renderTimeMs: Int64(index * 1000 / 60))
        decoder.waitForPendingFrames()
    }
    _ = decoder.release()
    let stats = source.snapshot()
    #expect(!stats.state.hasPrefix("Failed:"))
    #expect(stats.decodeErrors > 0)
    #expect(stats.decodeErrors <= 2)
    #expect(stats.recoverySkippedFrames > 0)
    #expect(stats.missingFrameSignals == 1)
    #expect(stats.decoded >= accessUnits.count - laterIDR)
    let last = try #require(source.nextFrame(at: 0))
    #expect(last.time > 11)
    #expect(stats.hardware)
    #expect(stats.queued == LiveVideo.displayCapacity)
}

@Test func h264SamplePreservesSupplementalNALUnits() {
    let sps = Data([0x67, 1]), pps = Data([0x68, 2])
    let sei = Data([0x06, 3]), aud = Data([0x09, 4]), slice = Data([0x65, 5])
    #expect(H264AccessUnit.samplePayload([sps, pps, sei, aud, slice]) ==
            H264AccessUnit.lengthPrefixed([sei, aud, slice]))
    #expect(H264AccessUnit.samplePayload([sps, pps, sei]).isEmpty)
}

@Test func liveDiagnosticsClassifyFailuresAndIgnoreLateNetworkSamples() {
    let source = LiveVideo()
    let decoder = HardwareH264Decoder(output: source)
    decoder.handleDecodeFailure(kVTVideoDecoderBadDataErr, synchronous: true, keyframe: true)
    decoder.handleDecodeFailure(kVTVideoDecoderBadDataErr, synchronous: false, keyframe: false)
    source.networkSample(received: 100, lost: 2, nacks: 3)
    let stats = source.snapshot()
    #expect(stats.decodeErrors == 2)
    #expect(stats.synchronousDecodeErrors == 1)
    #expect(stats.asynchronousDecodeErrors == 1)
    #expect(stats.keyframeDecodeErrors == 1)
    #expect(stats.videoPacketsReceived == 100)
    #expect(stats.videoPacketsLost == 2)
    #expect(stats.videoNacks == 3)
    source.stop()
    source.networkSample(received: 200, lost: 4, nacks: 5)
    #expect(source.snapshot().videoPacketsReceived == 100)
}

@Test func cloudRegionSelectionUsesOnlyAuthorizedEndpoints() throws {
    let regions = [
        CloudToken.Settings.Region(name: "WESTUS", baseUri: URL(string: "https://west.gssv.xboxlive.com")!, isDefault: false),
        CloudToken.Settings.Region(name: "WESTUS2", baseUri: URL(string: "https://west2.gssv.xboxlive.com")!, isDefault: true)
    ]
    let token = CloudToken(gsToken: "test", durationInSeconds: 3600, market: "US",
                          offeringSettings: .init(regions: regions))
    let expires = Date().addingTimeInterval(3600)
    #expect(try CloudService(credential: token, expires: expires).regionName == "WESTUS2")
    #expect(try CloudService(credential: token, expires: expires, regionName: "WESTUS").regionName == "WESTUS")
    #expect(throws: (any Error).self) {
        try CloudService(credential: token, expires: expires, regionName: "UNKNOWN")
    }
    let fallback = CloudToken(gsToken: "test", durationInSeconds: 3600, market: "US",
                             offeringSettings: .init(regions: [regions[0]]))
    #expect(try CloudService(credential: fallback, expires: expires).regionName == "WESTUS")
}

@Test func annexBParsingAndLengthPrefixes() {
    let data = Data([0, 0, 0, 1, 0x67, 3, 4, 0, 0, 1, 0x68, 5, 0, 0, 1, 0x65, 6, 7])
    let units = H264AccessUnit.nalUnits(data)
    #expect(units == [Data([0x67, 3, 4]), Data([0x68, 5]), Data([0x65, 6, 7])])
    #expect(H264AccessUnit.lengthPrefixed([Data([0x65, 6, 7])]) == Data([0, 0, 0, 3, 0x65, 6, 7]))
    #expect(H264AccessUnit.nalUnits(Data([0, 0, 1])).isEmpty)
    #expect(H264AccessUnit.nalUnits(Data([1, 2, 3])).isEmpty)
}

@Test func iceCandidateDecodesStringAndNumericIndices() throws {
    for json in [#"{"candidate":"candidate:test","sdpMid":"0","sdpMLineIndex":"0"}"#,
                 #"{"candidate":"candidate:test","sdpMid":"0","sdpMLineIndex":0}"#] {
        let candidate = try JSONDecoder().decode(CloudICECandidate.self, from: Data(json.utf8))
        #expect(candidate.sdpMLineIndex == 0)
        #expect(candidate.sdpMid == "0")
    }
}

@Test func damagedH264FrameDoesNotTerminateTheStream() {
    let source = LiveVideo()
    let decoder = HardwareH264Decoder(output: source)
    decoder.handleDecodeFailure(kVTVideoDecoderBadDataErr)
    #expect(!source.snapshot().state.hasPrefix("Failed:"))
    #expect(source.snapshot().decodeErrors == 1)
    #expect(source.snapshot().errorsBeforeFirstFrame == 1)
    #expect(source.takeKeyframeRequest())
    #expect(!source.takeKeyframeRequest())
    decoder.handleDecodeFailure(noErr)
    #expect(!source.snapshot().state.hasPrefix("Failed:"))
    decoder.handleDecodeFailure(kVTVideoDecoderMalfunctionErr)
    #expect(source.snapshot().state.hasPrefix("Failed:"))
}

@Test func streamingDecoderProducesHardwareNV12WithBoundedDisplaySlot() throws {
    let url = URL(fileURLWithPath: ".build/fixtures/h264-1080p60.h264")
    let bytes = try Data(contentsOf: url)
    var accessUnits: [Data] = []
    var current = Data()
    for nal in H264AccessUnit.nalUnits(bytes) {
        if nal.first! & 31 == 9, !current.isEmpty { accessUnits.append(current); current = Data() }
        current.append(contentsOf: [0, 0, 0, 1]); current.append(nal)
    }
    if !current.isEmpty { accessUnits.append(current) }
    #expect(accessUnits.count == 720)
    let source = LiveVideo()
    let decoder = HardwareH264Decoder(output: source)
    decoder.setCallback { source.renderFrame($0) }
    #expect(decoder.startDecode(withNumberOfCores: 1) == 0)
    for (index, data) in accessUnits.enumerated() {
        let image = RTCEncodedImage()
        image.buffer = data
        image.timeStamp = UInt32(index * 1500)
        image.rotation = ._0
        #expect(decoder.decode(image, missingFrames: false, codecSpecificInfo: nil, renderTimeMs: Int64(index * 1000 / 60)) == 0)
    }
    #expect(decoder.release() == 0)
    let stats = source.snapshot()
    #expect(stats.hardware)
    #expect(stats.decoded == 720)
    #expect(stats.queued == LiveVideo.displayCapacity)
    #expect(stats.dropped == 720 - LiveVideo.displayCapacity)
    #expect(stats.keyframeSubmissions > 0)
    #expect(stats.missingFrameSignals == 0)
    source.recoverableDecodeError()
    #expect(source.snapshot().decodeErrors == 1)
    #expect(source.snapshot().errorsBeforeFirstFrame == 0)
    let frame = try #require(source.nextFrame(at: 0))
    #expect(CVPixelBufferGetPixelFormatType(frame.buffer) == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)
    #expect(CVPixelBufferGetIOSurface(frame.buffer) != nil)
    source.stop()
    source.renderFrame(RTCVideoFrame(buffer: RTCCVPixelBuffer(pixelBuffer: frame.buffer), rotation: ._0, timeStampNs: 0))
    #expect(source.snapshot().decoded == 720)
    #expect(source.nextFrame(at: 0) == nil)
}

@Test func livePlaybackPreservesTwoFramesDeliveredBetweenDisplayTicks() throws {
    var buffer: CVPixelBuffer?
    #expect(CVPixelBufferCreate(kCFAllocatorDefault, 16, 16,
        kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, nil, &buffer) == kCVReturnSuccess)
    let pixelBuffer = try #require(buffer)
    let source = LiveVideo()
    for stamp: Int64 in [1_000_000_000, 1_016_666_667] {
        source.renderFrame(RTCVideoFrame(buffer: RTCCVPixelBuffer(pixelBuffer: pixelBuffer), rotation: ._0, timeStampNs: stamp))
    }
    // Two callbacks can fall between display ticks even with a 60 fps average.
    #expect(source.nextFrame(at: 0)?.id == 1)
    #expect(source.nextFrame(at: 0)?.id == 2)
    #expect(source.nextFrame(at: 0) == nil)
    #expect(source.snapshot().dropped == 0)
}

@Test func livePlaybackBoundsBacklogAndDropsStaleFramesAfterStalls() throws {
    var buffer: CVPixelBuffer?
    #expect(CVPixelBufferCreate(kCFAllocatorDefault, 16, 16,
        kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, nil, &buffer) == kCVReturnSuccess)
    let pixelBuffer = try #require(buffer)
    let source = LiveVideo()
    for stamp in 0..<10 {
        source.renderFrame(RTCVideoFrame(buffer: RTCCVPixelBuffer(pixelBuffer: pixelBuffer), rotation: ._0, timeStampNs: Int64(stamp)))
    }
    #expect(source.snapshot().queued == 2 && source.snapshot().peakQueue == 2)
    #expect(source.snapshot().dropped == 8)
    let first = try #require(source.nextFrame(at: 0))
    #expect(first.id == 9)
    // Simulate returning after a long blocked render callback; don't replay old input.
    #expect(source.nextFrame(at: first.arrivedAt + 1) == nil)
    #expect(source.snapshot().dropped == 9 && source.snapshot().queued == 0)
    source.renderFrame(RTCVideoFrame(buffer: RTCCVPixelBuffer(pixelBuffer: pixelBuffer), rotation: ._0, timeStampNs: 11))
    #expect(source.nextFrame(at: 0)?.id == 11)
    source.stop()
    #expect(source.snapshot().queued == 0)
}

@Test func livePlaybackPrefersFreshFrameAfterExcessBacklog() throws {
    var buffer: CVPixelBuffer?
    #expect(CVPixelBufferCreate(kCFAllocatorDefault, 16, 16,
        kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, nil, &buffer) == kCVReturnSuccess)
    let pixelBuffer = try #require(buffer)
    let source = LiveVideo()
    let start = CACurrentMediaTime()
    for stamp: Int64 in [1, 2] {
        source.renderFrame(RTCVideoFrame(buffer: RTCCVPixelBuffer(pixelBuffer: pixelBuffer), rotation: ._0, timeStampNs: stamp))
    }
    // A renderer stalled for 30 ms must not replay the oldest queued frame.
    #expect(source.nextFrame(at: start + 0.030)?.id == 2)
    #expect(source.snapshot().dropped == 1)
    #expect(source.nextFrame(at: start + 0.030) == nil)
}

@Test func livePlaybackKeepsOrdinaryOneFrameJitter() throws {
    var buffer: CVPixelBuffer?
    #expect(CVPixelBufferCreate(kCFAllocatorDefault, 16, 16,
        kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, nil, &buffer) == kCVReturnSuccess)
    let pixelBuffer = try #require(buffer)
    let source = LiveVideo()
    for stamp: Int64 in [1, 2] {
        source.renderFrame(RTCVideoFrame(buffer: RTCCVPixelBuffer(pixelBuffer: pixelBuffer), rotation: ._0, timeStampNs: stamp))
    }
    let consumeAt = CACurrentMediaTime() + 0.020
    #expect(source.nextFrame(at: consumeAt)?.id == 1)
    #expect(source.nextFrame(at: consumeAt)?.id == 2)
    #expect(source.snapshot().dropped == 0)
}

@Test func lowLatencyKeepsNewestWaitingFrameAndStillExpiresAfterStall() throws {
    var buffer: CVPixelBuffer?
    #expect(CVPixelBufferCreate(kCFAllocatorDefault, 16, 16,
        kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, nil, &buffer) == kCVReturnSuccess)
    let pixelBuffer = try #require(buffer)
    let source = LiveVideo(framePacing: .lowLatency)
    for stamp: Int64 in [1, 2, 3] {
        source.renderFrame(RTCVideoFrame(buffer: RTCCVPixelBuffer(pixelBuffer: pixelBuffer), rotation: ._0, timeStampNs: stamp))
    }
    #expect(source.snapshot().capacity == 1)
    #expect(source.snapshot().peakQueue == 1)
    #expect(source.snapshot().dropped == 2)
    let newest = try #require(source.nextFrame(at: 0))
    #expect(newest.id == 3)
    #expect(source.nextFrame(at: 0) == nil)
    source.renderFrame(RTCVideoFrame(buffer: RTCCVPixelBuffer(pixelBuffer: pixelBuffer), rotation: ._0, timeStampNs: 4))
    #expect(source.nextFrame(at: newest.arrivedAt + 1) == nil)
    #expect(source.snapshot().dropped == 3)
    let report = try #require(JSONSerialization.jsonObject(with: source.diagnosticReport().encoded()) as? [String: Any])
    #expect(report["framePacing"] as? String == "lowLatency")
    #expect(PerformanceHUDText.render(source.snapshot(), preset: .detailed, controller: "").contains("PACING Low latency (experimental)"))
    source.stop()
    source.renderFrame(RTCVideoFrame(buffer: RTCCVPixelBuffer(pixelBuffer: pixelBuffer), rotation: ._0, timeStampNs: 5))
    #expect(source.snapshot().queued == 0)
}
