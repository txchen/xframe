import Foundation

// Joins callbacks for the same frame, regardless of GPU/presentation callback order.
// Only numeric timings are retained; no per-frame logs or observable UI updates.
final class FramePresentation: @unchecked Sendable {
    private let lock = NSLock()
    private let source: any VideoSource
    private let arrivedAt, submittedAt: Double
    private let sourceRTP: UInt32?
    private let frameID: Int?
    private var gpuEnd: Double?
    private var displayedAt: Double?
    private var gpuReported = false
    private var presentationReported = false
    private var displayWaitReported = false

    init(source: any VideoSource, arrivedAt: Double, submittedAt: Double, sourceRTP: UInt32? = nil, frameID: Int? = nil) {
        self.sourceRTP = sourceRTP
        self.frameID = frameID
        self.source = source
        self.arrivedAt = arrivedAt
        self.submittedAt = submittedAt
        source.performance.record(.frameWait, seconds: submittedAt - arrivedAt)
    }

    func gpuCompleted(start: Double, end: Double) {
        lock.withLock {
            guard !gpuReported else { return }
            gpuReported = true
            guard start.isFinite, end.isFinite, start >= submittedAt, end >= start else { return }
            gpuEnd = end
            source.performance.record(.gpuQueue, seconds: start - submittedAt)
            source.performance.record(.gpu, seconds: end - start)
            recordDisplayWait()
        }
    }

    func presented(at time: Double) {
        lock.withLock {
            guard !presentationReported else { return }
            presentationReported = true
            // Apple reports zero when the drawable was not displayed.
            guard time.isFinite, time > 0, time >= submittedAt, time >= arrivedAt else {
                source.didMissPresentation()
                return
            }
            displayedAt = time
            source.didPresent()
            if let live = source as? LiveVideo, let sourceRTP {
                live.frameTrace.note(.presented, rtp: sourceRTP, frameID: frameID, at: time)
            }
            source.performance.record(.presentation, seconds: time - arrivedAt)
            recordDisplayWait()
        }
    }

    private func recordDisplayWait() {
        guard !displayWaitReported, let gpuEnd, let displayedAt, displayedAt >= gpuEnd else { return }
        displayWaitReported = true
        source.performance.record(.displayWait, seconds: displayedAt - gpuEnd)
    }
}
