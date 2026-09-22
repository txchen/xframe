import Foundation
import CoreVideo
import Testing
@testable import XFrame

private func fixture() throws -> URL {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let url = root.appendingPathComponent(".build/fixtures/h264-1080p60.mp4")
    guard FileManager.default.fileExists(atPath: url.path) else {
        throw RenderError.unavailable("Generate .build/fixtures/h264-1080p60.mp4 using scripts/make-test-video.sh first.")
    }
    return url
}

@Test(arguments: [false, true])
func hardwareDecodeReordersBFramesAndToleratesDisplayJitter(simulateStall: Bool) async throws {
    let video = LocalVideo(url: try fixture())
    defer { video.stop() }
    var tick = 0
    var lastPTS = -Double.infinity
    var received = 0
    let deadline = Date().addingTimeInterval(20)
    while Date() < deadline {
        let stats = video.snapshot()
        #expect(!stats.state.hasPrefix("Failed:"), "\(stats.state)")
        if stats.state.hasPrefix("Failed:") { break }
        if stats.state == "Ended" { break }
        if stats.queued < (received == 0 ? LocalVideo.capacity : 8) && !stats.inputFinished {
            try await Task.sleep(for: .milliseconds(1))
            continue
        }
        let stall = simulateStall && tick >= 60 ? 1.0 : 0.0
        let host = 100.0 + Double(tick) / 60.0 + (tick.isMultiple(of: 2) ? 0.001 : -0.001) + stall
        if let frame = video.nextFrame(at: host) {
            #expect(frame.time > lastPTS)
            #expect(CVPixelBufferGetWidth(frame.buffer) == 1920)
            #expect(CVPixelBufferGetHeight(frame.buffer) == 1080)
            #expect(CVPixelBufferGetPixelFormatType(frame.buffer) == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)
            #expect(CVPixelBufferGetIOSurface(frame.buffer) != nil)
            lastPTS = frame.time
            received += 1
        }
        tick += 1
    }
    let stats = video.snapshot()
    #expect(stats.state == "Ended")
    #expect(stats.hardware)
    #expect(stats.decoded == 720)
    #expect(received + stats.dropped == 720)
    if simulateStall { #expect(stats.dropped > 0) }
    else { #expect(stats.dropped == 0) }
    #expect(stats.peakQueue <= LocalVideo.capacity)
    #expect(stats.queued == 0)
    #expect(stats.presented == 0) // Decoding is not proof of display presentation.
    #expect(stats.timings.decode?.count == 720)
    #expect(stats.timings.gpu == nil)
    if !simulateStall, let timing = stats.timings.decode {
        print("LOCAL_DECODE_BASELINE samples=\(timing.count) recent=\(timing.recentCount) mean_ms=\(timing.meanMS) p95_ms=\(timing.p95MS)")
    }
}

@Test func cancellationReleasesFullQueue() async throws {
    let video = LocalVideo(url: try fixture())
    defer { video.stop() }
    let deadline = Date().addingTimeInterval(5)
    while video.snapshot().queued < LocalVideo.capacity && Date() < deadline {
        try await Task.sleep(for: .milliseconds(5))
    }
    #expect(video.snapshot().queued == LocalVideo.capacity)
    video.stop()
    try await Task.sleep(for: .milliseconds(50))
    #expect(video.snapshot().queued == 0)
    #expect(video.snapshot().state == "Stopped")
}

@Test func missingFileFailsVisibly() async throws {
    let video = LocalVideo(url: URL(fileURLWithPath: "/nonexistent-xframe-test.mp4"))
    defer { video.stop() }
    let deadline = Date().addingTimeInterval(5)
    while !video.snapshot().state.hasPrefix("Failed:") && Date() < deadline {
        try await Task.sleep(for: .milliseconds(5))
    }
    #expect(video.snapshot().state.hasPrefix("Failed:"))
}

@Test func repeatedLocalCancellationReleasesSourceAndQueue() async throws {
    var residentKB: [Int] = []
    for _ in 0..<12 {
        var source: LocalVideo? = LocalVideo(url: try fixture())
        weak let released = source
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while source!.snapshot().queued < LocalVideo.capacity && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(2))
        }
        #expect(source!.snapshot().queued == LocalVideo.capacity)
        source!.stop()
        #expect(source!.snapshot().queued == 0)
        source = nil
        while released != nil && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(2)) }
        #expect(released == nil, "Decode worker must release the stopped source.")
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-o", "rss=", "-p", String(ProcessInfo.processInfo.processIdentifier)]
        process.standardOutput = pipe
        try process.run()
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        if let rss = Int(String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)) {
            residentKB.append(rss)
        }
    }
    print("LOCAL_CANCEL_RSS_KB \(residentKB)") // Observational, not a leak threshold.
}
