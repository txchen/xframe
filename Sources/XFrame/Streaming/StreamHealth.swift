import Foundation

// Monotonic seconds are supplied by the connection, allowing exact boundary tests.
struct StreamHealth {
    enum Transport { case connecting, connected, disconnected, failed }
    enum Action: Equatable { case waiting, playing, recovering, firstFrameTimeout, stalled, transportFailed }
    private(set) var disconnectedAt: Double?
    private(set) var transport: Transport = .connecting
    private var nextKeyframeAt = 0.0

    mutating func updateTransport(_ state: Transport, now: Double) {
        transport = state
        if state == .disconnected {
            if disconnectedAt == nil { disconnectedAt = now }
        } else if state == .connected { disconnectedAt = nil }
    }

    func action(now: Double, startedAt: Double, frameAge: Double?, inputBlockedAt: Double? = nil) -> Action {
        if transport == .failed { return .transportFailed }
        if let inputBlockedAt, now - inputBlockedAt >= 15 { return .transportFailed }
        if let disconnectedAt, now - disconnectedAt >= 15 { return .transportFailed }
        if let frameAge {
            if frameAge >= 15 { return .stalled }
            if disconnectedAt != nil || inputBlockedAt != nil || frameAge >= 2 { return .recovering }
            return .playing
        }
        if now - startedAt >= 45 { return .firstFrameTimeout }
        return disconnectedAt == nil ? .waiting : .recovering
    }

    mutating func shouldRequestKeyframe(now: Double, recovering: Bool, decoderRequested: Bool) -> Bool {
        guard (recovering || decoderRequested), now >= nextKeyframeAt else { return false }
        nextKeyframeAt = now + 1
        return true
    }
}

// Heartbeats run independently so an HTTP request cannot suspend the media watchdog.
@MainActor
final class StreamHeartbeat {
    private(set) var failure: (any Error)?
    private var task: Task<Void, Never>?
    func start(interval: Double, pulse: @escaping @Sendable () async throws -> Void,
               sleep: @escaping @Sendable (Double) async throws -> Void = {
                   try await Task.sleep(for: .seconds($0))
               }, event: @escaping (StreamDiagnosticEvent.Kind) -> Void) {
        guard task == nil else { return }
        let interval = interval.isFinite ? min(60, max(1, interval)) : 20
        task = Task { [weak self] in
            var failures = 0
            while !Task.isCancelled {
                do {
                    try await pulse()
                    try Task.checkCancellation()
                    if failures > 0 { event(.heartbeatRecovered) }
                    failures = 0
                } catch {
                    guard !Task.isCancelled else { return }
                    failures += 1
                    guard Self.isTransient(error), failures < 5 else {
                        self?.failure = error
                        return
                    }
                    event(.heartbeatRetry)
                }
                do { try await sleep(failures == 0 ? interval : pow(2, Double(failures - 1))) }
                catch { return }
            }
        }
    }
    func stop() { task?.cancel(); task = nil }
    private static func isTransient(_ error: any Error) -> Bool {
        switch error {
        case CloudError.network: true
        case CloudError.http(let status): [408, 500, 502, 503, 504].contains(status)
        default: false
        }
    }
}
