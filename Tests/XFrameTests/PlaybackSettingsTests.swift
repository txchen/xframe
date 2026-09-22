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
