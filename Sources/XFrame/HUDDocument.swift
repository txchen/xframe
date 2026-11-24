import Foundation

// Prepared away from the main actor; the view only paints immutable strings.
struct HUDDocument: Sendable {
    struct Row: Sendable {
        let name: String
        let value: String
    }
    let rows: [Row]
    let accessibilityText: String
    let outputFPS: Double?
    let sampledAt: TimeInterval
    let recovering: Bool
    let live: Bool
    let hardware: Bool
    let state: String

    init(stats s: PlaybackStats, preset: PerformanceHUDPreset,
         sampledAt: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        func n(_ v: Double?, _ unit: String = "") -> String {
            guard let v, v.isFinite, v >= 0 else { return "—" }
            return String(format: "%.1f", v) + unit
        }
        func count(_ v: Int?) -> String { v.map(String.init) ?? "—" }
        let out = s.isLive ? s.recentPresentedFPS : (s.elapsed > 0 ? Double(s.presented) / s.elapsed : nil)
        let input = s.isLive ? s.recentDecodedFPS : (s.elapsed > 0 ? Double(s.decoded) / s.elapsed : nil)
        var rows: [Row] = [
            Row(name: s.isLive ? "Stream · 2s" : "Input · session", value: n(input, " fps")),
            Row(name: s.isLive ? "Output · 2s" : "Output · session", value: n(out, " fps")),
            Row(name: "Video bitrate", value: n(s.videoBitrateMbps, " Mbps")),
            Row(name: "GPU · mean", value: n(s.timings.gpu?.meanMS, " ms")),
            Row(name: "Network RTT", value: n(s.networkRoundTripMS, " ms")),
            Row(name: "Net + client · est.", value: n(s.pipelineLatencyEstimateMS, " ms"))
        ]
        if preset == .detailed {
            rows += [
                Row(name: "LOCAL PIPELINE", value: "p95 · ms"),
                Row(name: "Decode", value: n(s.timings.decode?.p95MS)),
                Row(name: "Frame wait", value: n(s.timings.frameWait?.p95MS)),
                Row(name: "GPU queue", value: n(s.timings.gpuQueue?.p95MS)),
                Row(name: "GPU", value: n(s.timings.gpu?.p95MS)),
                Row(name: "Display wait", value: n(s.timings.displayWait?.p95MS)),
                Row(name: "Arrival → display", value: n(s.timings.presentation?.p95MS)),
                Row(name: "STREAM HEALTH", value: s.framePacing.title),
                Row(name: "Skipped · total", value: String(s.dropped)),
                Row(name: "Queue", value: "\(s.queued) / \(s.capacity)"),
                Row(name: "Decode errors", value: String(s.decodeErrors)),
                Row(name: "Packets lost / NACK", value: "\(count(s.videoPacketsLost)) / \(count(s.videoNacks))"),
                Row(name: "Receiver buffer", value: n(s.jitterBufferMS, " ms")),
                Row(name: "Recovery skips / IDR", value: "\(s.recoverySkippedFrames) / \(s.keyframeSubmissions)"),
                Row(name: "Session in / out", value: "\(s.decoded) / \(s.presented)")
            ]
            if s.generatedFrames > 0 {
                rows.append(Row(name: "Generated · total", value: String(s.generatedFrames)))
            }
        }
        self.rows = preset == .hidden ? [] : rows
        accessibilityText = PerformanceHUDText.render(s, preset: preset, controller: "")
        outputFPS = out.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        self.sampledAt = sampledAt
        recovering = s.connectionRecovering
        live = s.isLive
        hardware = s.hardware
        state = s.state
    }
}

struct HUDHistory {
    struct Point { let time: TimeInterval; let fps: Double }
    private(set) var points: [Point] = []
    mutating func append(_ document: HUDDocument) {
        let now = document.sampledAt
        guard now.isFinite else { return }
        if let last = points.last, now <= last.time { return }
        points.removeAll { now - $0.time > 30 }
        if let fps = document.outputFPS { points.append(Point(time: now, fps: fps)) }
        if points.count > 64 { points.removeFirst(points.count - 64) }
    }
}
