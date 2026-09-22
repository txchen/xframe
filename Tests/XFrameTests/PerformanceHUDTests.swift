import Foundation
import GameController
import Testing
@testable import XFrame

@Test func videoBitrateUsesMicrosecondsAndResetsForNewSources() {
    var meter = VideoBitrateMeter()
    let initial = meter.sample(bytes: 1_000_000, timestampUS: 1_000_000, streamID: "a")
    let rate = meter.sample(bytes: 4_000_000, timestampUS: 3_000_000, streamID: "a")
    #expect(initial == nil && rate == 12)
    let zero = meter.sample(bytes: 4_000_000, timestampUS: 4_000_000, streamID: "a")
    #expect(zero == 0) // Measured zero is distinct from missing data.
    let switched = meter.sample(bytes: 9_000_000, timestampUS: 5_000_000, streamID: "b")
    let reset = meter.sample(bytes: 0, timestampUS: 6_000_000, streamID: "b")
    let afterReset = meter.sample(bytes: 1_000_000, timestampUS: 7_000_000, streamID: "b")
    #expect(switched == nil && reset == nil && afterReset == 8)
}

@Test func videoBitrateRejectsMissingInvalidAndOutOfOrderSamples() {
    var meter = VideoBitrateMeter()
    _ = meter.sample(bytes: 0, timestampUS: 1_000_000, streamID: "a")
    let duplicate = meter.sample(bytes: 1_000_000, timestampUS: 1_000_000, streamID: "a")
    let reversed = meter.sample(bytes: 1_000_000, timestampUS: 500_000, streamID: "a")
    let next = meter.sample(bytes: 1_000_000, timestampUS: 2_000_000, streamID: "a")
    #expect(duplicate == nil && reversed == nil && next == 8)
    let oldCounter = meter.sample(bytes: 0, timestampUS: 1_000_000, streamID: "a")
    let afterOldCounter = meter.sample(bytes: 2_000_000, timestampUS: 3_000_000, streamID: "a")
    #expect(oldCounter == nil && afterOldCounter == 8)
    for invalid: Double? in [nil, .nan, .infinity, -1] {
        let result = meter.sample(bytes: invalid, timestampUS: 3_000_000, streamID: "a")
        #expect(result == nil)
        let baseline = meter.sample(bytes: 0, timestampUS: 4_000_000, streamID: "a")
        #expect(baseline == nil)
    }
}

@Test func videoBitrateReachesLiveStatsAndSanitizedExportWithoutLateMutation() throws {
    let source = LiveVideo()
    source.networkSample(received: 1, lost: 0, nacks: 0, bytes: 0, timestampUS: 1_000_000, streamID: "a")
    #expect(source.snapshot().videoBitrateMbps == nil)
    source.networkSample(received: 2, lost: 0, nacks: 0, bytes: 2_000_000, timestampUS: 2_000_000, streamID: "a")
    #expect(source.snapshot().videoBitrateMbps == 16)
    source.stop()
    source.networkSample(received: 3, lost: 0, nacks: 0, bytes: 4_000_000, timestampUS: 3_000_000, streamID: "a")
    #expect(source.diagnosticReport().video.bitrateMbps == 16)
    var stats = PlaybackStats()
    stats.videoBitrateMbps = .infinity
    let report = StreamDiagnosticReport(stats: stats, outcome: .active, duration: 0, events: [])
    #expect(report.video.bitrateMbps == nil)
    #expect(try !report.encoded().isEmpty)
}

@Test func performanceHUDPresetsKeepStreamRatesDistinctFromGameFPS() {
    var stats = PlaybackStats()
    stats.isLive = true
    stats.capacity = LiveVideo.displayCapacity
    stats.elapsed = 2
    stats.decoded = 60
    stats.presented = 60
    stats.recentDecodedFPS = 60
    stats.recentPresentedFPS = 55
    stats.videoBitrateMbps = 15.5
    #expect(PerformanceHUDPreset.compact.next == .detailed)
    #expect(PerformanceHUDPreset.detailed.next == .hidden)
    #expect(PerformanceHUDPreset.hidden.next == .compact)
    let compact = PerformanceHUDText.render(stats, preset: .compact, controller: "Gamepad")
    #expect(compact.contains("2s") && !compact.contains("SESSION avg"))
    #expect(PerformanceHUDText.render(stats, preset: .detailed, controller: "Gamepad").contains("SESSION avg IN 30.0"))
    #expect(compact.split(separator: "\n").count == 3)
    #expect(compact.contains("60.0") && compact.contains("55.0") && compact.contains("15.5 Mbps"))
    #expect(PerformanceHUDText.render(stats, preset: .detailed, controller: "Gamepad").contains("Game FPS not measured"))
    #expect(PerformanceHUDText.render(stats, preset: .hidden, controller: "Gamepad").isEmpty)
    stats.videoBitrateMbps = nil
    #expect(PerformanceHUDText.render(stats, preset: .compact, controller: "Gamepad").contains("n/a Mbps"))
}

@Test func gamepadHUDChordIsLocalAndCyclesOnceUntilBothButtonsRelease() {
    var shortcut = GamepadHUDShortcut()
    let first = shortcut.process(GamepadSnapshot(buttons: [.view], leftX: 0.5), now: 0)
    let chord = shortcut.process(GamepadSnapshot(buttons: [.view, .menu, .a], leftX: 0.5), now: 0.05)
    let held = shortcut.process(GamepadSnapshot(buttons: [.view, .menu]), now: 1)
    let partlyReleased = shortcut.process(GamepadSnapshot(buttons: [.menu]), now: 1.1)
    #expect(first.states.first?.buttons == [] && first.states.first?.leftX == 0.5)
    #expect(chord.cycle && chord.states.first?.buttons == [.a] && chord.states.first?.leftX == 0.5)
    #expect(!held.cycle && held.states.first?.buttons == [])
    #expect(!partlyReleased.cycle && partlyReleased.states.first?.buttons == [])
    _ = shortcut.process(GamepadSnapshot(), now: 2)
    #expect(shortcut.process(GamepadSnapshot(buttons: [.view, .menu]), now: 3).cycle)
}

@Test func gamepadHUDShortcutPreservesStandaloneTapHoldAndLateSecondButton() {
    var shortcut = GamepadHUDShortcut()
    _ = shortcut.process(GamepadSnapshot(buttons: [.menu]), now: 0)
    let tap = shortcut.process(GamepadSnapshot(), now: 0.05)
    #expect(tap.states.map(\.buttons) == [[.menu], []] && !tap.cycle)
    _ = shortcut.process(GamepadSnapshot(buttons: [.view]), now: 1)
    let hold = shortcut.process(GamepadSnapshot(buttons: [.view]), now: 1.4)
    #expect(hold.states.first?.buttons == [.view] && !hold.cycle)
    let late = shortcut.process(GamepadSnapshot(buttons: [.view, .menu]), now: 2)
    #expect(!late.cycle && late.states.first?.buttons == [.view, .menu])
    shortcut.reset()
    let released = shortcut.process(GamepadSnapshot(), now: 3)
    #expect(released.states.map(\.buttons) == [[]]) // No delayed press survives focus loss.
}

@Test func gamepadHUDChordAcceptsCapturedXboxButtonStagger() {
    // Physical Xbox trace: first press at 24.957 s, second at 25.085 s.
    // The connection also polls between the two button callbacks.
    var shortcut = GamepadHUDShortcut()
    _ = shortcut.process(GamepadSnapshot(buttons: [.menu]), now: 24.957)
    _ = shortcut.process(GamepadSnapshot(buttons: [.menu]), now: 25.080)
    let chord = shortcut.process(GamepadSnapshot(buttons: [.menu, .view]), now: 25.085)
    #expect(chord.cycle)
    #expect(chord.states.allSatisfy { $0.buttons.isDisjoint(with: [.menu, .view]) })
}

@Test @MainActor func gamepadSystemGestureCaptureRestoresOriginalPreferences() {
    let pad = GCController.withExtendedGamepad().extendedGamepad!
    let menu = pad.buttonMenu
    menu.preferredSystemGestureState = .enabled
    let scope = GamepadSystemGestures()
    scope.capture([menu])
    #expect(menu.preferredSystemGestureState == .disabled)
    scope.capture([menu]) // Repeated focus notifications must not overwrite the original.
    scope.restore()
    #expect(menu.preferredSystemGestureState == .enabled)
    menu.preferredSystemGestureState = .disabled
    scope.capture([menu])
    scope.restore()
    #expect(menu.preferredSystemGestureState == .disabled)
}
