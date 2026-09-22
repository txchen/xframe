import AppKit
import MetalKit
import UniformTypeIdentifiers
import SwiftUI

@main
@MainActor
enum XFrameApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow?
    private var playbackPresentation: PlaybackWindowPresentation?
    private var renderer: MetalRenderer?
    private var videoView: MetalView?
    private var playback: LocalVideo?
    private var lastURL: URL?
    private lazy var account = XboxAccount()
    private var libraryWindow: NSWindow?
    private let playbackSettings = PlaybackSettingsView()
    private let diagnostics = PerformanceHUDView()
    private var hudPreset = PerformanceHUDPreset(rawValue: UserDefaults.standard.string(forKey: "XFrame.PerformanceHUD") ?? "") ?? .compact
    private var scalingMode = VideoScalingMode(rawValue: UserDefaults.standard.string(forKey: VideoScalingMode.preferenceKey) ?? "") ?? .original
    private var scalingMenuItems: [NSMenuItem] = []
    private var hudMenuItems: [NSMenuItem] = []
    private var controllerMenuItem: NSMenuItem?
    private var keyboardMenuItem: NSMenuItem?
    private var keyboardMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMenu()
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            return self.handleKeyboard(event)
        }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(systemWillSleep(_:)),
            name: NSWorkspace.willSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(systemDidWake(_:)),
            name: NSWorkspace.didWakeNotification, object: nil)
        do {
            guard let device = MTLCreateSystemDefaultDevice() else {
                throw RenderError.unavailable("A Metal-capable GPU is required.")
            }
            let view = MetalView(frame: NSRect(x: 0, y: 0, width: 960, height: 540), device: device)
            let renderer = try MetalRenderer(view: view)
            renderer.scalingMode = scalingMode
            renderer.scalingReport = { [weak self] status in
                self?.diagnostics.scaling = status
                self?.playbackSettings.setEffective(status)
            }
            view.showPlaybackSettings = { [weak self] in self?.togglePlaybackSettings() }
            view.dismissPlaybackSettings = { [weak self] in self?.hidePlaybackSettings() }
            playbackSettings.selectScaling = { [weak self] mode in self?.setScaling(mode) }
            playbackSettings.selectHUD = { [weak self] preset in self?.setPerformanceHUD(preset) }
            playbackSettings.dismiss = { [weak self] in self?.hidePlaybackSettings() }
            self.renderer = renderer
            self.videoView = view
            view.delegate = renderer

            let window = NSWindow(
                contentRect: view.frame,
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered, defer: false
            )
            window.title = "XFrame — Native Rendering"
            window.backgroundColor = .black
            window.delegate = self
            window.contentMinSize = NSSize(width: 320, height: 180)
            window.collectionBehavior = [.fullScreenPrimary]
            let content = NSView(frame: view.frame)
            content.wantsLayer = true
            content.layer?.backgroundColor = NSColor.black.cgColor
            content.addSubview(view)
            diagnostics.preset = hudPreset
            content.addSubview(diagnostics)
            content.addSubview(playbackSettings)
            NSLayoutConstraint.activate([
                playbackSettings.centerXAnchor.constraint(equalTo: content.centerXAnchor),
                playbackSettings.centerYAnchor.constraint(equalTo: content.centerYAnchor),
                playbackSettings.widthAnchor.constraint(lessThanOrEqualTo: content.widthAnchor, constant: -24),
                playbackSettings.heightAnchor.constraint(lessThanOrEqualTo: content.heightAnchor, constant: -24)
            ])
            NSLayoutConstraint.activate([
                diagnostics.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
                diagnostics.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
                diagnostics.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -12)
            ])
            renderer.report = { [weak self] stats in
                guard let self else { return }
                self.diagnostics.update(stats, controller: self.account.library.controllerStatus,
                    quality: self.account.library.activeStreamPreferences?.quality)
            }
            window.contentView = content
            window.isReleasedWhenClosed = false
            WindowPlacement.restore(window, name: "XFrame.Playback.v1",
                                    preferredContentSize: NSSize(width: 960, height: 540))
            self.window = window
            playbackPresentation = PlaybackWindowPresentation(surface: window)
            view.updateBackingSize()
            NSApp.activate(ignoringOtherApps: true)
            account.library.displayVideo = { [weak self] source in
                guard let self, let view = self.videoView, let renderer = self.renderer else { return }
                self.hidePlaybackSettings()
                self.playback?.stop()
                self.playback = nil
                renderer.play(source, in: view)
                view.sourceName = source == nil ? "1920×1080" : "xCloud H.264"
                view.updateBackingSize()
                self.diagnostics.showMessage(source == nil ? "Cloud session ended" : "Connecting cloud video…")
                if source != nil {
                    self.playbackPresentation?.showWindowed()
                } else {
                    self.hidePlaybackWindow()
                }
            }
            account.library.showPlaybackSettings = { [weak self] in self?.showPlaybackSettings() }
            account.library.settingsGamepad = { [weak self] state in self?.playbackSettings.gamepad(state) }
            account.restore()
            showCloudLibrary()
        } catch {
            let alert = NSAlert()
            alert.messageText = "Unable to start XFrame"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .critical
            alert.runModal()
            NSApp.terminate(nil)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard account.library.ownsSession else { return .terminateNow }
        showCloudLibrary()
        let alert = NSAlert()
        alert.messageText = "End the cloud session before quitting"
        alert.informativeText = "Use End Session and wait for confirmation. This avoids leaving a cloud console occupied."
        alert.runModal()
        return .terminateCancel
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showCloudLibrary()
        return true
    }
    func applicationWillTerminate(_ notification: Notification) {
        if let keyboardMonitor { NSEvent.removeMonitor(keyboardMonitor) }
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        playback?.stop(); account.cancel()
    }
    @objc private func systemWillSleep(_ notification: Notification) { account.library.systemWillSleep() }
    @objc private func systemDidWake(_ notification: Notification) { account.library.systemDidWake() }

    @objc private func showXboxAccount() {
        showCloudLibrary()
        account.showingAccount = account.hasCloudAccess
    }

    @objc private func showCloudLibrary() {
        if libraryWindow == nil {
            let controller = NSHostingController(rootView: CloudLibraryView(library: account.library, account: account))
            let window = NSWindow(contentViewController: controller)
            window.title = "XFrame — Cloud Games"
            window.appearance = NSAppearance(named: .darkAqua)
            window.titlebarAppearsTransparent = true
            window.backgroundColor = NSColor(red: 0.055, green: 0.067, blue: 0.075, alpha: 1)
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.isReleasedWhenClosed = false
            WindowPlacement.restore(window, name: "XFrame.Library.v1",
                                    preferredContentSize: NSSize(width: 1240, height: 820))
            libraryWindow = window
        }
        libraryWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func openVideo() {
        guard !account.library.ownsSession else { showCloudLibrary(); return }
        // A canceled picker must not reveal an otherwise unused rendering window.
        showCloudLibrary()
        guard let libraryWindow else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.mpeg4Movie, .quickTimeMovie]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.beginSheetModal(for: libraryWindow) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.play(url)
        }
    }

    private func play(_ url: URL) {
        guard !account.library.ownsSession else { return }
        guard let renderer, let videoView else { return }
        hidePlaybackSettings()
        playback?.stop()
        let source = LocalVideo(url: url)
        playback = source
        lastURL = url
        diagnostics.showMessage("Loading \(url.lastPathComponent)…")
        videoView.sourceName = url.lastPathComponent
        videoView.updateBackingSize()
        renderer.play(source, in: videoView)
        playbackPresentation?.showWindowed()
    }

    @objc private func replayVideo() { if let lastURL { play(lastURL) } }

    @objc private func showTestPattern() {
        guard !account.library.ownsSession else { account.library.end(); return }
        guard let renderer, let videoView else { return }
        playback?.stop()
        playback = nil
        renderer.play(nil, in: videoView)
        videoView.sourceName = "1920×1080"
        videoView.updateBackingSize()
        diagnostics.showMessage("Test pattern · Command-O to open an H.264 video")
        playbackPresentation?.showWindowed()
    }

    private func hidePlaybackWindow() {
        hidePlaybackSettings()
        playbackPresentation?.hide()
        showCloudLibrary()
    }

    func windowDidBecomeKey(_ notification: Notification) { updateControllerFocus() }
    func windowDidResignKey(_ notification: Notification) { account.library.playbackFocused = false; hidePlaybackSettings() }
    func applicationDidBecomeActive(_ notification: Notification) { updateControllerFocus() }
    func applicationDidResignActive(_ notification: Notification) { account.library.playbackFocused = false; hidePlaybackSettings() }
    private func updateControllerFocus() {
        account.library.playbackFocused = NSApp.isActive && window?.isKeyWindow == true
    }
    @objc private func toggleControllerInput(_ sender: NSMenuItem) {
        account.library.controllerEnabled.toggle()
        refreshInputMenu()
    }
    @objc private func toggleKeyboardInput(_ sender: NSMenuItem) {
        account.library.keyboardEnabled.toggle()
        refreshInputMenu()
    }
    private func refreshInputMenu() {
        controllerMenuItem?.state = account.library.controllerEnabled ? .on : .off
        keyboardMenuItem?.state = account.library.keyboardEnabled ? .on : .off
    }
    @objc private func showKeyboardControls() {
        let alert = NSAlert()
        alert.messageText = "Keyboard Controls"
        alert.informativeText = KeyboardGamepad.controls
        alert.runModal()
    }
    private func handleKeyboard(_ event: NSEvent) -> NSEvent? {
        if !playbackSettings.isHidden, event.window === window, window?.isKeyWindow == true {
            // Keep app/system shortcuts available. Consume all ordinary game keys,
            // including key-up, while settings owns local input.
            if !event.modifierFlags.intersection([.command, .control, .option]).isEmpty { return event }
            if event.type == .keyDown && (!event.isARepeat || [125, 126].contains(event.keyCode)) {
                _ = playbackSettings.key(event.keyCode)
            }
            return nil
        }
        guard account.library.keyboardEnabled, account.library.ready,
              NSApp.isActive, let window, event.window === window, window.isKeyWindow,
              window.attachedSheet == nil else { return event }
        let shortcut = !event.modifierFlags.intersection([.command, .control, .option]).isEmpty
        if event.type == .flagsChanged {
            if shortcut { account.library.releaseKeyboard() }
            return event
        }
        let consumed = account.library.keyboardEvent(code: event.keyCode, down: event.type == .keyDown,
            repeatKey: event.isARepeat, shortcut: shortcut)
        return consumed ? nil : event
    }

    func windowDidResize(_ notification: Notification) { refreshVideoView() }
    func applicationDidChangeScreenParameters(_ notification: Notification) {
        for window in [window, libraryWindow].compactMap({ $0 }) {
            WindowPlacement.keepVisible(window)
        }
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if account.library.ownsSession { account.library.end(); showCloudLibrary(); return false }
        playback?.stop()
        playback = nil
        if let renderer, let videoView { renderer.play(nil, in: videoView) }
        hidePlaybackWindow()
        return false
    }
    func windowWillEnterFullScreen(_ notification: Notification) {
        playbackPresentation?.willTransitionFullScreen()
    }
    func windowWillExitFullScreen(_ notification: Notification) {
        playbackPresentation?.willTransitionFullScreen()
    }
    func windowDidEnterFullScreen(_ notification: Notification) {
        playbackPresentation?.didTransitionFullScreen()
        refreshVideoView()
    }
    func windowDidExitFullScreen(_ notification: Notification) {
        playbackPresentation?.didTransitionFullScreen()
        refreshVideoView()
    }
    func windowDidFailToEnterFullScreen(_ window: NSWindow) {
        playbackPresentation?.failedTransitionFullScreen()
    }
    func windowDidFailToExitFullScreen(_ window: NSWindow) {
        playbackPresentation?.failedTransitionFullScreen()
        diagnostics.showMessage("Unable to exit full screen. Use Control-Command-F, then retry.")
    }
    func windowDidChangeScreen(_ notification: Notification) { refreshVideoView() }

    private func refreshVideoView() {
        guard let view = videoView else { return }
        renderer?.invalidate()
        view.updateBackingSize()
        view.draw()
    }

    @objc private func cyclePerformanceHUD() { setPerformanceHUD(hudPreset.next) }
    @objc private func selectPerformanceHUD(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String,
              let preset = PerformanceHUDPreset(rawValue: value) else { return }
        setPerformanceHUD(preset)
    }
    private func setPerformanceHUD(_ preset: PerformanceHUDPreset) {
        hudPreset = preset
        playbackSettings.update(scaling: scalingMode, hud: preset)
        diagnostics.preset = preset
        UserDefaults.standard.set(preset.rawValue, forKey: "XFrame.PerformanceHUD")
        for item in hudMenuItems {
            item.state = item.representedObject as? String == preset.rawValue ? .on : .off
        }
    }

    @objc private func selectScaling(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String, let mode = VideoScalingMode(rawValue: value) else { return }
        setScaling(mode)
    }
    private func setScaling(_ mode: VideoScalingMode) {
        scalingMode = mode
        playbackSettings.update(scaling: mode, hud: hudPreset)
        UserDefaults.standard.set(mode.rawValue, forKey: VideoScalingMode.preferenceKey)
        renderer?.scalingMode = mode
        for item in scalingMenuItems { item.state = item.representedObject as? String == mode.rawValue ? .on : .off }
        videoView?.needsDisplay = true
        videoView?.draw()
    }

    private func togglePlaybackSettings() {
        if playbackSettings.isHidden { showPlaybackSettings() } else { hidePlaybackSettings() }
    }
    private func showPlaybackSettings() {
        guard window?.isVisible == true, window?.isKeyWindow == true else { return }
        account.library.playbackSettingsVisible = true
        playbackSettings.show(scaling: scalingMode, hud: hudPreset)
    }
    private func hidePlaybackSettings() {
        guard !playbackSettings.isHidden else { return }
        playbackSettings.isHidden = true
        account.library.playbackSettingsVisible = false
    }

    private func installMenu() {
        let menu = NSMenu()
        let appItem = menu.addItem(withTitle: "XFrame", action: nil, keyEquivalent: "")
        let appMenu = NSMenu(title: "XFrame")
        appMenu.addItem(withTitle: "Quit XFrame", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        let fileItem = menu.addItem(withTitle: "File", action: nil, keyEquivalent: "")
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "Open Video…", action: #selector(openVideo), keyEquivalent: "o").target = self
        fileMenu.addItem(withTitle: "Replay Video", action: #selector(replayVideo), keyEquivalent: "r").target = self
        fileMenu.addItem(withTitle: "Stop and Show Test Pattern", action: #selector(showTestPattern), keyEquivalent: "0").target = self
        fileItem.submenu = fileMenu
        let accountItem = menu.addItem(withTitle: "Account", action: nil, keyEquivalent: "")
        let accountMenu = NSMenu(title: "Account")
        let signIn = accountMenu.addItem(withTitle: "Xbox Account…", action: #selector(showXboxAccount), keyEquivalent: "a")
        signIn.keyEquivalentModifierMask = [.command, .shift]
        signIn.target = self
        accountItem.submenu = accountMenu
        let games = accountMenu.addItem(withTitle: "Cloud Games…", action: #selector(showCloudLibrary), keyEquivalent: "g")
        games.keyEquivalentModifierMask = [.command, .shift]
        games.target = self
        let viewItem = menu.addItem(withTitle: "View", action: nil, keyEquivalent: "")
        let viewMenu = NSMenu(title: "View")
        let scalingItem = viewMenu.addItem(withTitle: "Video Scaling", action: nil, keyEquivalent: "")
        let scalingMenu = NSMenu(title: "Video Scaling")
        scalingItem.submenu = scalingMenu
        for mode in VideoScalingMode.allCases {
            let item = scalingMenu.addItem(withTitle: mode.title, action: #selector(selectScaling(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            item.state = mode == scalingMode ? .on : .off
            scalingMenuItems.append(item)
        }
        let fullScreen = viewMenu.addItem(withTitle: "Toggle Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        fullScreen.keyEquivalentModifierMask = [.control, .command]
        controllerMenuItem = viewMenu.addItem(withTitle: "Enable Controller Input", action: #selector(toggleControllerInput(_:)), keyEquivalent: "")
        controllerMenuItem?.target = self
        keyboardMenuItem = viewMenu.addItem(withTitle: "Enable Keyboard Input", action: #selector(toggleKeyboardInput(_:)), keyEquivalent: "")
        keyboardMenuItem?.target = self
        refreshInputMenu()
        viewMenu.addItem(withTitle: "Keyboard Controls…", action: #selector(showKeyboardControls), keyEquivalent: "").target = self
        let cycle = viewMenu.addItem(withTitle: "Cycle Performance Overlay", action: #selector(cyclePerformanceHUD), keyEquivalent: "d")
        cycle.keyEquivalentModifierMask = [.command, .shift]
        cycle.target = self
        let performance = NSMenu(title: "Performance Overlay")
        let presets = viewMenu.addItem(withTitle: "Performance Overlay", action: nil, keyEquivalent: "")
        presets.submenu = performance
        for preset in PerformanceHUDPreset.allCases {
            let item = performance.addItem(withTitle: preset.title, action: #selector(selectPerformanceHUD(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = preset.rawValue
            item.state = preset == hudPreset ? .on : .off
            hudMenuItems.append(item)
        }
        viewItem.submenu = viewMenu
        NSApp.mainMenu = menu
    }
}

@MainActor
final class MetalView: MTKView {
    var sourceName = "1920×1080"
    var showPlaybackSettings: (() -> Void)?
    var dismissPlaybackSettings: (() -> Void)?
    override func mouseDown(with event: NSEvent) { dismissPlaybackSettings?() }
    override func rightMouseDown(with event: NSEvent) { showPlaybackSettings?() }
    override init(frame: NSRect, device: (any MTLDevice)?) {
        super.init(frame: frame, device: device)
        autoresizingMask = [.width, .height]
        colorPixelFormat = .bgra8Unorm
        colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        clearColor = MTLClearColorMake(0, 0, 0, 1)
        framebufferOnly = true
        autoResizeDrawable = true
        isPaused = true
        enableSetNeedsDisplay = true
    }

    required init(coder: NSCoder) { fatalError("Storyboard initialization is unsupported.") }

    override func layout() {
        super.layout()
        updateBackingSize()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateBackingSize()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateBackingSize()
    }

    func updateBackingSize() {
        let pixels = convertToBacking(bounds).size
        guard pixels.width > 0, pixels.height > 0 else { return }
        let resized = drawableSize != pixels
        if resized { drawableSize = pixels }
        let title = "XFrame — \(sourceName) · View \(Int(bounds.width))×\(Int(bounds.height)) pt · Canvas \(Int(pixels.width))×\(Int(pixels.height)) px"
        if window?.title != title { window?.title = title }
        if resized { needsDisplay = true }
    }
}
