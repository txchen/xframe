import AppKit
import MetalKit
import SwiftUI
import Testing
@testable import XFrame

private actor PreviewCatalog: CloudServing {
    func games() async throws -> [CloudGame] {
        ["33 Immortals", "1000xRESIST", "A Game About Digging A Hole", "Abiotic Factor", "Absolum", "Abyssus", "Age of Empires II", "Alien: Isolation"].enumerated().map {
            CloudGame(id: String($0.offset), name: $0.element, productID: nil, categories: ["Adventure"], access: .init(entitled: true))
        }
    }
    func create(title: String, preferences: CloudStreamPreferences) async throws -> URL { throw CloudError.network }
    func state(at: URL) async throws -> CloudSessionState { throw CloudError.network }
    func configuration(at: URL) async throws {}
    func connect(at: URL) async throws {}
    func end(at: URL) async throws {}
}

@Test @MainActor func redesignedViewsRenderAtSupportedSizes() async throws {
    _ = NSApplication.shared
    let library = CloudLibrary()
    library.load(using: PreviewCatalog())
    while library.loading { try await Task.sleep(for: .milliseconds(10)) }
    library.selection = "2"
    let model = PostProcessingBenchmarkModel(sessionActive: { false })
    try await capture(PostProcessingBenchmarkView(model: model), name: "benchmark", size: NSSize(width: 860, height: 820))
    try await capture(StreamConnectingView(library: library), name: "connecting", size: NSSize(width: 960, height: 540))
    for width in [900.0, 1440.0] {
        try await capture(VStack {
            GameBrowserView(library: library)
            Divider()
            InlineStreamSettings(library: library)
        }.padding(24).background(LibraryStyle.canvas).foregroundStyle(.white).preferredColorScheme(.dark),
            name: "catalog-\(Int(width))", size: NSSize(width: width, height: 820))
    }
}

@MainActor private func capture<V: View>(_ root: V, name: String, size: NSSize) async throws {
    let host = NSHostingView(rootView: root)
    let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = host
    host.frame = NSRect(origin: .zero, size: size)
    window.appearance = NSAppearance(named: .darkAqua)
    host.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(200))
    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    let data = try #require(bitmap.representation(using: .png, properties: [:]))
    try data.write(to: URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/redesign-\(name).png"))
    #expect(!data.isEmpty)
}

@Test @MainActor func firstRenderedFrameDismissesStartupOverlay() async throws {
    guard ProcessInfo.processInfo.environment["XFRAME_VERIFY_PLAYER_WINDOW"] == "1" else { return }
    _ = NSApplication.shared
    let videoView = MTKView(frame: NSRect(x: 0, y: 0, width: 640, height: 360), device: MTLCreateSystemDefaultDevice())
    let renderer = try MetalRenderer(view: videoView)
    videoView.delegate = renderer
    let content = NSView(frame: videoView.frame)
    content.addSubview(videoView)
    let overlay = NSHostingView(rootView: StreamConnectingView(library: CloudLibrary()))
    overlay.frame = content.bounds
    content.addSubview(overlay)
    let window = NSWindow(contentRect: content.bounds, styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = content
    window.title = "XFrame startup verification"
    window.orderFrontRegardless()
    defer { window.orderOut(nil); videoView.isPaused = true }
    var presentations = 0
    renderer.firstFrameReady = { presentations += 1; overlay.isHidden = true }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let source = LocalVideo(url: root.appendingPathComponent(".build/fixtures/h264-1080p60.mp4"))
    defer { source.stop() }
    renderer.play(source, in: videoView)
    let deadline = ContinuousClock.now.advanced(by: .seconds(10))
    while presentations == 0 && ContinuousClock.now < deadline { videoView.draw(); try await Task.sleep(for: .milliseconds(20)) }
    #expect(presentations == 1)
    #expect(overlay.isHidden)
    #expect((source.snapshot().timings.gpu?.count ?? 0) > 0)
}
