import Foundation
import SwiftUI
import UniformTypeIdentifiers

// Explicit allowlist. Never encode PlaybackStats directly: its state may contain
// free-form errors. No account, title, URL, SDP, IP address or media is exported.
struct StreamDiagnosticReport: Encodable, Sendable {
    enum Outcome: String, Encodable, Sendable { case active, stopped, failed }
    struct Video: Encodable, Sendable {
        let hardware: Bool
        let decoded, presented, skipped, queued, peakQueue: Int
        let decodeErrors, recoverySkips, errorsBeforeFirstFrame: Int
        let configurations, idrSubmissions, missingFrameSignals: Int
        let synchronousErrors, asynchronousErrors, idrErrors: Int
        let packetsReceived, packetsLost, nacks: Int?
    }
    struct Audio: Encodable, Sendable {
        let attached, muted: Bool
        let volume: Double
        let packetsReceived: Int?
        let energy: Double?
    }
    let schemaVersion = 1
    let outcome: Outcome
    let durationSeconds: Double
    let video: Video
    let audio: Audio
    let events: [StreamDiagnosticEvent]

    init(stats: PlaybackStats, outcome: Outcome, duration: Double, events: [StreamDiagnosticEvent]) {
        self.outcome = outcome
        durationSeconds = duration.isFinite ? max(0, duration) : 0
        video = Video(hardware: stats.hardware, decoded: stats.decoded, presented: stats.presented,
            skipped: stats.dropped, queued: stats.queued, peakQueue: stats.peakQueue,
            decodeErrors: stats.decodeErrors, recoverySkips: stats.recoverySkippedFrames,
            errorsBeforeFirstFrame: stats.errorsBeforeFirstFrame, configurations: stats.decoderConfigurations,
            idrSubmissions: stats.keyframeSubmissions, missingFrameSignals: stats.missingFrameSignals,
            synchronousErrors: stats.synchronousDecodeErrors, asynchronousErrors: stats.asynchronousDecodeErrors,
            idrErrors: stats.keyframeDecodeErrors, packetsReceived: stats.videoPacketsReceived,
            packetsLost: stats.videoPacketsLost, nacks: stats.videoNacks)
        audio = Audio(attached: stats.audioAttached, muted: stats.audioMuted,
            volume: stats.audioVolume.isFinite ? min(1, max(0, stats.audioVolume)) : 0,
            packetsReceived: stats.audioPacketsReceived,
            energy: stats.audioEnergy.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil })
        self.events = Array(events.suffix(LiveVideo.eventLimit))
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}

struct StreamDiagnosticDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    let data: Data
    init(report: StreamDiagnosticReport) throws { data = try report.encoded() }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
