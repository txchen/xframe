import AppKit

enum PerformanceHUDPreset: String, CaseIterable {
    case compact, detailed, hidden
    var next: Self {
        switch self { case .compact: .detailed; case .detailed: .hidden; case .hidden: .compact }
    }
    var title: String { rawValue.capitalized }
}

enum PerformanceHUDText {
    static func render(_ stats: PlaybackStats, preset: PerformanceHUDPreset, controller: String, quality: CloudStreamQuality? = nil) -> String {
        guard preset != .hidden else { return "" }
        func decimal(_ value: Double?) -> String {
            guard let value, value.isFinite, value >= 0 else { return "n/a" }
            return String(format: "%.1f", value)
        }
        func count(_ value: Int?) -> String { value.map(String.init) ?? "n/a" }
        let decode = decimal(stats.elapsed > 0 ? Double(stats.decoded) / stats.elapsed : nil)
        let present = decimal(stats.elapsed > 0 ? Double(stats.presented) / stats.elapsed : nil)
        let bitrate = decimal(stats.videoBitrateMbps)
        let average = "SESSION avg IN \(decode) · OUT \(present) fps"
        let rate = stats.isLive ? "STREAM \(decimal(stats.recentDecodedFPS)) · OUT \(decimal(stats.recentPresentedFPS)) fps · 2s" : average
        let profile = quality.map { $0 == .hq ? "HQ" : $0 == .low720 ? "720p" : "SQ" } ?? "n/a"
        let video = stats.isLive ? "\(profile) requested · VIDEO \(bitrate) Mbps · \(stats.hardware ? "HW" : "HW pending")" : "LOCAL VIDEO · \(stats.hardware ? "HW" : "HW pending")"
        let recovery = stats.connectionRecovering ? "Connection interrupted — recovering…\n" : ""
        if preset == .compact {
            return recovery + "\(rate)\n\(video)" + (stats.isLive ? "\nLatency est. \(decimal(stats.pipelineLatencyEstimateMS)) ms" : "")
        }
        let volume = stats.audioVolume.isFinite ? Int(min(1, max(0, stats.audioVolume)) * 100) : 0
        let timing = stats.timings
        let stages = [timing.decode, timing.frameWait, timing.gpuQueue, timing.gpu, timing.displayWait, timing.presentation]
            .map { decimal($0?.p95MS) }.joined(separator: " / ")
        var lines = [stats.state, rate + " · Game FPS not measured", video,
            "FRAMES skipped total \(stats.dropped) · queue \(stats.queued)/\(stats.capacity) · errors \(stats.decodeErrors)",
            "P95 ms decode / wait / GPU queue / GPU / display wait / present  \(stages)"]
        lines += ["MEAN ms queue / GPU queue / GPU / display  " + [timing.frameWait, timing.gpuQueue, timing.gpu, timing.displayWait].map { decimal($0?.meanMS) }.joined(separator: " / "),
            "LOCAL present mean \(decimal(timing.presentation?.meanMS)) ms · p95 \(decimal(timing.presentation?.p95MS)) ms"]
        if !stats.isLive { lines += ["TOTAL in \(stats.decoded) · out \(stats.presented)"] }
        if stats.isLive {
            lines += ["PACING \(stats.framePacing.title)", "Latency est. \(decimal(stats.pipelineLatencyEstimateMS)) ms · network + client only",
                "RTT \(decimal(stats.networkRoundTripMS)) ms · buffer \(decimal(stats.jitterBufferMS)) ms · host delay not measured"]
            let pacing = timing.pacing
            lines += [average, "TOTAL in \(stats.decoded) · out \(stats.presented) · ticks \(pacing.drawTicks)",
                "SKIP inbox \(pacing.inboxReplaced) · renderer \(pacing.rendererReplaced) · busy \(pacing.busyTicks) · drawable \(pacing.drawableMisses) · not shown \(pacing.notPresented)",
                "P95 ms arrival / draw / drawable \(decimal(pacing.arrivalInterval?.p95MS)) / \(decimal(pacing.drawInterval?.p95MS)) / \(decimal(pacing.drawableWait?.p95MS))"]
            lines += ["NET packets \(count(stats.videoPacketsReceived)) · lost \(count(stats.videoPacketsLost)) · NACK \(count(stats.videoNacks))",
                "DECODE recovery skips \(stats.recoverySkippedFrames) · IDR \(stats.keyframeSubmissions) · errors pre/sync/async \(stats.errorsBeforeFirstFrame)/\(stats.synchronousDecodeErrors)/\(stats.asynchronousDecodeErrors)",
                "AUDIO \(!stats.audioAttached ? "waiting" : (stats.audioMuted ? "muted" : "on")) · volume \(volume)%",
                controller]
        }
        return recovery + lines.joined(separator: "\n")
    }
}

@MainActor
final class PerformanceHUDView: NSView {
    private var document: HUDDocument?
    private var history = HUDHistory()
    private var message = "Command-O to open a video"
    private var quality: CloudStreamQuality?
    private var controller = ""
    var scaling: ScalingStatus? { didSet { needsDisplay = true } }
    var preset: PerformanceHUDPreset = .compact {
        didSet {
            isHidden = preset == .hidden
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.025, alpha: 0.82).cgColor
        layer?.cornerRadius = 8
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        toolTip = "FPS describes received/displayed video, not game rendering. Local timings exclude network and host latency."
    }
    required init?(coder: NSCoder) { fatalError("Storyboard initialization is unsupported.") }
    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize {
        NSSize(width: 310, height: preset == .detailed ? 604 : 282)
    }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func update(_ document: HUDDocument, controller: String, quality: CloudStreamQuality? = nil) {
        self.document = document
        self.quality = quality
        self.controller = controller.components(separatedBy: " · sent ").first ?? controller
        history.append(document)
        toolTip = document.state + "\nFPS is video cadence, not game FPS. Latency estimate covers network + client only, not input-to-photon."
        setAccessibilityValue(document.accessibilityText + "\n" + (scaling?.title ?? "") + "\n" + controller)
        needsDisplay = true
    }

    func showMessage(_ message: String) {
        document = nil
        history = HUDHistory()
        self.message = message
        setAccessibilityValue(message)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard preset != .hidden else { return }
        // Keep the panel inside small playback windows without relaying out rows.
        let scale = min(1, max(0.01, bounds.height / intrinsicContentSize.height))
        let context = NSGraphicsContext.current?.cgContext
        context?.saveGState()
        defer { context?.restoreGState() }
        context?.scaleBy(x: scale, y: scale)
        let width = bounds.width / scale
        let inset: CGFloat = 14
        let accent = NSColor(calibratedRed: 0.38, green: 0.88, blue: 0.78, alpha: 1)
        func text(_ value: String, x: CGFloat, y: CGFloat, w: CGFloat, color: NSColor,
                  size: CGFloat = 11, right: Bool = false) {
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = right ? .right : .left
            paragraph.lineBreakMode = .byTruncatingTail
            (value as NSString).draw(in: NSRect(x: x, y: y, width: max(0, w), height: 18),
                withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: size, weight: .medium),
                                 .foregroundColor: color, .paragraphStyle: paragraph])
        }
        text("XFRAME", x: inset, y: 13, w: 100, color: accent, size: 12)
        let profile = quality.map { $0 == .hq ? "HQ req." : $0 == .low720 ? "720p req." : "SQ req." } ?? "LIVE"
        let failed = document?.state.hasPrefix("Failed:") == true
        let status = failed ? "FAILED" : (document?.state == "Ended" ? "ENDED" : nil)
        text(status ?? (document?.recovering == true ? "RECOVERING" : (document?.live == true ? profile + (document?.hardware == true ? " · HW" : "") : "LOCAL VIDEO")),
             x: 110, y: 14, w: width - 124, color: document?.recovering == true ? .systemOrange : NSColor(calibratedWhite: 0.55, alpha: 1), right: true)
        guard let document else {
            text(message, x: inset, y: 48, w: width - 28, color: .white)
            return
        }
        var y: CGFloat = 42
        let visibleRows = preset == .compact ? Array(document.rows.prefix(6)) : document.rows
        for row in visibleRows {
            let section = row.name == "LOCAL PIPELINE" || row.name == "STREAM HEALTH"
            if section { y += 9 }
            text(row.name, x: inset, y: y, w: width * 0.57 - inset,
                 color: section ? accent : NSColor(calibratedWhite: 0.72, alpha: 1), size: section ? 10 : 11)
            text(row.value, x: width * 0.57, y: y, w: width * 0.43 - inset,
                 color: section ? NSColor(calibratedWhite: 0.55, alpha: 1) : .white, size: section ? 10 : 11, right: true)
            y += 19
        }
        y += 10
        text(document.live ? "OUTPUT FPS · 2s samples · 30s history" : "OUTPUT FPS · session average · 30s",
             x: inset, y: y, w: width - 28, color: NSColor(calibratedWhite: 0.55, alpha: 1), size: 9)
        let chart = NSRect(x: inset, y: y + 20, width: max(1, width - 28), height: 40)
        let grid = NSBezierPath()
        for i in 0...4 {
            let x = chart.minX + chart.width * CGFloat(i) / 4
            grid.move(to: NSPoint(x: x, y: chart.minY))
            grid.line(to: NSPoint(x: x, y: chart.maxY))
        }
        for edge in [chart.minY, chart.maxY] {
            grid.move(to: NSPoint(x: chart.minX, y: edge))
            grid.line(to: NSPoint(x: chart.maxX, y: edge))
        }
        NSColor.white.withAlphaComponent(0.12).setStroke()
        grid.lineWidth = 0.5
        grid.stroke()
        let ceiling = max(60, history.points.map(\.fps).max() ?? 60)
        let line = NSBezierPath()
        var previous: TimeInterval?
        for point in history.points {
            let x = chart.maxX - CGFloat((document.sampledAt - point.time) / 30) * chart.width
            let p = NSPoint(x: x, y: chart.maxY - CGFloat(point.fps / ceiling) * chart.height)
            if let previous, point.time - previous < 2 { line.line(to: p) }
            else { line.move(to: p) }
            previous = point.time
        }
        accent.setStroke()
        line.lineWidth = 1.3
        line.stroke()
        text(scaling?.title ?? "Original scaling", x: inset, y: chart.maxY + 10, w: width - 28,
             color: .white, size: 10)
        text("Video FPS ≠ game FPS", x: inset, y: chart.maxY + 28, w: width - 28,
             color: NSColor(calibratedWhite: 0.55, alpha: 1), size: 9)
        if preset == .detailed {
            text(controller, x: inset, y: chart.maxY + 46, w: width - 28,
                 color: NSColor(calibratedWhite: 0.55, alpha: 1), size: 9)
        }
    }
}
