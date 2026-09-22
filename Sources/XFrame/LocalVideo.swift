import AVFoundation
import VideoToolbox
import QuartzCore

// Immutable after construction; CoreVideo owns the retained decode surface.
struct VideoFrame: @unchecked Sendable {
    let buffer: CVPixelBuffer
    let time: Double
    let id: Int
    var sourceRTP: UInt32? = nil
    let arrivedAt = CACurrentMediaTime()
}

struct PlaybackStats: Sendable {
    var isLive = false
    var connectionRecovering = false
    var framePacing: FramePacingMode = .balanced
    var pipelineLatencyEstimateMS: Double? {
        let parts = [networkRoundTripMS, jitterBufferMS, timings.decode?.meanMS, timings.presentation?.meanMS]
        guard parts.allSatisfy({ $0.map { $0.isFinite && $0 >= 0 } ?? false }) else { return nil }
        let value = parts.compactMap { $0 }.reduce(0, +)
        return value.isFinite ? value : nil
    }
    var timings = PlaybackTimingSnapshot()
    var capacity = 16
    var decodeErrors = 0
    var recoverySkippedFrames = 0
    var errorsBeforeFirstFrame = 0
    var keyframeSubmissions = 0
    var missingFrameSignals = 0
    var decoderConfigurations = 0
    var synchronousDecodeErrors = 0
    var asynchronousDecodeErrors = 0
    var keyframeDecodeErrors = 0
    var networkRoundTripMS: Double?
    var jitterBufferMS: Double?
    var videoBitrateMbps: Double?
    var videoPacketsReceived: Int?
    var videoPacketsLost: Int?
    var videoNacks: Int?
    var audioAttached = false
    var audioMuted = false
    var audioVolume = 1.0
    var audioPacketsReceived: Int?
    var audioEnergy: Double?
    var state = "Loading"
    var hardware = false
    var decoded = 0
    var presented = 0
    var dropped = 0
    var queued = 0
    var peakQueue = 0
    var recentDecodedFPS: Double?
    var recentPresentedFPS: Double?
    var elapsed = 0.0
    var inputFinished = false
}

// All mutable fields are protected by condition. The reader and VT session are
// confined to the worker. Cancellation wakes a producer blocked by backpressure.
final class LocalVideo: VideoSource, @unchecked Sendable {
    let performance = PlaybackPerformance()
    static let capacity = 16
    private let condition = NSCondition()
    private var frames: [VideoFrame] = []
    private var stats = PlaybackStats()
    private var stopped = false
    private var finished = false
    private var ready = false
    private var anchor: Double?
    private var firstPTS = 0.0
    private var schedulingLead = 0.0
    private var decodedThrough = -Double.infinity
    private var lastPTS = -Double.infinity
    private var endTime = 0.0

    init(url: URL) {
        Task.detached(priority: .userInitiated) { [self] in
            do { try await decode(url: url) }
            catch { fail(error.localizedDescription) }
        }
    }

    func stop() {
        performance.stop()
        condition.lock()
        stopped = true
        stats.state = "Stopped"
        frames.removeAll()
        condition.broadcast()
        condition.unlock()
    }

    func snapshot() -> PlaybackStats {
        condition.lock(); defer { condition.unlock() }
        var result = stats
        result.timings = performance.snapshot()
        result.queued = frames.count
        result.inputFinished = finished
        if let anchor { result.elapsed = max(0, (endTime > 0 ? endTime : CACurrentMediaTime()) - anchor) }
        return result
    }

    func nextFrame(at hostTime: Double) -> VideoFrame? {
        condition.lock(); defer { condition.unlock() }
        guard !stopped, ready else { return nil }
        if anchor == nil, let first = frames.first {
            anchor = hostTime
            firstPTS = first.time
            if frames.count > 1 {
                // Center selection around the source cadence. Without this,
                // tiny display callback jitter alternates repeats and skips.
                schedulingLead = min(1.0 / 60.0, max(0, frames[1].time - first.time) / 2)
            }
            stats.state = "Playing"
        }
        guard let anchor else {
            if finished { stats.state = "Ended" }
            return nil
        }
        let due = firstPTS + hostTime - anchor + schedulingLead
        var selected: VideoFrame?
        // DTS is a safe reordering watermark: later compressed samples cannot
        // present before their decode time. Preserve future reference frames
        // even when a long display stall makes the whole queue look overdue.
        while let first = frames.first, first.time <= due,
              finished || first.time <= decodedThrough + 0.000001 {
            let candidate = frames.removeFirst()
            if selected != nil { stats.dropped += 1 }
            selected = candidate
        }
        if let selected {
            if selected.time < lastPTS {
                stats.state = "Failed: unsupported presentation timestamp order"
                stopped = true
            }
            lastPTS = selected.time
        }
        if finished && frames.isEmpty && selected == nil {
            stats.state = "Ended"
            if endTime == 0 { endTime = hostTime }
        }
        condition.broadcast()
        return stopped ? nil : selected
    }

    func didPresent() {
        condition.lock(); defer { condition.unlock() }
        guard !stopped else { return }
        stats.presented += 1
    }
    func didMissPresentation() {
        condition.lock(); defer { condition.unlock() }
        if !stopped { stats.dropped += 1; performance.note(.notPresented) }
    }
    func didSkipFrame() {
        condition.lock(); defer { condition.unlock() }
        if !stopped { stats.dropped += 1 }
    }

    func fail(_ message: String) {
        performance.stop()
        condition.lock(); defer { condition.unlock() }
        if stopped { return }
        stats.state = "Failed: \(message)"
        stopped = true
        frames.removeAll()
        condition.broadcast()
    }

    private func waitForRoom() -> Bool {
        condition.lock(); defer { condition.unlock() }
        while frames.count >= Self.capacity && !stopped { condition.wait() }
        return !stopped
    }

    private func receive(status: OSStatus, buffer: CVPixelBuffer?, time: CMTime) {
        guard status == noErr, let buffer, time.isNumeric else {
            fail("VideoToolbox output failed (\(status)).")
            return
        }
        condition.lock(); defer { condition.unlock() }
        guard !stopped else { return }
        stats.decoded += 1
        frames.append(VideoFrame(buffer: buffer, time: time.seconds, id: stats.decoded))
        frames.sort { $0.time < $1.time }
        stats.peakQueue = max(stats.peakQueue, frames.count)
        if frames.count == Self.capacity { ready = true }
    }

    private func decode(url: URL) async throws {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw RenderError.unavailable("No video track was found.")
        }
        let descriptions = try await track.load(.formatDescriptions)
        let transform = try await track.load(.preferredTransform)
        guard transform == .identity else {
            throw RenderError.unavailable("Rotated video is not supported yet. Use an unrotated H.264 file.")
        }
        guard let format = descriptions.first, CMFormatDescriptionGetMediaSubType(format) == kCMVideoCodecType_H264 else {
            throw RenderError.unavailable("This increment supports H.264 video only.")
        }
        let dimensions = CMVideoFormatDescriptionGetDimensions(format)
        let display = CMVideoFormatDescriptionGetPresentationDimensions(format, usePixelAspectRatio: true, useCleanAperture: true)
        guard display.width == Double(dimensions.width), display.height == Double(dimensions.height) else {
            throw RenderError.unavailable("Use square-pixel video without a cropped clean aperture.")
        }
        let transfer = CMFormatDescriptionGetExtension(format, extensionKey: kCMFormatDescriptionExtension_TransferFunction) as? String
        guard transfer != kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ as String,
              transfer != kCVImageBufferTransferFunction_ITU_R_2100_HLG as String else {
            throw RenderError.unavailable("HDR video is not supported in this SDR increment.")
        }
        var session: VTDecompressionSession?
        let decoder: [CFString: Any] = [kVTVideoDecoderSpecification_RequireHardwareAcceleratedVideoDecoder: true]
        let attributes: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelBufferMetalCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as [String: Any]
        ]
        let status = VTDecompressionSessionCreate(allocator: nil, formatDescription: format,
            decoderSpecification: decoder as CFDictionary, imageBufferAttributes: attributes as CFDictionary,
            outputCallback: nil, decompressionSessionOut: &session)
        guard status == noErr, let session else {
            throw RenderError.unavailable("Hardware H.264 decoder creation failed (\(status)).")
        }
        defer { VTDecompressionSessionInvalidate(session) }
        var hardware: Unmanaged<CFTypeRef>?
        let query = VTSessionCopyProperty(session, key: kVTDecompressionPropertyKey_UsingHardwareAcceleratedVideoDecoder,
                                         allocator: nil, valueOut: &hardware)
        let usesHardware = hardware?.takeRetainedValue() as? Bool
        guard query == noErr, usesHardware == true else {
            throw RenderError.unavailable("VideoToolbox did not confirm hardware decoding.")
        }
        setHardwareVerified()
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        guard reader.canAdd(output) else { throw RenderError.unavailable("Cannot read this video track.") }
        let provider = reader.outputProvider(for: output)
        try reader.start()
        defer { reader.cancelReading() }
        while waitForRoom(), let readySample = try await provider.next() {
            try readySample.withUnsafeSampleBuffer { sample in
                // The reader may emit zero-sample timeline markers before media.
                guard CMSampleBufferGetNumSamples(sample) > 0 else { return }
                guard let sampleFormat = CMSampleBufferGetFormatDescription(sample),
                      VTDecompressionSessionCanAcceptFormatDescription(session, formatDescription: sampleFormat),
                      CMVideoFormatDescriptionGetDimensions(sampleFormat).width == dimensions.width,
                      CMVideoFormatDescriptionGetDimensions(sampleFormat).height == dimensions.height else {
                    throw RenderError.unavailable("Mid-file format changes are not supported yet.")
                }
                let dts = CMSampleBufferGetDecodeTimeStamp(sample)
                let pts = CMSampleBufferGetPresentationTimeStamp(sample)
                // CoreMedia permits invalid DTS for samples already in display order.
                let decodeTime = dts.isNumeric ? dts : pts
                guard decodeTime.isNumeric, pts.isNumeric, pts >= decodeTime else {
                    throw RenderError.unavailable("Unsupported video timestamps: presentation must not precede decoding.")
                }
                // With both flags clear, the callback completes before this returns.
                let submittedAt = CACurrentMediaTime()
                let result = VTDecompressionSessionDecodeFrame(session, sampleBuffer: sample, flags: [], infoFlagsOut: nil) {
                    [self] status, _, buffer, pts, _ in
                    if status == noErr, buffer != nil { performance.record(.decode, seconds: CACurrentMediaTime() - submittedAt) }
                    receive(status: status, buffer: buffer, time: pts)
                }
                guard result == noErr else { throw RenderError.unavailable("H.264 decode failed (\(result)).") }
                updateWatermark(decodeTime.seconds)
            }
        }
        if reader.status == .failed { throw reader.error ?? RenderError.unavailable("Reading the video failed.") }
        markFinished()
    }

    private func setHardwareVerified() {
        condition.lock(); defer { condition.unlock() }
        stats.hardware = true
    }

    private func updateWatermark(_ time: Double) {
        condition.lock(); defer { condition.unlock() }
        decodedThrough = max(decodedThrough, time)
    }

    private func markFinished() {
        condition.lock(); defer { condition.unlock() }
        guard !stopped else { return }
        finished = true
        ready = true
    }
}
