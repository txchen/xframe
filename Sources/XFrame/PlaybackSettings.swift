import AppKit
import GameController

// Confirmation is edge-triggered. Horizontal adjustments repeat with an initial delay.
struct PlaybackSettingsNavigation {
    enum Action: Equatable { case move(Int), adjust(Int), activate, dismiss }
    private var ready = false
    private var previous: Set<GamepadButton> = []
    private var repeatAt = 0.0
    mutating func reset() { ready = false; previous = []; repeatAt = 0 }
    mutating func process(_ state: GamepadSnapshot, now: Double = ProcessInfo.processInfo.systemUptime) -> Action? {
        let buttons = state.buttons
        defer { previous = buttons }
        guard ready else {
            if buttons.isEmpty && abs(state.leftX) < 0.25 && abs(state.leftY) < 0.25 { ready = true }
            return nil
        }
        let pressed = buttons.subtracting(previous)
        if pressed.contains(.b) { return .dismiss }
        if pressed.contains(.up) { return .move(-1) }
        if pressed.contains(.down) { return .move(1) }
        if pressed.contains(.a) { return .activate }
        let horizontal = buttons.intersection([.left, .right])
        guard horizontal.count == 1 else { repeatAt = 0; return nil }
        let direction = horizontal.contains(.left) ? -1 : 1
        if !pressed.intersection(horizontal).isEmpty {
            repeatAt = now + 0.4
            return .adjust(direction)
        }
        if now >= repeatAt {
            repeatAt = now + 0.1
            return .adjust(direction)
        }
        return nil
    }
}

@MainActor
final class PlaybackSettingsView: NSVisualEffectView {
    enum Mode: Equatable { case settings, confirmation, ending, failed(String) }
    private enum Row: Equatable {
        case scaling, sharpening, frameGeneration, hud, volume, mute, keyboard, rumble, fullscreen, end, close, cancel, confirm, retry
    }
    var selectScaling: ((VideoScalingMode) -> Void)?
    var selectFrameGeneration: ((FrameGenerationMode) -> Void)?
    var selectSharpening: ((SharpeningPreset) -> Void)?
    var selectHUD: ((PerformanceHUDPreset) -> Void)?
    var selectAudio: ((Bool, Double) -> Void)?
    var selectKeyboard: ((Bool) -> Void)?
    var selectRumble: ((Bool) -> Void)?
    var toggleFullscreen: (() -> Void)?
    var requestEnd: (() -> Void)?
    var confirmEnd: (() -> Void)?
    var dismiss: (() -> Void)?
    private(set) var mode: Mode = .settings
    var retainsTermination: Bool {
        switch mode { case .ending, .failed: return true; default: return false }
    }
    private var rows: [NSButton] = []
    private var actions: [Row] = []
    private var selectedRow = 0
    private let effectiveLabel = NSTextField(wrappingLabelWithString: "")
    private let slider = NSSlider(value: 1, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let scroll = NSScrollView()
    private let stack = NSStackView()
    private var navigation = PlaybackSettingsNavigation()
    private var sharpening: SharpeningPreset = .off
    private var scaling: VideoScalingMode = .original
    private var frameGeneration: FrameGenerationMode = .off
    private var hud: PerformanceHUDPreset = .compact
    private var cloud = false
    private var console = false
    private var muted = false
    private var keyboardEnabled = true
    private var rumbleEnabled = true
    private var volume = 1.0
    private var fullscreen = false
    private var transitioning = false

    private static let accentBorder = NSColor(red: 0.24, green: 0.84, blue: 0.48, alpha: 0.85).cgColor
    private static let accentFill = NSColor(red: 0.20, green: 0.78, blue: 0.44, alpha: 0.22).cgColor
    private static let dangerBorder = NSColor(red: 0.95, green: 0.32, blue: 0.30, alpha: 0.9).cgColor
    private static let dangerFill = NSColor(red: 0.90, green: 0.24, blue: 0.24, alpha: 0.26).cgColor
    private static let idleFill = NSColor.white.withAlphaComponent(0.06).cgColor
    private static let idleDangerFill = NSColor(red: 0.90, green: 0.24, blue: 0.24, alpha: 0.12).cgColor

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        appearance = NSAppearance(named: .darkAqua)
        wantsLayer = true
        layer?.cornerRadius = 16
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = stack
        addSubview(scroll)
        stack.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true
        effectiveLabel.font = .systemFont(ofSize: 11)
        effectiveLabel.textColor = .secondaryLabelColor
        slider.target = self
        slider.action = #selector(changeVolume(_:))
        slider.isContinuous = true
        slider.controlSize = .small
        slider.setAccessibilityLabel("Game volume")
        let preferredWidth = widthAnchor.constraint(equalToConstant: 368)
        let preferredHeight = heightAnchor.constraint(equalToConstant: 520)
        preferredWidth.priority = .defaultHigh
        preferredHeight.priority = .defaultHigh
        NSLayoutConstraint.activate([preferredWidth, preferredHeight])
        rebuild()
        isHidden = true
    }

    override func rightMouseDown(with event: NSEvent) { dismissRequested() }
    override func layout() {
        super.layout()
        scroll.frame = bounds.insetBy(dx: 16, dy: 14)
    }
    required init?(coder: NSCoder) { fatalError("Storyboard initialization is unsupported.") }

    private func header(_ title: String) {
        let view = NSTextField(wrappingLabelWithString: title)
        view.font = .systemFont(ofSize: 18, weight: .semibold)
        view.textColor = .labelColor
        stack.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -8).isActive = true
    }

    private func section(_ title: String) {
        let view = NSTextField(labelWithString: title.uppercased())
        view.font = .systemFont(ofSize: 10.5, weight: .semibold)
        view.textColor = NSColor.white.withAlphaComponent(0.48)
        stack.addArrangedSubview(view)
        stack.setCustomSpacing(10, after: stack.arrangedSubviews.dropLast().last ?? view)
    }

    private func note(_ text: String) {
        let view = NSTextField(wrappingLabelWithString: text)
        view.font = .systemFont(ofSize: 11)
        view.textColor = .secondaryLabelColor
        stack.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -8).isActive = true
    }

    private func addRow(_ row: Row) {
        let button = NSButton(title: "", target: self, action: #selector(activateRow(_:)))
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 8
        button.layer?.borderWidth = 1
        button.alignment = .left
        button.font = .systemFont(ofSize: 13, weight: .medium)
        button.tag = rows.count
        rows.append(button)
        actions.append(row)
        stack.addArrangedSubview(button)
        button.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -8).isActive = true
        button.heightAnchor.constraint(equalToConstant: 32).isActive = true
    }

    private func rebuild() {
        for view in stack.arrangedSubviews { stack.removeArrangedSubview(view); view.removeFromSuperview() }
        rows = []; actions = []; selectedRow = 0
        switch mode {
        case .settings:
            header("Playback Settings")
            section("Display")
            addRow(.scaling)
            stack.addArrangedSubview(effectiveLabel)
            effectiveLabel.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -8).isActive = true
            if scaling == .metalFX { addRow(.sharpening) }
            addRow(.frameGeneration)
            addRow(.hud)
            section(cloud ? "Audio & Input" : "Input")
            if cloud {
                addRow(.volume)
                stack.addArrangedSubview(slider)
                slider.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -16).isActive = true
                addRow(.mute)
            }
            addRow(.keyboard)
            if cloud { addRow(.rumble) }
            section("Session")
            addRow(.fullscreen)
            if cloud { addRow(.end) }
            addRow(.close)
            note("↑↓ Select · ←→ Change · Return / A Toggle · Esc / B Close")
        case .confirmation:
            header(console ? "Disconnect from Xbox?" : "End Session?")
            note(console ? "XFrame will disconnect. The Xbox and game remain on." : "This ends the stream. Save your game before disconnecting if needed.")
            addRow(.cancel)
            addRow(.confirm)
        case .ending:
            header(console ? "Disconnecting…" : "Ending Session…")
            note("Waiting for the streaming service to release the session. This request cannot be canceled.")
        case .failed(let message):
            header(console ? "Unable to Disconnect" : "Unable to End Session")
            note(message)
            addRow(.retry)
        }
        refreshSelection()
        stack.layoutSubtreeIfNeeded()
        let topY = max(0, stack.fittingSize.height - scroll.contentView.bounds.height)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: topY))
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    func configure(cloud: Bool, muted: Bool, volume: Double, rumbleEnabled: Bool = true,
                   keyboardEnabled: Bool = true, fullscreen: Bool, transitioning: Bool,
                   console: Bool = false) {
        let sourceChanged = self.cloud != cloud || self.console != console
        self.cloud = cloud; self.console = console; self.muted = muted; self.volume = volume
        self.rumbleEnabled = rumbleEnabled; self.keyboardEnabled = keyboardEnabled
        self.fullscreen = fullscreen; self.transitioning = transitioning
        if sourceChanged && mode == .settings { rebuild() }
        refreshSelection()
    }

    func show(scaling: VideoScalingMode, hud: PerformanceHUDPreset) {
        self.scaling = scaling; self.hud = hud
        mode = .settings
        rebuild()
        selectedRow = 0
        resetNavigation()
        isHidden = false
        refreshSelection()
    }

    func showTermination(_ mode: Mode) {
        guard mode != .settings else { return }
        self.mode = mode
        resetNavigation()
        rebuild()
        isHidden = false
    }

    func hide() {
        isHidden = true
        mode = .settings
        resetNavigation()
    }

    func resetNavigation() { navigation.reset() }

    func update(scaling: VideoScalingMode, hud: PerformanceHUDPreset) {
        let changed = self.scaling != scaling
        let selected = actions.indices.contains(selectedRow) ? actions[selectedRow] : nil
        self.scaling = scaling; self.hud = hud
        if changed && mode == .settings {
            rebuild()
            selectedRow = selected.flatMap { actions.firstIndex(of: $0) } ?? 0
        }
        refreshSelection()
    }

    func updateSharpening(_ preset: SharpeningPreset) {
        sharpening = preset
        refreshSelection()
    }

    func updateFrameGeneration(_ mode: FrameGenerationMode) {
        frameGeneration = mode
        refreshSelection()
    }

    func setEffective(_ status: ScalingStatus) { effectiveLabel.stringValue = status.title }

    func gamepad(_ state: GamepadSnapshot) {
        guard !isHidden, let action = navigation.process(state) else { return }
        perform(action)
    }

    @discardableResult func key(_ code: UInt16) -> Bool {
        switch code {
        case 126: perform(.move(-1))
        case 125: perform(.move(1))
        case 123: perform(.adjust(-1))
        case 124: perform(.adjust(1))
        case 36, 49: perform(.activate)
        case 53: perform(.dismiss)
        default: break
        }
        return true
    }

    func dismissRequested() { if !retainsTermination { dismiss?() } }

    private func cycle<T: Equatable>(_ all: [T], current: T, step: Int) -> T {
        let idx = all.firstIndex(of: current) ?? 0
        return all[(idx + step + all.count) % all.count]
    }

    private func perform(_ action: PlaybackSettingsNavigation.Action) {
        switch action {
        case .move(let step):
            guard !rows.isEmpty else { return }
            selectedRow = (selectedRow + step + rows.count) % rows.count
            refreshSelection()
            rows[selectedRow].scrollToVisible(rows[selectedRow].bounds)
        case .adjust(let step):
            guard actions.indices.contains(selectedRow) else { return }
            apply(actions[selectedRow], step: step)
        case .activate:
            guard rows.indices.contains(selectedRow) else { return }
            activateRow(rows[selectedRow])
        case .dismiss: dismissRequested()
        }
    }

    private func apply(_ row: Row, step: Int) {
        switch row {
        case .scaling:
            let next = cycle(VideoScalingMode.allCases, current: scaling, step: step)
            selectScaling?(next)
        case .sharpening:
            let next = cycle(SharpeningPreset.allCases, current: sharpening, step: step)
            sharpening = next
            refreshSelection()
            selectSharpening?(next)
        case .frameGeneration:
            let next = cycle(FrameGenerationMode.allCases, current: frameGeneration, step: step)
            frameGeneration = next
            refreshSelection()
            selectFrameGeneration?(next)
        case .hud:
            let next = cycle(PerformanceHUDPreset.allCases, current: hud, step: step)
            hud = next
            refreshSelection()
            selectHUD?(next)
        case .volume:
            volume = min(1, max(0, (volume * 100 + Double(step * 5)).rounded() / 100))
            refreshSelection()
            selectAudio?(muted, volume)
        case .mute:
            muted.toggle(); refreshSelection(); selectAudio?(muted, volume)
        case .keyboard:
            keyboardEnabled.toggle(); refreshSelection(); selectKeyboard?(keyboardEnabled)
        case .rumble:
            rumbleEnabled.toggle(); refreshSelection(); selectRumble?(rumbleEnabled)
        default: break
        }
    }

    private func isDestructive(_ row: Row) -> Bool {
        row == .end || row == .confirm
    }

    private func title(_ row: Row) -> String {
        switch row {
        case .scaling: return "Scaling:  ‹ \(scaling.title) ›"
        case .sharpening: return "Sharpening:  ‹ \(sharpening.title) ›"
        case .frameGeneration: return "Frame Generation:  ‹ \(frameGeneration.shortTitle) ›"
        case .hud: return "Overlay:  ‹ \(hud.title) ›"
        case .volume: return "Volume: \(Int((volume * 100).rounded()))%  ‹ ›"
        case .mute: return muted ? "Mute: On" : "Mute: Off"
        case .keyboard: return "Keyboard Input: " + (keyboardEnabled ? "On" : "Off")
        case .rumble: return "Controller Vibration: " + (rumbleEnabled ? "On" : "Off")
        case .fullscreen: return fullscreen ? "Exit Fullscreen" : "Enter Fullscreen"
        case .end, .confirm: return console ? "Disconnect" : "End Session"
        case .cancel: return "Cancel"
        case .retry: return console ? "Retry Disconnect" : "Retry End Session"
        case .close: return "Close"
        }
    }

    private func refreshSelection() {
        slider.doubleValue = volume
        for (index, button) in rows.enumerated() {
            let row = actions[index]
            let isSelected = index == selectedRow
            let danger = isDestructive(row)
            let text = (isSelected ? "▸ " : "   ") + title(row)
            let color: NSColor = danger
                ? NSColor(red: 1.0, green: 0.42, blue: 0.40, alpha: 1)
                : (isSelected ? .white : NSColor.white.withAlphaComponent(0.86))
            button.title = text
            button.attributedTitle = NSAttributedString(string: text, attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: isSelected ? .semibold : .medium),
                .foregroundColor: color
            ])
            button.layer?.backgroundColor = isSelected
                ? (danger ? Self.dangerFill : Self.accentFill)
                : (danger ? Self.idleDangerFill : Self.idleFill)
            button.layer?.borderColor = isSelected
                ? (danger ? Self.dangerBorder : Self.accentBorder)
                : NSColor.white.withAlphaComponent(0.06).cgColor
            button.isEnabled = row != .fullscreen || !transitioning
        }
    }

    @objc private func changeVolume(_ sender: NSSlider) {
        volume = sender.doubleValue
        if let index = actions.firstIndex(of: .volume) { selectedRow = index }
        refreshSelection()
        selectAudio?(muted, volume)
    }

    @objc private func activateRow(_ sender: NSButton) {
        guard sender.isEnabled, actions.indices.contains(sender.tag) else { return }
        selectedRow = sender.tag
        let row = actions[selectedRow]
        switch row {
        case .scaling, .sharpening, .frameGeneration, .hud, .mute, .keyboard, .rumble:
            apply(row, step: 1)
        case .volume: break
        case .fullscreen: toggleFullscreen?()
        case .end: requestEnd?()
        case .confirm, .retry: confirmEnd?()
        case .close, .cancel: dismissRequested()
        }
    }
}

// Local panel input must survive transport loss and session teardown.
@MainActor
final class PlaybackPanelInput {
    private var task: Task<Void, Never>?
    private var controller: GCController?
    func start(panel: PlaybackSettingsView, enabled: @escaping @MainActor () -> Bool) {
        guard task == nil else { return }
        task = Task { [weak self, weak panel] in
            var wasEnabled = false
            while !Task.isCancelled {
                guard let self, let panel else { return }
                let active = enabled()
                if active {
                    let devices = GCController.controllers().filter { $0.extendedGamepad != nil && !$0.isSnapshot }
                    if !devices.contains(where: { $0 === self.controller }) {
                        self.controller = devices.first
                        panel.resetNavigation()
                    }
                    if !wasEnabled { panel.resetNavigation() }
                    if let pad = self.controller?.extendedGamepad { panel.gamepad(NativeGamepad.snapshot(pad)) }
                } else if wasEnabled { panel.resetNavigation() }
                wasEnabled = active
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }
    func stop() { task?.cancel(); task = nil; controller = nil }
}
