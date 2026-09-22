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
        let profile = quality.map { $0 == .hq ? "HQ" : "SQ" } ?? "n/a"
        let video = stats.isLive ? "\(profile) requested · VIDEO \(bitrate) Mbps · \(stats.hardware ? "HW" : "HW pending")" : "LOCAL VIDEO · \(stats.hardware ? "HW" : "HW pending")"
        let recovery = stats.connectionRecovering ? "Connection interrupted — recovering…\n" : ""
        if preset == .compact {
            return recovery + "\(rate)\n\(video)" + (stats.isLive ? "\nLatency est. \(decimal(stats.pipelineLatencyEstimateMS)) ms" : "")
        }
        let volume = stats.audioVolume.isFinite ? Int(min(1, max(0, stats.audioVolume)) * 100) : 0
        let timing = stats.timings
        let stages = [timing.decode, timing.frameWait, timing.gpu, timing.presentation]
            .map { decimal($0?.p95MS) }.joined(separator: " / ")
        var lines = [stats.state, rate + " · Game FPS not measured", video,
            "FRAMES skipped total \(stats.dropped) · queue \(stats.queued)/\(stats.capacity) · errors \(stats.decodeErrors)",
            "P95 ms decode / wait / GPU / present  \(stages)"]
        if stats.isLive {
            lines += ["PACING \(stats.framePacing.title)", "Latency est. \(decimal(stats.pipelineLatencyEstimateMS)) ms · network + client only",
                "RTT \(decimal(stats.networkRoundTripMS)) ms · buffer \(decimal(stats.jitterBufferMS)) ms · host delay not measured"]
            lines += ["MEAN ms queue / GPU queue / GPU / display  " + [timing.frameWait, timing.gpuQueue, timing.gpu, timing.displayWait].map { decimal($0?.meanMS) }.joined(separator: " / "),
                "LOCAL present mean \(decimal(timing.presentation?.meanMS)) ms · p95 \(decimal(timing.presentation?.p95MS)) ms"]
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
    private let label = NSTextField(labelWithString: "")
    private var stats: PlaybackStats?
    private var controller = ""
    private var quality: CloudStreamQuality?
    private var message = "Test pattern · Command-O to open an H.264 video"
    var preset: PerformanceHUDPreset = .compact { didSet { refresh() } }

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.28).cgColor
        layer?.cornerRadius = 6
        label.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        label.textColor = .white
        label.maximumNumberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.translatesAutoresizingMaskIntoConstraints = false
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.85)
        shadow.shadowBlurRadius = 2
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        label.shadow = shadow
        label.toolTip = "SQ/HQ is the requested session profile, not proof of negotiated quality. Latency estimate adds network RTT, receiver buffer, decode and local presentation means. Host rendering/encoding and input/display hardware delay are not measured; this is not full input-to-photon latency."
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6)
        ])
        refresh()
    }
    required init?(coder: NSCoder) { fatalError("Storyboard initialization is unsupported.") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func update(_ stats: PlaybackStats, controller: String, quality: CloudStreamQuality? = nil) {
        self.quality = quality
        self.stats = stats
        self.controller = controller
        refresh()
    }
    func showMessage(_ message: String) {
        stats = nil
        self.message = message
        refresh()
    }
    private func refresh() {
        isHidden = preset == .hidden
        guard !isHidden else { return }
        let text = stats.map { PerformanceHUDText.render($0, preset: preset, controller: controller, quality: quality) } ?? message
        if label.stringValue != text { label.stringValue = text }
    }
}
