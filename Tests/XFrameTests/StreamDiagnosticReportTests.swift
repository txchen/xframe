import Foundation
import Testing
@testable import XFrame

@Test func diagnosticExportUsesAnExplicitAllowlist() throws {
    var stats = PlaybackStats()
    stats.state = "SECRET_TOKEN https://private.example/session account-name SDP"
    stats.decoded = 123
    stats.audioPacketsReceived = 45
    stats.audioEnergy = 0.2
    let report = StreamDiagnosticReport(stats: stats, outcome: .stopped, duration: 10, events: [])
    let data = try report.encoded()
    let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(Set(json.keys) == ["schemaVersion", "outcome", "durationSeconds", "video", "audio", "events", "timings", "framePacing"])
    #expect(json["schemaVersion"] as? Int == 6)
    let video = try #require(json["video"] as? [String: Any])
    #expect(video["decoded"] as? Int == 123)
    #expect(video["packetsLost"] == nil)
    let audio = try #require(json["audio"] as? [String: Any])
    #expect(audio["packetsReceived"] as? Int == 45)
    let text = String(decoding: data, as: UTF8.self)
    for forbidden in ["SECRET_TOKEN", "private.example", "account-name", "SDP", "state"] {
        #expect(!text.contains(forbidden))
    }
}

@Test func diagnosticExportBoundsEventsAndSanitizesNonFiniteNumbers() throws {
    var stats = PlaybackStats()
    stats.audioVolume = .nan
    stats.audioEnergy = .infinity
    let events = (0..<300).map {
        StreamDiagnosticEvent(milliseconds: $0, kind: .configured, configuration: $0,
            accessUnit: nil, synchronous: nil, keyframe: nil, packetsLost: nil, nacks: nil)
    }
    let report = StreamDiagnosticReport(stats: stats, outcome: .active, duration: .infinity, events: events)
    #expect(report.events.count == 128)
    #expect(report.events.first?.milliseconds == 172)
    #expect(report.durationSeconds == 0)
    #expect(report.audio.volume == 0)
    #expect(report.audio.energy == nil)
    #expect(try !report.encoded().isEmpty)
}

@Test func terminalStreamReportIsStableAndRetainsFailureOutcome() throws {
    let source = LiveVideo()
    source.decoderConfigured()
    source.networkSample(received: 100, lost: 1, nacks: 2)
    source.fail("sensitive error text must not be exported")
    source.stop()
    let first = source.diagnosticReport()
    source.didPresent()
    source.hardwareVerified()
    source.fail("late error")
    source.audioPlayback(attached: true, muted: false, volume: 1)
    source.networkSample(received: 200, lost: 2, nacks: 3)
    source.stop()
    let second = source.diagnosticReport()
    #expect(first.outcome == .failed)
    #expect(first.durationSeconds == second.durationSeconds)
    #expect(try first.encoded() == second.encoded())
    #expect(first.video.packetsReceived == 100)
    #expect(!String(decoding: try first.encoded(), as: UTF8.self).contains("sensitive"))
}

@Test func stoppedStreamReportRoundTripsThroughAFile() throws {
    let source = LiveVideo()
    source.stop()
    let report = source.diagnosticReport()
    #expect(report.outcome == .stopped)
    let document = try StreamDiagnosticDocument(report: report)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("diagnostics.json")
    try document.data.write(to: file, options: .atomic)
    #expect(try Data(contentsOf: file) == report.encoded())
    #expect(try JSONSerialization.jsonObject(with: Data(contentsOf: file)) is [String: Any])
}
