import Foundation
import Testing
@testable import XFrame

@Test func interruptionRecoversWithinBudgetAndRepeatedEventsDoNotExtendIt() {
    var health = StreamHealth()
    #expect(health.action(now: 44, startedAt: 0, frameAge: nil) == .waiting)
    #expect(health.action(now: 45, startedAt: 0, frameAge: nil) == .firstFrameTimeout)
    health.updateTransport(.connected, now: 1)
    #expect(health.action(now: 1, startedAt: 0, frameAge: 0) == .playing)
    health.updateTransport(.disconnected, now: 2)
    health.updateTransport(.disconnected, now: 10)
    #expect(health.action(now: 16.9, startedAt: 0, frameAge: 1) == .recovering)
    #expect(health.action(now: 17, startedAt: 0, frameAge: 1) == .transportFailed)
    health.updateTransport(.connected, now: 17)
    #expect(health.action(now: 17, startedAt: 0, frameAge: 2) == .recovering)
    #expect(health.action(now: 17, startedAt: 0, frameAge: 0) == .playing)
    health.updateTransport(.failed, now: 18)
    #expect(health.action(now: 18, startedAt: 0, frameAge: 0) == .transportFailed)
}

@Test func videoSilenceHasBoundedRecoveryAndKeyframeRate() {
    var health = StreamHealth()
    #expect(health.action(now: 5, startedAt: 0, frameAge: 1.99) == .playing)
    #expect(health.action(now: 5, startedAt: 0, frameAge: 2) == .recovering)
    #expect(health.action(now: 18, startedAt: 0, frameAge: 15) == .stalled)
    let request1 = health.shouldRequestKeyframe(now: 0, recovering: false, decoderRequested: false)
    #expect(!request1)
    let request2 = health.shouldRequestKeyframe(now: 0, recovering: false, decoderRequested: true)
    #expect(request2)
    for tick in 1..<100 {
        let request3 = health.shouldRequestKeyframe(now: Double(tick) / 100, recovering: true, decoderRequested: true)
        #expect(!request3)
    }
    let request4 = health.shouldRequestKeyframe(now: 1, recovering: true, decoderRequested: false)
    #expect(request4)
    let request5 = health.shouldRequestKeyframe(now: 2, recovering: false, decoderRequested: false)
    #expect(!request5)
}

@Test @MainActor func connectionRecordsTypedFailureBeforeClosing() async {
    let failures: [(StreamError, StreamDiagnosticEvent.Kind)] = [
        (.signaling, .startupFailed), (.connection, .transportFailed),
        (.firstFrame, .firstFrameTimeout), (.stalled, .videoStalled),
        (.heartbeat, .heartbeatFailed), (.decoder("test"), .decoderFailed)
    ]
    for (failure, kind) in failures {
        let connection = CloudVideoConnection()
        do { try await connection.withLifecycle { throw failure }; Issue.record("Expected failure") }
        catch {}
        connection.close()
        let report = connection.video.diagnosticReport()
        #expect(report.outcome == .failed)
        #expect(report.events.last?.kind == kind)
        #expect(report.video.decodeErrors == 0)
        #expect(connection.video.streamState.state.hasPrefix("Failed:"))
    }
}

@Test @MainActor func cancellationAndLateErrorsCannotTurnClosedSessionIntoFailure() async {
    let connection = CloudVideoConnection()
    do { try await connection.withLifecycle { throw CancellationError() }; Issue.record("Expected cancellation") }
    catch {}
    #expect(connection.video.diagnosticReport().outcome == .stopped)
    var ran = false
    do { try await connection.withLifecycle { ran = true }; Issue.record("Expected closed connection") }
    catch {}
    #expect(!ran)
    #expect(connection.video.diagnosticReport().outcome == .stopped)
}

private actor Pulses {
    var calls = 0
    let errors: [CloudError]
    init(_ errors: [CloudError]) { self.errors = errors }
    func pulse() throws {
        calls += 1
        if calls <= errors.count { throw errors[calls - 1] }
    }
}

@Test @MainActor func heartbeatRetriesTransientFailuresThenRecovers() async throws {
    let pulses = Pulses([.network, .http(503)])
    let heartbeat = StreamHeartbeat()
    var events: [StreamDiagnosticEvent.Kind] = []
    heartbeat.start(interval: 20, pulse: { try await pulses.pulse() }, sleep: { seconds in
        try await Task.sleep(for: seconds >= 20 ? .seconds(60) : .milliseconds(1))
    }, event: { events.append($0) })
    defer { heartbeat.stop() }
    try await waitUntil { events.contains(.heartbeatRecovered) }
    #expect(await pulses.calls == 3)
    #expect(events == [.heartbeatRetry, .heartbeatRetry, .heartbeatRecovered])
    #expect(heartbeat.failure == nil)
}

@Test @MainActor func heartbeatHasBoundedRetriesAndDoesNotRetryAuthorizationFailures() async throws {
    for errors: [CloudError] in [Array(repeating: .network, count: 5), [.http(401)], [.expired]] {
        let pulses = Pulses(errors)
        let heartbeat = StreamHeartbeat()
        heartbeat.start(interval: 20, pulse: { try await pulses.pulse() },
                        sleep: { _ in try await Task.sleep(for: .milliseconds(1)) }, event: { _ in })
        try await waitUntil { heartbeat.failure != nil }
        heartbeat.stop()
        #expect(await pulses.calls == errors.count)
    }
}

@Test @MainActor func stoppingHeartbeatCancelsAnInFlightRequest() async throws {
    let heartbeat = StreamHeartbeat()
    var began = false
    var cancelled = false
    heartbeat.start(interval: 20, pulse: { @MainActor in
        began = true
        do { try await Task.sleep(for: .seconds(60)) }
        catch { cancelled = true; throw error }
    }, event: { _ in Issue.record("Cancellation must not generate retries") })
    try await waitUntil { began }
    heartbeat.stop()
    try await waitUntil { cancelled }
    #expect(heartbeat.failure == nil)
}

@MainActor private func waitUntil(_ predicate: () -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(3))
    while !predicate() && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
    #expect(predicate())
}

@Test func recoveryStatusReachesBothVisibleHUDModesAndClearsAtStop() {
    let source = LiveVideo()
    source.setRecovering(true)
    for preset in [PerformanceHUDPreset.compact, .detailed] {
        #expect(PerformanceHUDText.render(source.snapshot(), preset: preset, controller: "").contains("recovering"))
    }
    source.setRecovering(false)
    #expect(!PerformanceHUDText.render(source.snapshot(), preset: .compact, controller: "").contains("recovering"))
    source.setRecovering(true)
    source.stop()
    source.setRecovering(true)
    #expect(!source.snapshot().connectionRecovering)
}

@Test func inputBackpressureUsesRecoveryBudgetInsteadOfTwoSecondTeardown() {
    var health = StreamHealth()
    health.updateTransport(.connected, now: 0)
    // ICE can still say connected while the unreliable input channel is blocked.
    #expect(health.action(now: 4, startedAt: 0, frameAge: 4, inputBlockedAt: 2) == .recovering)
    #expect(health.action(now: 7, startedAt: 0, frameAge: 0, inputBlockedAt: 2) == .recovering)
    #expect(health.action(now: 7, startedAt: 0, frameAge: 0, inputBlockedAt: nil) == .playing)
    #expect(health.action(now: 17, startedAt: 0, frameAge: 0, inputBlockedAt: 2) == .transportFailed)
}

private actor HeartbeatDelays {
    var values: [Double] = []
    func append(_ value: Double) { values.append(value) }
}

@Test @MainActor func heartbeatAllowsBriefOutageInsteadOfFailingAfterThreeSeconds() async throws {
    let pulses = Pulses([.network, .network, .network])
    let delays = HeartbeatDelays()
    let heartbeat = StreamHeartbeat()
    var recovered = false
    heartbeat.start(interval: 20, pulse: { try await pulses.pulse() }, sleep: { seconds in
        await delays.append(seconds)
        try await Task.sleep(for: seconds >= 20 ? .seconds(60) : .milliseconds(1))
    }, event: { if $0 == .heartbeatRecovered { recovered = true } })
    defer { heartbeat.stop() }
    try await waitUntil { recovered || heartbeat.failure != nil }
    #expect(recovered && heartbeat.failure == nil)
    #expect(await Array(delays.values.prefix(3)) == [1, 2, 4])
}
