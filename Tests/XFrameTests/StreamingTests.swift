import Foundation
import CoreVideo
import VideoToolbox
import Testing
@preconcurrency import WebRTC
@testable import XFrame

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
    #expect(stats.queued == 1)
    #expect(stats.dropped == 719)
    let frame = try #require(source.nextFrame(at: 0))
    #expect(CVPixelBufferGetPixelFormatType(frame.buffer) == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)
    #expect(CVPixelBufferGetIOSurface(frame.buffer) != nil)
    source.stop()
    source.renderFrame(RTCVideoFrame(buffer: RTCCVPixelBuffer(pixelBuffer: frame.buffer), rotation: ._0, timeStampNs: 0))
    #expect(source.snapshot().decoded == 720)
    #expect(source.nextFrame(at: 0) == nil)
}
