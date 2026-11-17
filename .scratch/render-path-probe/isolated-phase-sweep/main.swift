import AppKit
import MetalKit

// Callbacks arrive on different queues; all record storage and pending state use this lock.
final class Recorder: @unchecked Sendable {
    let lock = NSLock()
    private var rows: [[String: Double]] = []
    private var pending: Set<Int> = []
    func event(_ row: [String: Double]) { lock.withLock { rows.append(row) } }
    func count() -> Int { lock.withLock { pending.count } }
    func submit(_ id: Int, _ row: [String: Double]) {
        lock.withLock { pending.insert(id); rows.append(row) }
    }
    func finish(_ id: Int, _ row: [String: Double]) {
        lock.withLock { pending.remove(id); rows.append(row) }
    }
    func snapshot() -> [[String: Double]] { lock.withLock { rows } }
}

@MainActor final class Probe: NSObject, NSApplicationDelegate, NSWindowDelegate, MTKViewDelegate {
    let recorder = Recorder()
    let permits = DispatchSemaphore(value: 3)
    let output = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/RenderPathProbe")
    var window: NSWindow!
    var view: MTKView!
    var queue: (any MTLCommandQueue)!
    var frame = 0
    var tick = 0
    var start: Double?
    var finished = false
    var lastSparse = 0.0
    var lastBlock = -1
    var begun = false
    var status: String = "idle"
    var runDirectory: URL!
    var modes = [0, 1, 1, 0] // continuous / isolated; ABBA avoids a single time-order comparison.
    var blockSeconds = 12.0
    var delayedDraw = false
    var scheduled = false
    var clock: CADisplayLink?
    var refreshTarget = 0.0
    var intended = 0.0
    let warmup = 3.0

    func applicationDidFinishLaunching(_ note: Notification) {
        guard let device = MTLCreateSystemDefaultDevice(), let commandQueue = device.makeCommandQueue() else {
            fatalError("Metal device unavailable")
        }
        queue = commandQueue
        let menu = NSMenu()
        let appMenu = NSMenu(); menu.addItem(withTitle: "Render Path Probe", action: nil, keyEquivalent: "").submenu = appMenu
        appMenu.addItem(withTitle: "Quit Render Path Probe", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let experiment = NSMenu(); menu.addItem(withTitle: "Experiment", action: nil, keyEquivalent: "").submenu = experiment
        let begin = experiment.addItem(withTitle: "Start full-screen ABBA", action: #selector(beginRun), keyEquivalent: "r"); begin.target = self
        let sweep = experiment.addItem(withTitle: "Start isolated phase sweep", action: #selector(beginSweep), keyEquivalent: "p"); sweep.target = self
        let stop = experiment.addItem(withTitle: "Stop and save", action: #selector(stopRun), keyEquivalent: "."); stop.target = self
        NSApp.mainMenu = menu
        view = MTKView(frame: NSRect(x: 0, y: 0, width: 960, height: 540), device: device)
        view.colorPixelFormat = .bgra8Unorm
        view.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        view.framebufferOnly = true
        view.preferredFramesPerSecond = 60
        view.autoResizeDrawable = true
        view.layer?.isOpaque = true
        view.delegate = self
        window = NSWindow(contentRect: view.frame, styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Render Path Probe — ⌘R starts 48-second ABBA"
        window.isReleasedWhenClosed = false
        window.isOpaque = true
        window.backgroundColor = .black
        window.collectionBehavior = [.fullScreenPrimary]
        window.delegate = self
        window.contentView = view
        window.center(); window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func beginSweep() {
        guard !begun else { return }
        modes = [2, 6, 3, 7, 4, 8, 5, 9]
        blockSeconds = 8
        let link = view.displayLink(target: self, selector: #selector(refresh(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        clock = link
        beginRun()
    }
    @objc func refresh(_ link: CADisplayLink) {
        refreshTarget = link.targetTimestamp
        if begun && !finished { recorder.event(["clockCallback": CACurrentMediaTime(), "refreshTimestamp": link.timestamp, "refreshTarget": link.targetTimestamp]) }
    }
    @objc func beginRun() {
        guard !begun else { return }
        begun = true
        let name = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-") + "-" + UUID().uuidString.prefix(8)
        runDirectory = output.appendingPathComponent(name)
        do { try FileManager.default.createDirectory(at: runDirectory, withIntermediateDirectories: true) }
        catch { fail(error.localizedDescription); return }
        status = "waiting-for-fullscreen"
        saveStatus()
        if window.styleMask.contains(.fullScreen) { arm() } else { window.toggleFullScreen(nil) }
    }
    func windowDidEnterFullScreen(_ notification: Notification) { if begun && start == nil { arm() } }
    func windowDidFailToEnterFullScreen(_ window: NSWindow) { fail("Native fullscreen failed; no samples accepted") }
    func windowDidExitFullScreen(_ notification: Notification) { if begun && !finished { fail("Fullscreen exited during run") } }
    func arm() {
        // No UI interaction is needed after arming; no writes occur during measurement.
        start = CACurrentMediaTime() + warmup
        status = "running"
        saveStatus()
    }
    func saveStatus() {
        guard let runDirectory else { return }
        let value: [String: Any] = ["status": status, "run": runDirectory.path, "blockSeconds": blockSeconds, "modes": modes, "warmupSeconds": warmup]
        do { try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]).write(to: runDirectory.appendingPathComponent("status.json"), options: .atomic) }
        catch { NSLog("Status export failed: %@", error.localizedDescription) }
    }
    func fail(_ message: String) { status = "invalid: " + message; finish() }
    @objc func stopRun() { guard begun && !finished else { return }; status = "stopped"; finish() }
    func finish() {
        guard !finished else { return }
        finished = true
        // Stop drawing, allow outstanding callbacks to drain, then serialize once.
        view.isPaused = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.export() }
    }
    func export() {
        guard let runDirectory else { return }
        let screen = window.screen
        let report: [String: Any] = [
            "schema": 1, "status": status, "events": recorder.snapshot(), "pendingAtExport": recorder.count(),
            "device": view.device?.name ?? "unknown", "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "screen": screen?.localizedName ?? "unknown", "screenFrame": NSStringFromRect(screen?.frame ?? .zero),
            "backingScale": window.backingScaleFactor, "drawableSize": NSStringFromSize(view.drawableSize),
            "start": start ?? 0, "blockSeconds": blockSeconds, "modes": modes,
            "syncEnabled": (view.layer as? CAMetalLayer)?.displaySyncEnabled ?? true,
            "maximumDrawableCount": (view.layer as? CAMetalLayer)?.maximumDrawableCount ?? 0,
            "description": "2..9=isolated delayed MTK draw, offsets 0..14ms in 2ms increments; 0=continuous MTK 60; 1=isolated frames >=0.5s apart and zero pending actual presentations. GPU clear only. Sparse mode diagnoses queueing, not a playable scheduler."
        ]
        do {
            try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]).write(to: runDirectory.appendingPathComponent("events.json"), options: .atomic)
            saveStatus()
            window.title = "Render Path Probe — \(status) — \(runDirectory.lastPathComponent)"
        } catch { NSLog("Export failed: %@", error.localizedDescription) }
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if begun && !finished { status = "stopped-on-quit"; finished = true; view.isPaused = true; export() }
        return .terminateNow
    }
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    func draw(in view: MTKView) {
        guard !finished else { return }
        let now = CACurrentMediaTime()
        let elapsed = start.map { now - $0 } ?? -1
        if elapsed >= blockSeconds * Double(modes.count) { status = "complete"; finish(); return }
        let block = elapsed >= 0 ? Int(elapsed / blockSeconds) : -1
        let mode = block >= 0 ? modes[block] : 0
        tick += 1
        let pending = recorder.count()
        if mode >= 2 && !delayedDraw {
            guard !scheduled, pending == 0, now - lastSparse >= 0.5 else { return }
            scheduled = true
            let delay = Double(mode - 2) * 0.002
            intended = now + delay
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                self.scheduled = false
                guard !self.finished else { return }
                self.delayedDraw = true
                self.view.draw()
                self.delayedDraw = false
            }
            return
        }
        if begun { recorder.event(["tick": Double(tick), "time": now, "block": Double(block), "pending": Double(pending), "fullscreen": window.styleMask.contains(.fullScreen) ? 1 : 0]) }
        if block != lastBlock { lastBlock = block; lastSparse = now }
        if mode == 1 && (pending > 0 || now - lastSparse < 0.5) { return }
        guard permits.wait(timeout: .now()) == .success else {
            recorder.event(["time": now, "block": Double(block), "gpuPermitMiss": 1]); return
        }
        let acquire = CACurrentMediaTime()
        guard let drawable = view.currentDrawable, let pass = view.currentRenderPassDescriptor, let command = queue.makeCommandBuffer() else {
            permits.signal(); recorder.event(["time": now, "block": Double(block), "drawableMiss": 1]); return
        }
        let acquired = CACurrentMediaTime()
        frame += 1
        let id = frame
        // Alternating colors expose updates without text/UI overlays or shader compilation.
        pass.colorAttachments[0].clearColor = MTLClearColor(red: id % 2 == 0 ? 0.12 : 0.22, green: mode == 1 ? 0.42 : 0.16, blue: 0.32, alpha: 1)
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { permits.signal(); return }
        encoder.endEncoding()
        let record = recorder; let semaphore = permits
        record.submit(id, ["id": Double(id), "block": Double(block), "mode": Double(mode), "submit": CACurrentMediaTime(), "acquire": acquire, "acquired": acquired, "pendingBefore": Double(pending), "refreshTarget": refreshTarget, "intended": intended, "fullscreen": window.styleMask.contains(.fullScreen) ? 1 : 0])
        command.addCompletedHandler { buffer in
            let row = ["id": Double(id), "gpuStart": buffer.gpuStartTime, "gpuEnd": buffer.gpuEndTime, "gpuCallback": CACurrentMediaTime(), "error": buffer.status == .completed ? 0.0 : 1.0]
            if buffer.status == .completed { record.event(row) } else { record.finish(id, row) }
            semaphore.signal()
        }
        drawable.addPresentedHandler { d in
            record.finish(id, ["id": Double(id), "actual": d.presentedTime, "presentCallback": CACurrentMediaTime()])
        }
        command.present(drawable); command.commit()
        lastSparse = now
    }
}
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = Probe()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()
}
