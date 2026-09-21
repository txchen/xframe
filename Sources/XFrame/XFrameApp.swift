import AppKit
import MetalKit
import UniformTypeIdentifiers

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
    private var renderer: MetalRenderer?
    private var videoView: MetalView?
    private var playback: LocalVideo?
    private var lastURL: URL?
    private let diagnostics = NSTextField(labelWithString: "Test pattern · Command-O to open an H.264 video")

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMenu()
        do {
            guard let device = MTLCreateSystemDefaultDevice() else {
                throw RenderError.unavailable("A Metal-capable GPU is required.")
            }
            let view = MetalView(frame: NSRect(x: 0, y: 0, width: 960, height: 540), device: device)
            let renderer = try MetalRenderer(view: view)
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
            diagnostics.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
            diagnostics.textColor = .white
            diagnostics.backgroundColor = NSColor.black.withAlphaComponent(0.8)
            diagnostics.drawsBackground = true
            diagnostics.maximumNumberOfLines = 3
            diagnostics.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(diagnostics)
            NSLayoutConstraint.activate([
                diagnostics.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
                diagnostics.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
                diagnostics.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -12)
            ])
            renderer.report = { [weak self] stats in
                let decodeRate = stats.elapsed > 0 ? Double(stats.decoded) / stats.elapsed : 0
                let presentRate = stats.elapsed > 0 ? Double(stats.presented) / stats.elapsed : 0
                self?.diagnostics.stringValue = String(format:
                    "%@ · Hardware: %@\nDecode avg %.1f fps · Present avg %.1f fps · Skipped %d · Queue %d/%d",
                    stats.state, stats.hardware ? "Yes" : "Pending",
                    decodeRate, presentRate,
                    stats.dropped, stats.queued, LocalVideo.capacity)
            }
            window.contentView = content
            window.isReleasedWhenClosed = false
            window.center()
            window.makeKeyAndOrderFront(nil)
            self.window = window
            view.updateBackingSize()
            NSApp.activate(ignoringOtherApps: true)
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
    func applicationWillTerminate(_ notification: Notification) { playback?.stop() }

    @objc private func openVideo() {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.mpeg4Movie, .quickTimeMovie]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.play(url)
        }
    }

    private func play(_ url: URL) {
        guard let renderer, let videoView else { return }
        playback?.stop()
        let source = LocalVideo(url: url)
        playback = source
        lastURL = url
        diagnostics.stringValue = "Loading \(url.lastPathComponent)…"
        videoView.sourceName = url.lastPathComponent
        videoView.updateBackingSize()
        renderer.play(source, in: videoView)
    }

    @objc private func replayVideo() { if let lastURL { play(lastURL) } }

    @objc private func showTestPattern() {
        guard let renderer, let videoView else { return }
        playback?.stop()
        playback = nil
        renderer.play(nil, in: videoView)
        videoView.sourceName = "1920×1080"
        videoView.updateBackingSize()
        diagnostics.stringValue = "Test pattern · Command-O to open an H.264 video"
    }

    func windowDidResize(_ notification: Notification) { refreshVideoView() }
    func windowDidEnterFullScreen(_ notification: Notification) { refreshVideoView() }
    func windowDidExitFullScreen(_ notification: Notification) { refreshVideoView() }
    func windowDidChangeScreen(_ notification: Notification) { refreshVideoView() }

    private func refreshVideoView() {
        guard let view = videoView else { return }
        view.updateBackingSize()
        view.draw()
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
        let viewItem = menu.addItem(withTitle: "View", action: nil, keyEquivalent: "")
        let viewMenu = NSMenu(title: "View")
        let fullScreen = viewMenu.addItem(withTitle: "Toggle Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        fullScreen.keyEquivalentModifierMask = [.control, .command]
        viewItem.submenu = viewMenu
        NSApp.mainMenu = menu
    }
}

@MainActor
final class MetalView: MTKView {
    var sourceName = "1920×1080"
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
        if drawableSize != pixels { drawableSize = pixels }
        window?.title = "XFrame — \(sourceName) → \(Int(pixels.width))×\(Int(pixels.height)) px"
        needsDisplay = true
    }
}
