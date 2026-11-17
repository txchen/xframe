import Foundation

// GPU completion does not release a drawable's place in the display pipeline.
// Track every mode so switching to Original also waits for older submissions.
final class PresentationQueue: @unchecked Sendable {
    private let lock = NSLock()
    private var pending = 0

    func reserve(enforcingLimit: Bool) -> Reservation? {
        lock.withLock {
            guard !enforcingLimit || pending < 2 else { return nil }
            pending += 1
            return Reservation(owner: self)
        }
    }

    private func release() { lock.withLock { pending -= 1 } }

    final class Reservation: @unchecked Sendable {
        private let lock = NSLock()
        private var owner: PresentationQueue?

        fileprivate init(owner: PresentationQueue) { self.owner = owner }

        func finish() {
            let owner = lock.withLock {
                let owner = self.owner
                self.owner = nil
                return owner
            }
            owner?.release()
        }

        deinit { finish() }
    }
}
