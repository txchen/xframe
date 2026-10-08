import Foundation

// One collection in flight, one delivery, then sleep. No catch-up queue. A slow
// consumer drops refresh opportunities, never applies backpressure to video.
@MainActor
final class HUDSampler {
    private var task: Task<Void, Never>?
    private var generation = 0

    func start(collect: @escaping @Sendable () -> HUDDocument,
               deliver: @escaping @MainActor (HUDDocument) -> Void) {
        stop()
        let generation = generation
        task = Task { [weak self] in
            while !Task.isCancelled {
                let worker = Task.detached(priority: .utility) { collect() }
                let document = await worker.value
                guard !Task.isCancelled, self?.generation == generation else { return }
                deliver(document)
                do { try await Task.sleep(for: .milliseconds(500)) }
                catch { return }
            }
        }
    }

    func stop() {
        generation += 1
        task?.cancel()
        task = nil
    }

    deinit { task?.cancel() }
}
