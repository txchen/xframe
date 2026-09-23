import AppKit
import Testing
@testable import XFrame

@Test func settingsNavigationRequiresReleaseAndConsumesButtonEdges() {
    var navigation = PlaybackSettingsNavigation()
    #expect(navigation.process(GamepadSnapshot(buttons: [.view, .menu, .a])) == nil)
    #expect(navigation.process(GamepadSnapshot(buttons: [.a])) == nil)
    #expect(navigation.process(GamepadSnapshot()) == nil)
    #expect(navigation.process(GamepadSnapshot(buttons: [.down])) == .move(1))
    #expect(navigation.process(GamepadSnapshot(buttons: [.down])) == nil)
    #expect(navigation.process(GamepadSnapshot()) == nil)
    #expect(navigation.process(GamepadSnapshot(buttons: [.up])) == .move(-1))
    #expect(navigation.process(GamepadSnapshot(buttons: [.a])) == .activate)
    #expect(navigation.process(GamepadSnapshot(buttons: [.a])) == nil)
    #expect(navigation.process(GamepadSnapshot(buttons: [.b])) == .dismiss)
    navigation.reset()
    #expect(navigation.process(GamepadSnapshot(buttons: [.b])) == nil)
}

@Test func settingsReleaseDropsQueuedGameplayAndRequiresNeutralOnReturn() {
    var input = GamepadInput()
    input.update(GamepadSnapshot(), ownsInput: true)
    input.update(GamepadSnapshot(buttons: [.a], leftX: 1), ownsInput: true)
    // Same release boundary used when the panel opens and closes.
    input.release()
    input.update(GamepadSnapshot(), ownsInput: false)
    #expect(input.queue.isEmpty && !input.armed && input.needsNeutral)
    input.update(GamepadSnapshot(buttons: [.b]), ownsInput: true)
    #expect(!input.armed && input.queue.isEmpty)
    input.update(GamepadSnapshot(), ownsInput: true)
    #expect(input.armed)
    input.update(GamepadSnapshot(buttons: [.a]), ownsInput: true)
    #expect(input.queue.last?.buttons == [.a])
}

@Test @MainActor func settingsPanelKeyboardAppliesChoicesWithoutClosing() {
    let panel = PlaybackSettingsView()
    var selected: VideoScalingMode?
    var hud: PerformanceHUDPreset?
    var closed = false
    panel.selectScaling = { selected = $0 }
    panel.selectHUD = { hud = $0 }
    panel.dismiss = { closed = true }
    panel.show(scaling: .original, hud: .compact)
    panel.key(125) // Integer
    panel.key(36)
    #expect(selected == .integer && !closed && !panel.isHidden)
    panel.key(125) // MetalFX
    panel.key(36)
    #expect(selected == .metalFX)
    panel.key(125) // Compact
    panel.key(125) // Detailed
    panel.key(36)
    #expect(hud == .detailed && !closed)
    panel.key(53)
    #expect(closed)
}

@Test @MainActor func settingsPanelShowsItsEntireTitleAfterLayout() throws {
    let panel = PlaybackSettingsView()
    panel.frame = NSRect(x: 0, y: 0, width: 350, height: 470)
    panel.show(scaling: .integer, hud: .detailed)
    panel.setEffective(ScalingPlan.make(mode: .integer, source: .init(width: 1920, height: 1080),
        canvas: .init(width: 3064, height: 1634), fullscreen: false, supported: true).status)
    panel.layoutSubtreeIfNeeded()
    let scroll = try #require(panel.subviews.compactMap { $0 as? NSScrollView }.first)
    let stack = try #require(scroll.documentView as? NSStackView)
    let title = try #require(stack.arrangedSubviews.first)
    #expect(scroll.documentVisibleRect.contains(title.frame))
}

@Test func settingsVolumeRepeatHasDelayAndNeverRepeatsConfirmation() {
    var navigation = PlaybackSettingsNavigation()
    _ = navigation.process(GamepadSnapshot(), now: 0)
    #expect(navigation.process(GamepadSnapshot(buttons: [.right]), now: 1) == .adjust(1))
    #expect(navigation.process(GamepadSnapshot(buttons: [.right]), now: 1.39) == nil)
    #expect(navigation.process(GamepadSnapshot(buttons: [.right]), now: 1.41) == .adjust(1))
    #expect(navigation.process(GamepadSnapshot(buttons: [.right]), now: 1.42) == nil)
    #expect(navigation.process(GamepadSnapshot(buttons: [.right]), now: 1.52) == .adjust(1))
    #expect(navigation.process(GamepadSnapshot(buttons: [.left, .right]), now: 2) == nil)
    #expect(navigation.process(GamepadSnapshot(buttons: [.a]), now: 3) == .activate)
    #expect(navigation.process(GamepadSnapshot(buttons: [.a]), now: 5) == nil)
    navigation.reset()
    #expect(navigation.process(GamepadSnapshot(buttons: [.a]), now: 6) == nil)
}

@MainActor private func buttons(in panel: PlaybackSettingsView) -> [NSButton] {
    let scroll = panel.subviews.compactMap { $0 as? NSScrollView }.first!
    return (scroll.documentView as! NSStackView).arrangedSubviews.compactMap { $0 as? NSButton }
}

@Test @MainActor func cloudAudioControlsClampVolumeAndPreserveMute() throws {
    let panel = PlaybackSettingsView()
    panel.configure(cloud: true, muted: true, volume: 0.4, fullscreen: false, transitioning: false)
    panel.show(scaling: .original, hud: .compact)
    var changes: [(Bool, Double)] = []
    panel.selectAudio = { changes.append(($0, $1)) }
    let volume = try #require(buttons(in: panel).first { $0.title.contains("Volume:") })
    volume.performClick(nil)
    panel.key(124)
    #expect(changes.last?.0 == true && changes.last?.1 == 0.45)
    for _ in 0..<30 { panel.key(124) }
    #expect(changes.last?.1 == 1)
    for _ in 0..<30 { panel.key(123) }
    #expect(changes.last?.1 == 0)
    panel.key(125) // Mute
    panel.key(36)
    #expect(changes.last?.0 == false && changes.last?.1 == 0)
}

@Test @MainActor func controllerVibrationRowReflectsAndChangesPreference() throws {
    let panel = PlaybackSettingsView()
    panel.configure(cloud: true, muted: false, volume: 1, rumbleEnabled: true,
                    fullscreen: false, transitioning: false)
    panel.show(scaling: .original, hud: .compact)
    var selected: Bool?
    panel.selectRumble = { selected = $0 }
    let toggle = try #require(buttons(in: panel).first { $0.title.contains("Controller Vibration") })
    #expect(toggle.title.contains("On"))
    toggle.performClick(nil)
    #expect(selected == false && toggle.title.contains("Off"))
    panel.configure(cloud: true, muted: false, volume: 1, rumbleEnabled: true,
                    fullscreen: false, transitioning: false)
    #expect(toggle.title.contains("On"))
}

@Test @MainActor func fullscreenTransitionRetainsSelectionAndDisablesRepeatedActivation() throws {
    let panel = PlaybackSettingsView()
    panel.show(scaling: .original, hud: .compact)
    var count = 0
    panel.toggleFullscreen = {
        count += 1
        panel.configure(cloud: false, muted: false, volume: 1, fullscreen: false, transitioning: true)
    }
    try #require(buttons(in: panel).first { $0.title.contains("Enter Fullscreen") }).performClick(nil)
    panel.key(36)
    #expect(count == 1)
    panel.configure(cloud: false, muted: false, volume: 1, fullscreen: true, transitioning: false)
    let exit = try #require(buttons(in: panel).first { $0.title.contains("Exit Fullscreen") })
    #expect(exit.title.hasPrefix("▸") && exit.isEnabled && !panel.isHidden)
    panel.key(36)
    #expect(count == 2)
}

@Test @MainActor func terminationConfirmationDefaultsToCancelAndHeldInputCannotCarryThrough() {
    let panel = PlaybackSettingsView()
    var confirmed = 0
    var dismissed = 0
    panel.confirmEnd = { confirmed += 1; panel.showTermination(.ending) }
    panel.dismiss = { dismissed += 1; panel.hide() }
    panel.showTermination(.confirmation)
    panel.gamepad(GamepadSnapshot(buttons: [.a]))
    #expect(confirmed == 0 && dismissed == 0)
    panel.gamepad(GamepadSnapshot())
    panel.gamepad(GamepadSnapshot(buttons: [.a])) // Default Cancel
    #expect(confirmed == 0 && dismissed == 1 && panel.isHidden)
    panel.showTermination(.confirmation)
    panel.key(125)
    panel.key(36)
    #expect(confirmed == 1 && panel.retainsTermination)
    panel.key(36)
    panel.key(53)
    panel.dismissRequested()
    #expect(confirmed == 1 && dismissed == 1 && !panel.isHidden)
    panel.showTermination(.failed("Cleanup failed"))
    panel.gamepad(GamepadSnapshot(buttons: [.a]))
    #expect(confirmed == 1)
    panel.gamepad(GamepadSnapshot())
    panel.gamepad(GamepadSnapshot(buttons: [.a]))
    #expect(confirmed == 2)
    panel.hide()
    #expect(!panel.retainsTermination)
    panel.show(scaling: .original, hud: .compact)
    #expect(panel.mode == .settings && !panel.isHidden)
}

@Test @MainActor func localSourcesHideCloudActionsAndSmallPanelScrollsToLastRow() throws {
    let panel = PlaybackSettingsView()
    panel.configure(cloud: false, muted: true, volume: 0.4, fullscreen: false, transitioning: false)
    panel.show(scaling: .original, hud: .compact)
    #expect(!buttons(in: panel).contains { $0.title.contains("Volume") || $0.title.contains("Mute") || $0.title.contains("End Session") })
    panel.configure(cloud: true, muted: false, volume: 1, fullscreen: false, transitioning: false)
    panel.frame = NSRect(x: 0, y: 0, width: 296, height: 156)
    panel.layoutSubtreeIfNeeded()
    let controls = buttons(in: panel)
    for _ in 1..<controls.count { panel.key(125) }
    let scroll = try #require(panel.subviews.compactMap { $0 as? NSScrollView }.first)
    let close = try #require(controls.last)
    #expect(close.title.contains("Close") && close.title.hasPrefix("▸"))
    #expect(scroll.documentVisibleRect.intersects(close.frame))
}
