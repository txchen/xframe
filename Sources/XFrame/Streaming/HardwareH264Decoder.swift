import Foundation
import VideoToolbox
import QuartzCore
@preconcurrency import WebRTC

enum H264AccessUnit {
    // WebRTC's H.264 depacketizer supplies Annex B access units. Only compressed
    // bytes are copied here; decoded pixel planes stay on CoreVideo/Metal surfaces.
    static func nalUnits(_ data: Data) -> [Data] {
        let bytes = [UInt8](data)
        var starts: [(Int, Int)] = []
        var i = 0
        while i + 2 < bytes.count {
            if bytes[i] == 0 && bytes[i + 1] == 0 {
                if bytes[i + 2] == 1 { starts.append((i, i + 3)); i += 3; continue }
                if i + 3 < bytes.count && bytes[i + 2] == 0 && bytes[i + 3] == 1 {
                    starts.append((i, i + 4)); i += 4; continue
                }
            }
            i += 1
        }
        return starts.enumerated().compactMap { index, start in
            let end = index + 1 < starts.count ? starts[index + 1].0 : bytes.count
            return end > start.1 ? Data(bytes[start.1..<end]) : nil
        }
    }
    static func lengthPrefixed(_ units: [Data]) -> Data {
        var result = Data()
        for unit in units {
            var length = UInt32(unit.count).bigEndian
            withUnsafeBytes(of: &length) { result.append(contentsOf: $0) }
            result.append(unit)
        }
        return result
    }
    static func samplePayload(_ units: [Data]) -> Data {
        guard units.contains(where: { unit in
            guard let first = unit.first else { return false }
            return (1...5).contains(Int(first & 31))
        }) else { return Data() }
        // SPS/PPS are provided through the format description. Preserve SEI,
        // AUD and other accompanying NALs instead of silently discarding them.
        return lengthPrefixed(units.filter { unit in
            guard let first = unit.first else { return false }
            return first & 31 != 7 && first & 31 != 8
        })
    }
}

struct H264RecoveryState {
    private(set) var needsIDR = false
    private var latestIDRUnit = 0
    mutating func failed(unit: Int?) {
        if unit == nil || unit! >= latestIDRUnit { needsIDR = true }
    }
    mutating func submittedIDR(unit: Int) { latestIDRUnit = unit; needsIDR = false }
}

final class HardwareH264Factory: NSObject, RTCVideoDecoderFactory {
    private let output: LiveVideo
    init(output: LiveVideo) { self.output = output }
    func supportedCodecs() -> [RTCVideoCodecInfo] { RTCVideoDecoderH264.supportedCodecs() }
    func createDecoder(_ info: RTCVideoCodecInfo) -> (any RTCVideoDecoder)? {
        info.name == "H264" ? HardwareH264Decoder(output: output) : nil
    }
}

// WebRTC serializes decode/release operations. The callback lock is independent
// so waiting for outstanding VT callbacks during release cannot deadlock.
final class HardwareH264Decoder: NSObject, RTCVideoDecoder, @unchecked Sendable {
    private let output: LiveVideo
    private let callbackLock = NSLock()
    private var callback: RTCVideoDecoderCallback?
    private var recovery = H264RecoveryState() // Protected by callbackLock.
    private var session: VTDecompressionSession?
    private var format: CMVideoFormatDescription?
    private var sps: Data?
    private var pps: Data?
    init(output: LiveVideo) { self.output = output }
    func setCallback(_ callback: @escaping RTCVideoDecoderCallback) { callbackLock.withLock { self.callback = callback } }
    func startDecode(withNumberOfCores numberOfCores: Int32) -> Int { 0 }
    func implementationName() -> String { "XFrame VideoToolbox Hardware H264" }
    // Shared by synchronous and asynchronous decode failures; tested without
    // relying on nondeterministic network packet loss.
    func handleDecodeFailure(_ status: OSStatus, synchronous: Bool = false, keyframe: Bool = false, unit: Int? = nil) {
        if status == noErr { return } // VideoToolbox may intentionally drop a frame.
        if status == kVTVideoDecoderBadDataErr {
            callbackLock.withLock { recovery.failed(unit: unit) }
            output.recoverableDecodeError(synchronous: synchronous, keyframe: keyframe, unit: unit); return
        }
        output.fail("Hardware H.264 decoding failed (\(status)).")
    }
    func release() -> Int {
        if let session {
            VTDecompressionSessionWaitForAsynchronousFrames(session)
            VTDecompressionSessionInvalidate(session)
        }
        session = nil; format = nil; sps = nil; pps = nil
        callbackLock.withLock { recovery = H264RecoveryState() }
        return 0
    }
    func waitForPendingFrames() {
        if let session { VTDecompressionSessionWaitForAsynchronousFrames(session) }
    }
    func decode(_ encodedImage: RTCEncodedImage, missingFrames: Bool,
                codecSpecificInfo info: (any RTCCodecSpecificInfo)?, renderTimeMs: Int64) -> Int {
        output.frameTrace.note(.decoderInput, rtp: encodedImage.timeStamp)
        let units = H264AccessUnit.nalUnits(encodedImage.buffer)
        guard !units.isEmpty else { return -1 }
        let keyframe = units.contains { ($0.first! & 31) == 5 }
        let nextSPS = units.first { ($0.first! & 31) == 7 } ?? sps
        let nextPPS = units.first { ($0.first! & 31) == 8 } ?? pps
        guard let nextSPS, let nextPPS else { return -1 }
        do {
            if session == nil || nextSPS != sps || nextPPS != pps {
                let nextFormat = try makeFormat(sps: nextSPS, pps: nextPPS)
                if let session, VTDecompressionSessionCanAcceptFormatDescription(session, formatDescription: nextFormat) {
                    // Compatible SPS/PPS changes must not discard reference pictures.
                    format = nextFormat
                    output.connectionEvent(.decoderFormatUpdated)
                } else {
                    _ = release()
                    try configure(format: nextFormat)
                    // A new VT session has no references. Request an IDR before
                    // submitting dependent pictures, including initial delta input.
                    if !keyframe {
                        callbackLock.withLock { recovery.failed(unit: nil) }
                        output.requestKeyframe()
                    }
                }
                sps = nextSPS; pps = nextPPS
            }
            guard let session, let format else { return -1 }
            let payload = H264AccessUnit.samplePayload(units)
            guard !payload.isEmpty else { return 0 }
            // Continue accepting SPS/PPS while recovering, but do not submit
            // dependent pictures until a new IDR rebuilds the reference chain.
            if !keyframe && callbackLock.withLock({ recovery.needsIDR }) {
                output.skippedForRecovery()
                return 0
            }
            var block: CMBlockBuffer?
            guard CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: payload.count,
                blockAllocator: nil, customBlockSource: nil, offsetToData: 0, dataLength: payload.count,
                flags: 0, blockBufferOut: &block) == noErr, let block else { return -1 }
            let copyStatus = payload.withUnsafeBytes {
                CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: payload.count)
            }
            guard copyStatus == noErr else { return -1 }
            var sample: CMSampleBuffer?
            var size = payload.count
            var timing = CMSampleTimingInfo(duration: .invalid,
                presentationTimeStamp: CMTime(value: renderTimeMs, timescale: 1000), decodeTimeStamp: .invalid)
            guard CMSampleBufferCreateReady(allocator: nil, dataBuffer: block, formatDescription: format,
                sampleCount: 1, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
                sampleSizeEntryCount: 1, sampleSizeArray: &size, sampleBufferOut: &sample) == noErr, let sample else { return -1 }
            let stamp = encodedImage.timeStamp
            let rotation = encodedImage.rotation
            let unit = output.submittedAccessUnit(keyframe: keyframe, missingFrames: missingFrames)
            if keyframe { callbackLock.withLock { recovery.submittedIDR(unit: unit) } }
            let submittedAt = CACurrentMediaTime()
            let result = VTDecompressionSessionDecodeFrame(session, sampleBuffer: sample,
                flags: [._EnableAsynchronousDecompression], infoFlagsOut: nil) { [self] status, _, buffer, _, _ in
                guard status == noErr, let buffer else {
                    handleDecodeFailure(status, keyframe: keyframe, unit: unit); return
                }
                output.frameTrace.note(.decoded, rtp: stamp)
                let frame = RTCVideoFrame(buffer: RTCCVPixelBuffer(pixelBuffer: buffer), rotation: rotation,
                                          timeStampNs: renderTimeMs * 1_000_000)
                frame.timeStamp = Int32(bitPattern: stamp)
                output.performance.record(.decode, seconds: CACurrentMediaTime() - submittedAt)
                let callback = callbackLock.withLock { self.callback }
                callback?(frame)
            }
            if result != noErr { handleDecodeFailure(result, synchronous: true, keyframe: keyframe, unit: unit) }
            return result == noErr ? 0 : -1
        } catch {
            output.fail("Hardware H.264 decoder initialization failed.")
            return -1
        }
    }

    private func makeFormat(sps: Data, pps: Data) throws -> CMVideoFormatDescription {
        var format: CMVideoFormatDescription?
        let status = sps.withUnsafeBytes { s in pps.withUnsafeBytes { p in
            let pointers = [s.baseAddress!.assumingMemoryBound(to: UInt8.self), p.baseAddress!.assumingMemoryBound(to: UInt8.self)]
            let sizes = [sps.count, pps.count]
            return CMVideoFormatDescriptionCreateFromH264ParameterSets(allocator: nil, parameterSetCount: 2,
                parameterSetPointers: pointers, parameterSetSizes: sizes, nalUnitHeaderLength: 4,
                formatDescriptionOut: &format)
        } }
        guard status == noErr, let format else { throw CloudError.response }
        return format
    }

    private func configure(format: CMVideoFormatDescription) throws {
        self.format = format
        let decoder = [kVTVideoDecoderSpecification_RequireHardwareAcceleratedVideoDecoder: true] as CFDictionary
        let attributes: [CFString: Any] = [kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelBufferMetalCompatibilityKey: true, kCVPixelBufferIOSurfacePropertiesKey: [:] as [String: Any]]
        guard VTDecompressionSessionCreate(allocator: nil, formatDescription: format, decoderSpecification: decoder,
            imageBufferAttributes: attributes as CFDictionary, outputCallback: nil, decompressionSessionOut: &session) == noErr,
            let session else { throw CloudError.response }
        var hardware: Unmanaged<CFTypeRef>?
        guard VTSessionCopyProperty(session, key: kVTDecompressionPropertyKey_UsingHardwareAcceleratedVideoDecoder,
            allocator: nil, valueOut: &hardware) == noErr,
            (hardware?.takeRetainedValue() as? Bool) == true else { throw CloudError.response }
        output.hardwareVerified()
        output.decoderConfigured()
    }
}
