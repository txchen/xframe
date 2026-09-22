import AppKit

// Local navigation consumes edges, never repeats a held confirmation. The opening
// chord must be released before navigation can begin.
struct PlaybackSettingsNavigation {
    enum Action: Equatable { case move(Int), activate, dismiss }
    private var ready = false
    private var previous: Set<GamepadButton> = []
    mutating func reset() { ready = false; previous = [] }
    mutating func process(_ state: GamepadSnapshot) -> Action? {
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
        return nil
    }
}

@MainActor
final class PlaybackSettingsView: NSVisualEffectView {
    var selectScaling: ((VideoScalingMode) -> Void)?
    var selectHUD: ((PerformanceHUDPreset) -> Void)?
    var dismiss: (() -> Void)?
    private var rows: [NSButton] = []
    private var selectedRow = 0
    private let effectiveLabel = NSTextField(wrappingLabelWithString: "")
    private var rowTitles: [String] = []
    private let scroll = NSScrollView()
    private let stack = NSStackView()
    private var navigation = PlaybackSettingsNavigation()

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
        func label(_ title: String, size: CGFloat) {
            let view = NSTextField(labelWithString: title)
            view.font = .systemFont(ofSize: size, weight: .semibold)
            stack.addArrangedSubview(view)
        }
        label("Playback Settings", size: 20)
        label("Video Scaling", size: 13)
        for mode in VideoScalingMode.allCases { addRow(mode.title, to: stack) }
        effectiveLabel.font = .systemFont(ofSize: 11)
        effectiveLabel.textColor = .secondaryLabelColor
        stack.addArrangedSubview(effectiveLabel)
        effectiveLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 310).isActive = true
        label("Performance Overlay", size: 13)
        for preset in PerformanceHUDPreset.allCases { addRow(preset.title, to: stack) }
        addRow("Close", to: stack)
        let hint = NSTextField(wrappingLabelWithString: "D-pad ↑↓ · A select · B close\nKeyboard ↑↓ · Return select · Esc close\nVideo continues; game input is held while this panel is open.")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        stack.addArrangedSubview(hint)
        let preferredWidth = widthAnchor.constraint(equalToConstant: 350)
        let preferredHeight = heightAnchor.constraint(equalToConstant: 470)
        preferredWidth.priority = .defaultHigh
        preferredHeight.priority = .defaultHigh
        NSLayoutConstraint.activate([preferredWidth, preferredHeight])
        isHidden = true
    }
    override func rightMouseDown(with event: NSEvent) { dismiss?() }
    override func layout() {
        super.layout()
        scroll.frame = bounds.insetBy(dx: 16, dy: 16)
    }
    required init?(coder: NSCoder) { fatalError("Storyboard initialization is unsupported.") }
    private func addRow(_ title: String, to stack: NSStackView) {
        let button = NSButton(title: title, target: self, action: #selector(activateRow(_:)))
        button.bezelStyle = .rounded
        button.alignment = .left
        button.tag = rows.count
        button.setButtonType(.momentaryPushIn)
        rows.append(button)
        stack.addArrangedSubview(button)
        button.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -8).isActive = true
        button.heightAnchor.constraint(equalToConstant: 28).isActive = true
    }
    func show(scaling: VideoScalingMode, hud: PerformanceHUDPreset) {
        selectedRow = VideoScalingMode.allCases.firstIndex(of: scaling) ?? 0
        navigation.reset()
        isHidden = false
        update(scaling: scaling, hud: hud)
    }
    func update(scaling: VideoScalingMode, hud: PerformanceHUDPreset) {
        rowTitles = VideoScalingMode.allCases.map { ($0 == scaling ? "✓ " : "") + $0.title }
            + PerformanceHUDPreset.allCases.map { ($0 == hud ? "✓ " : "") + $0.title } + ["Close"]
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
        case 36, 49: perform(.activate)
        case 53: perform(.dismiss)
        default: break
        }
        return true
    }
    private func perform(_ action: PlaybackSettingsNavigation.Action) {
        switch action {
        case .move(let step):
            selectedRow = (selectedRow + step + rows.count) % rows.count
            refreshSelection()
            rows[selectedRow].scrollToVisible(rows[selectedRow].bounds)
        case .activate: activateRow(rows[selectedRow])
        case .dismiss: dismiss?()
        }
    }
    private func refreshSelection() {
        for (index, button) in rows.enumerated() where index < rowTitles.count {
            button.title = (index == selectedRow ? "▸ " : "   ") + rowTitles[index]
        }
    }
    @objc private func activateRow(_ sender: NSButton) {
        selectedRow = sender.tag
        let modes = VideoScalingMode.allCases
        if sender.tag < modes.count { selectScaling?(modes[sender.tag]) }
        else if sender.tag < modes.count + PerformanceHUDPreset.allCases.count {
            selectHUD?(PerformanceHUDPreset.allCases[sender.tag - modes.count])
        } else { dismiss?() }
    }
}
