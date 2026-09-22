import Foundation
import QuartzCore
@preconcurrency import WebRTC

protocol VideoSource: AnyObject, Sendable {
    func stop()
    func snapshot() -> PlaybackStats
    func nextFrame(at hostTime: Double) -> VideoFrame?
    func didPresent()
    func fail(_ message: String)
}

// The network decoder owns reordering. The display keeps only the newest frame,
// never an unbounded queue or a Task per decoded image.
final class LiveVideo: NSObject, VideoSource, RTCVideoRenderer, @unchecked Sendable {
    private let lock = NSLock()
    private var latest: VideoFrame?
    private var stats = PlaybackStats()
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
            snapshot.queued = latest == nil ? 0 : 1
            return StreamDiagnosticReport(stats: snapshot,
                outcome: failed ? .failed : (stopped ? .stopped : .active),
                duration: (endedAt ?? CACurrentMediaTime()) - createdAt, events: events)
        }
    }

    override init() {
        super.init()
        stats.state = "Connecting cloud video"
        stats.capacity = 1
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
            stats.decoded += 1
            stats.state = "Cloud video \(frame.width)×\(frame.height) · H.264"
            if latest != nil { stats.dropped += 1 }
            latest = VideoFrame(buffer: native.pixelBuffer, time: Double(frame.timeStampNs) / 1e9, id: stats.decoded)
            stats.peakQueue = 1
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
    func networkSample(received: Int?, lost: Int?, nacks: Int?) {
        lock.withLock {
            guard !stopped else { return }
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
        lock.withLock {
            if !stopped { record(.stopped) }
            if endedAt == nil { endedAt = CACurrentMediaTime() }
            stopped = true; latest = nil; stats.state = "Stopped"
        }
    }
    func fail(_ message: String) {
        lock.withLock {
            guard !stopped else { return }
            failed = true; endedAt = CACurrentMediaTime()
            stopped = true; latest = nil; stats.state = "Failed: " + message
        }
    }
    func nextFrame(at hostTime: Double) -> VideoFrame? {
        lock.withLock { let value = latest; latest = nil; return stopped ? nil : value }
    }
    func didPresent() { lock.withLock { if !stopped { stats.presented += 1 } } }
    func snapshot() -> PlaybackStats {
        lock.withLock {
            var result = stats
            result.queued = latest == nil ? 0 : 1
            result.elapsed = started.map { (endedAt ?? CACurrentMediaTime()) - $0 } ?? 0
            return result
        }
    }
    var secondsSinceFrame: Double? { lock.withLock { lastFrameAt.map { CACurrentMediaTime() - $0 } } }
}
