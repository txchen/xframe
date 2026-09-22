import AppKit
import GameController

// Confirmation is edge-triggered. Only horizontal volume adjustment repeats.
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
        case scaling(VideoScalingMode), hud(PerformanceHUDPreset), sharpening(SharpeningPreset), volume, mute, fullscreen, end, close, cancel, confirm, retry
    }
    var selectScaling: ((VideoScalingMode) -> Void)?
    var selectSharpening: ((SharpeningPreset) -> Void)?
    var selectHUD: ((PerformanceHUDPreset) -> Void)?
    var selectAudio: ((Bool, Double) -> Void)?
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
    private var hud: PerformanceHUDPreset = .compact
    private var cloud = false
    private var muted = false
    private var volume = 1.0
    private var fullscreen = false
    private var transitioning = false

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        appearance = NSAppearance(named: .darkAqua)
        wantsLayer = true
        layer?.cornerRadius = 12
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
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
        slider.setAccessibilityLabel("Game volume")
        let preferredWidth = widthAnchor.constraint(equalToConstant: 350)
        let preferredHeight = heightAnchor.constraint(equalToConstant: 620)
        preferredWidth.priority = .defaultHigh
        preferredHeight.priority = .defaultHigh
        NSLayoutConstraint.activate([preferredWidth, preferredHeight])
        rebuild()
        isHidden = true
    }
    override func rightMouseDown(with event: NSEvent) { dismissRequested() }
    override func layout() {
        super.layout()
        scroll.frame = bounds.insetBy(dx: 16, dy: 16)
    }
    required init?(coder: NSCoder) { fatalError("Storyboard initialization is unsupported.") }
    private func label(_ title: String, size: CGFloat = 13) {
        let view = NSTextField(wrappingLabelWithString: title)
        view.font = .systemFont(ofSize: size, weight: .semibold)
        stack.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -8).isActive = true
    }
    private func addRow(_ row: Row) {
        let button = NSButton(title: "", target: self, action: #selector(activateRow(_:)))
        button.bezelStyle = .rounded
        button.alignment = .left
        button.tag = rows.count
        button.setButtonType(.momentaryPushIn)
        rows.append(button)
        actions.append(row)
        stack.addArrangedSubview(button)
        button.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -8).isActive = true
        button.heightAnchor.constraint(equalToConstant: 28).isActive = true
    }
    private func rebuild() {
        for view in stack.arrangedSubviews { stack.removeArrangedSubview(view); view.removeFromSuperview() }
        rows = []; actions = []; selectedRow = 0
        switch mode {
        case .settings:
            label("Playback Settings", size: 20)
            label("Video Scaling")
            for mode in VideoScalingMode.allCases { addRow(.scaling(mode)) }
            stack.addArrangedSubview(effectiveLabel)
            effectiveLabel.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -8).isActive = true
            label("Performance Overlay")
            for preset in PerformanceHUDPreset.allCases { addRow(.hud(preset)) }
            if scaling == .metalFX {
                label("MetalFX Sharpening")
                for preset in SharpeningPreset.allCases { addRow(.sharpening(preset)) }
                label("Extra sharpening after MetalFX. Off keeps the original MetalFX result. Applies only while MetalFX is active.", size: 11)
            }
            if cloud {
                label("Game Audio")
                addRow(.volume)
                stack.addArrangedSubview(slider)
                slider.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -8).isActive = true
                addRow(.mute)
            }
            addRow(.fullscreen)
            if cloud { addRow(.end) }
            addRow(.close)
            label("D-pad ↑↓ · A select · B close\nVolume ←→ · Keyboard arrows / Return / Esc\nVideo continues; game input is held while settings are open.", size: 11)
        case .confirmation:
            label("End Session?", size: 20)
            label("This ends your cloud game. Unsaved progress may be lost.")
            addRow(.cancel)
            addRow(.confirm)
        case .ending:
            label("Ending Session…", size: 20)
            label("Waiting for the cloud service to release the session. This request cannot be canceled.")
        case .failed(let message):
            label("Unable to End Session", size: 20)
            label(message)
            addRow(.retry)
        }
        refreshSelection()
        scroll.contentView.scroll(to: .zero)
        scroll.reflectScrolledClipView(scroll.contentView)
    }
    func configure(cloud: Bool, muted: Bool, volume: Double, fullscreen: Bool, transitioning: Bool) {
        let sourceChanged = self.cloud != cloud
        self.cloud = cloud; self.muted = muted; self.volume = volume
        self.fullscreen = fullscreen; self.transitioning = transitioning
        if sourceChanged && mode == .settings { rebuild() }
        refreshSelection()
    }
    func show(scaling: VideoScalingMode, hud: PerformanceHUDPreset) {
        self.scaling = scaling; self.hud = hud
        mode = .settings
        rebuild()
        selectedRow = VideoScalingMode.allCases.firstIndex(of: scaling) ?? 0
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
    private func perform(_ action: PlaybackSettingsNavigation.Action) {
        switch action {
        case .move(let step):
            guard !rows.isEmpty else { return }
            selectedRow = (selectedRow + step + rows.count) % rows.count
            refreshSelection()
            rows[selectedRow].scrollToVisible(rows[selectedRow].bounds)
        case .adjust(let step):
            guard actions.indices.contains(selectedRow), actions[selectedRow] == .volume else { return }
            volume = min(1, max(0, (volume * 100 + Double(step * 5)).rounded() / 100))
            refreshSelection()
            selectAudio?(muted, volume)
        case .activate:
            guard rows.indices.contains(selectedRow) else { return }
            activateRow(rows[selectedRow])
        case .dismiss: dismissRequested()
        }
    }
    private func title(_ row: Row) -> String {
        switch row {
        case .scaling(let value): return (value == scaling ? "✓ " : "") + value.title
        case .hud(let value): return (value == hud ? "✓ " : "") + value.title
        case .sharpening(let preset): return (preset == sharpening ? "✓ " : "") + preset.title
        case .volume: return "Volume: \(Int((volume * 100).rounded()))%  ← →"
        case .mute: return muted ? "✓ Mute" : "Mute"
        case .fullscreen: return fullscreen ? "Exit Fullscreen" : "Enter Fullscreen"
        case .end, .confirm: return "End Session"
        case .cancel: return "Cancel"
        case .retry: return "Retry End Session"
        case .close: return "Close"
        }
    }
    private func refreshSelection() {
        slider.doubleValue = volume
        for (index, button) in rows.enumerated() {
            button.title = (index == selectedRow ? "▸ " : "   ") + title(actions[index])
            button.isEnabled = actions[index] != .fullscreen || !transitioning
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
        switch actions[selectedRow] {
        case .scaling(let mode): selectScaling?(mode)
        case .hud(let preset): selectHUD?(preset)
        case .sharpening(let preset): selectSharpening?(preset)
        case .volume: break
        case .mute: muted.toggle(); refreshSelection(); selectAudio?(muted, volume)
        case .fullscreen: toggleFullscreen?()
        case .end: requestEnd?()
        case .confirm, .retry: confirmEnd?()
        case .close, .cancel: dismissRequested()
        }
    }
}

// Local panel input must survive transport loss and session teardown. Poll without
// installing controller handlers, so the streaming input owner remains untouched.
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
