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
    private var started: Double?
    private var lastFrameAt: Double?
    private var needsKeyframe = false

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
            if started == nil { started = now }
            lastFrameAt = now
            stats.decoded += 1
            stats.state = "Cloud video \(frame.width)×\(frame.height) · H.264"
            if latest != nil { stats.dropped += 1 }
            latest = VideoFrame(buffer: native.pixelBuffer, time: Double(frame.timeStampNs) / 1e9, id: stats.decoded)
            stats.peakQueue = 1
        }
    }
    func hardwareVerified() { lock.withLock { stats.hardware = true } }
    func submittedAccessUnit(keyframe: Bool, missingFrames: Bool) {
        lock.withLock {
            guard !stopped else { return }
            if keyframe { stats.keyframeSubmissions += 1 }
            if missingFrames { stats.missingFrameSignals += 1 }
        }
    }
    func recoverableDecodeError() {
        lock.withLock {
            if !stopped {
                stats.decodeErrors += 1
                if stats.decoded == 0 { stats.errorsBeforeFirstFrame += 1 }
                needsKeyframe = true
            }
        }
    }
    func takeKeyframeRequest() -> Bool {
        lock.withLock { let value = needsKeyframe; needsKeyframe = false; return value }
    }
    func stop() { lock.withLock { stopped = true; latest = nil; stats.state = "Stopped" } }
    func fail(_ message: String) { lock.withLock { stopped = true; latest = nil; stats.state = "Failed: " + message } }
    func nextFrame(at hostTime: Double) -> VideoFrame? {
        lock.withLock { let value = latest; latest = nil; return stopped ? nil : value }
    }
    func didPresent() { lock.withLock { stats.presented += 1 } }
    func snapshot() -> PlaybackStats {
        lock.withLock {
            var result = stats
            result.queued = latest == nil ? 0 : 1
            result.elapsed = started.map { CACurrentMediaTime() - $0 } ?? 0
            return result
        }
    }
    var secondsSinceFrame: Double? { lock.withLock { lastFrameAt.map { CACurrentMediaTime() - $0 } } }
}
