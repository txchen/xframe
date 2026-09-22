import Foundation
import QuartzCore
@preconcurrency import WebRTC

protocol VideoSource: AnyObject, Sendable {
    var performance: PlaybackPerformance { get }
    func stop()
    func snapshot() -> PlaybackStats
    func nextFrame(at hostTime: Double) -> VideoFrame?
    func didPresent()
    func didSkipFrame()
    func didMissPresentation()
    func fail(_ message: String)
}

// The network decoder owns reordering. Keep a bounded two-frame FIFO to absorb
// delivery jitter across display ticks; discard old frames after a render stall.
final class LiveVideo: NSObject, VideoSource, RTCVideoRenderer, @unchecked Sendable {
    let performance = PlaybackPerformance()
    private let lock = NSLock()
    static let displayCapacity = FramePacingMode.balanced.capacity
    static let maximumFrameAge = 0.050
    static let catchUpAge = 1.5 / 60.0
    private var frames: [VideoFrame] = []
    private var stats = PlaybackStats()
    private var bitrateMeter = VideoBitrateMeter()
    private var latencyMeter = VideoLatencyMeter()
    private var bitrateSampleAt: Double?
    private var stopped = false
    private var failed = false
    private var endedAt: Double?
    private var started: Double?
    private var lastFrameAt: Double?
    private var needsKeyframe = false
    private let createdAt = CACurrentMediaTime()
    private var submittedUnits = 0
    private var events: [StreamDiagnosticEvent] = []
    static let eventLimit = 128

    // Call only with lock held. Memory use stays bounded even on a broken stream.
    private func record(_ kind: StreamDiagnosticEvent.Kind, unit: Int? = nil,
                        synchronous: Bool? = nil, keyframe: Bool? = nil) {
        events.append(StreamDiagnosticEvent(milliseconds: Int((CACurrentMediaTime() - createdAt) * 1000),
            kind: kind, configuration: stats.decoderConfigurations, accessUnit: unit,
            synchronous: synchronous, keyframe: keyframe,
            packetsLost: stats.videoPacketsLost, nacks: stats.videoNacks))
        if events.count > Self.eventLimit { events.removeFirst(events.count - Self.eventLimit) }
    }
    func diagnosticEvents() -> [StreamDiagnosticEvent] { lock.withLock { events } }
    func diagnosticsText() -> String { diagnosticEvents().map(\.line).joined(separator: "\n") }
    func diagnosticReport() -> StreamDiagnosticReport {
        lock.withLock {
            var snapshot = stats
            if bitrateSampleAt.map({ (endedAt ?? CACurrentMediaTime()) - $0 > 3 }) ?? true {
                snapshot.videoBitrateMbps = nil
                snapshot.networkRoundTripMS = nil
                snapshot.jitterBufferMS = nil
            }
            snapshot.timings = performance.snapshot()
            snapshot.queued = frames.count
            return StreamDiagnosticReport(stats: snapshot,
                outcome: failed ? .failed : (stopped ? .stopped : .active),
                duration: (endedAt ?? CACurrentMediaTime()) - createdAt, events: events)
        }
    }

    init(framePacing: FramePacingMode = .balanced) {
        super.init()
        stats.state = "Connecting cloud video"
        stats.capacity = framePacing.capacity
        stats.framePacing = framePacing
        stats.isLive = true
    }
    func setSize(_ size: CGSize) {}
    func renderFrame(_ frame: RTCVideoFrame?) {
        guard let frame else { return }
        guard frame.rotation == ._0, let native = frame.buffer as? RTCCVPixelBuffer else {
            fail("The stream did not produce an unrotated native video surface."); return
        }
        lock.withLock {
            guard !stopped else { return }
            let now = CACurrentMediaTime()
            if started == nil { started = now; record(.firstFrame) }
            lastFrameAt = now
            performance.note(.arrival, at: now)
            stats.decoded += 1
            stats.state = "Cloud video \(frame.width)×\(frame.height) · H.264"
            if frames.count == stats.capacity {
                frames.removeFirst()
                stats.dropped += 1
                performance.note(.inboxReplaced, at: now)
            }
            frames.append(VideoFrame(buffer: native.pixelBuffer, time: Double(frame.timeStampNs) / 1e9, id: stats.decoded))
            stats.peakQueue = max(stats.peakQueue, frames.count)
        }
    }
    func hardwareVerified() { lock.withLock { if !stopped { stats.hardware = true } } }
    func audioPlayback(attached: Bool, muted: Bool, volume: Double) {
        lock.withLock {
            guard !stopped else { return }
            stats.audioAttached = attached; stats.audioMuted = muted; stats.audioVolume = volume
        }
    }
    func audioNetworkSample(received: Int?, energy: Double?) {
        lock.withLock {
            guard !stopped else { return }
            stats.audioPacketsReceived = received
            stats.audioEnergy = energy.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        }
    }
    func skippedForRecovery() { lock.withLock { if !stopped { stats.recoverySkippedFrames += 1 } } }
    func decoderConfigured() {
        lock.withLock { guard !stopped else { return }; stats.decoderConfigurations += 1; record(.configured) }
    }
    func networkSample(received: Int?, lost: Int?, nacks: Int?,
                       bytes: Double? = nil, timestampUS: Double? = nil, streamID: String? = nil,
                       roundTripSeconds: Double? = nil, jitterBufferDelay: Double? = nil,
                       jitterBufferEmittedCount: Double? = nil) {
        lock.withLock {
            guard !stopped else { return }
            stats.videoBitrateMbps = bitrateMeter.sample(bytes: bytes, timestampUS: timestampUS, streamID: streamID)
            stats.networkRoundTripMS = roundTripSeconds.flatMap {
                $0.isFinite && $0 >= 0 && ($0 * 1000).isFinite ? $0 * 1000 : nil
            }
            stats.jitterBufferMS = latencyMeter.sample(id: streamID, timestampUS: timestampUS,
                delay: jitterBufferDelay, count: jitterBufferEmittedCount)
            bitrateSampleAt = CACurrentMediaTime()
            let changed = lost != stats.videoPacketsLost || nacks != stats.videoNacks
            stats.videoPacketsReceived = received
            stats.videoPacketsLost = lost
            stats.videoNacks = nacks
            if changed { record(.networkChange) }
        }
    }
    @discardableResult func submittedAccessUnit(keyframe: Bool, missingFrames: Bool) -> Int {
        lock.withLock {
            guard !stopped else { return 0 }
            submittedUnits += 1
            if keyframe { stats.keyframeSubmissions += 1 }
            if missingFrames { stats.missingFrameSignals += 1 }
            if keyframe { record(.idrSubmitted, unit: submittedUnits) }
            return submittedUnits
        }
    }
    func recoverableDecodeError(synchronous: Bool = false, keyframe: Bool = false, unit: Int? = nil) {
        lock.withLock {
            if !stopped {
                stats.decodeErrors += 1
                if synchronous { stats.synchronousDecodeErrors += 1 }
                else { stats.asynchronousDecodeErrors += 1 }
                if keyframe { stats.keyframeDecodeErrors += 1 }
                if stats.decoded == 0 { stats.errorsBeforeFirstFrame += 1 }
                needsKeyframe = true
                record(.badData, unit: unit, synchronous: synchronous, keyframe: keyframe)
            }
        }
    }
    func takeKeyframeRequest() -> Bool {
        lock.withLock {
            guard !stopped else { return false }
            let value = needsKeyframe; needsKeyframe = false
            if value { record(.keyframeRequestDequeued) }
            return value
        }
    }
    func stop() {
        performance.stop()
        lock.withLock {
            if !stopped { record(.stopped) }
            if endedAt == nil { endedAt = CACurrentMediaTime() }
            stopped = true; frames.removeAll()
            stats.state = "Stopped"
        }
    }
    func fail(_ message: String) {
        performance.stop()
        lock.withLock {
            guard !stopped else { return }
            failed = true; endedAt = CACurrentMediaTime()
            stopped = true; frames.removeAll()
            stats.state = "Failed: " + message
        }
    }
    func nextFrame(at hostTime: Double) -> VideoFrame? {
        lock.withLock {
            guard !stopped else { return nil }
            while let first = frames.first, hostTime - first.arrivedAt > Self.maximumFrameAge {
                frames.removeFirst()
                stats.dropped += 1
                performance.note(.inboxReplaced, at: hostTime)
            }
            // Preserve arrival/VSync jitter around a full frame interval. Retire
            // an older head only after 1.5 intervals when a fresher frame is ready;
            // a one-interval cutoff caused avoidable skips in live 60 Hz tests.
            // A lone frame still uses the 50 ms stall bound.
            while frames.count > 1, let first = frames.first, hostTime - first.arrivedAt > Self.catchUpAge {
                frames.removeFirst()
                stats.dropped += 1
                performance.note(.inboxReplaced, at: hostTime)
            }
            return frames.isEmpty ? nil : frames.removeFirst()
        }
    }
    func didMissPresentation() { lock.withLock { if !stopped { stats.dropped += 1; performance.note(.notPresented) } } }
    func didPresent() { lock.withLock { if !stopped { stats.presented += 1 } } }
    func didSkipFrame() { lock.withLock { if !stopped { stats.dropped += 1; performance.note(.rendererReplaced) } } }
    var streamState: (state: String, hasFrames: Bool) {
        lock.withLock { (stats.state, stats.decoded > 0) }
    }
    func snapshot() -> PlaybackStats {
        lock.withLock {
            var result = stats
            result.timings = performance.snapshot()
            result.queued = frames.count
            if !stopped, bitrateSampleAt.map({ CACurrentMediaTime() - $0 > 3 }) ?? true {
                result.videoBitrateMbps = nil
                result.networkRoundTripMS = nil
                result.jitterBufferMS = nil
            }
            result.elapsed = started.map { (endedAt ?? CACurrentMediaTime()) - $0 } ?? 0
            return result
        }
    }
    var secondsSinceFrame: Double? { lock.withLock { lastFrameAt.map { CACurrentMediaTime() - $0 } } }
}
