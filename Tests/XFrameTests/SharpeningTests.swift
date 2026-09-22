import AppKit
import Metal
import Testing
@testable import XFrame

@Test func sharpeningDefaultsToOffAndPersistsEachPreset() throws {
    let suite = "XFrameTests.Sharpening.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    #expect(SharpeningPreset.load(from: defaults) == .off)
    for preset in SharpeningPreset.allCases {
        preset.save(to: defaults)
        #expect(SharpeningPreset.load(from: defaults) == preset)
    }
    defaults.set("unknown", forKey: SharpeningPreset.preferenceKey)
    #expect(SharpeningPreset.load(from: defaults) == .off)
}

@Test @MainActor func sharpeningChoicesApplyWithoutClosingAndSurviveScalingSwitches() throws {
    let panel = PlaybackSettingsView()
    var selected: SharpeningPreset?
    panel.selectSharpening = { selected = $0; panel.updateSharpening($0) }
    panel.show(scaling: .metalFX, hud: .compact)
    func buttons() throws -> [NSButton] {
        let scroll = try #require(panel.subviews.compactMap { $0 as? NSScrollView }.first)
        let stack = try #require(scroll.documentView as? NSStackView)
        return stack.arrangedSubviews.compactMap { $0 as? NSButton }
    }
    try #require(try buttons().first { $0.title.hasSuffix("Low") }).performClick(nil)
    #expect(selected == .low && !panel.isHidden)
    panel.key(125)
    panel.key(36)
    #expect(selected == .medium)
    panel.gamepad(GamepadSnapshot())
    panel.gamepad(GamepadSnapshot(buttons: [.down]))
    panel.gamepad(GamepadSnapshot())
    panel.gamepad(GamepadSnapshot(buttons: [.a]))
    #expect(selected == .high)
    panel.update(scaling: .integer, hud: .compact)
    #expect(try !buttons().contains { $0.title.hasSuffix("High") })
    panel.update(scaling: .metalFX, hud: .compact)
    #expect(try buttons().contains { $0.title.contains("✓ High") })
}

// Exercise the actual final-composition shader, including SDR bounds and zero
// strength equivalence. This is GPU correctness, not a gameplay-quality judgment.
@Test func sharpeningGPUKeepsFlatColorsAndStrengthensSoftEdgesWithinBounds() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let queue = try #require(device.makeCommandQueue())
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let source = try String(contentsOf: root.appendingPathComponent("Sources/XFrame/Shaders.metal"), encoding: .utf8)
    let library = try device.makeLibrary(source: source, options: nil)
    func pipeline(_ name: String) throws -> any MTLRenderPipelineState {
        let d = MTLRenderPipelineDescriptor()
        d.vertexFunction = library.makeFunction(name: "patternVertex")
        d.fragmentFunction = library.makeFunction(name: name)
        d.colorAttachments[0].pixelFormat = .bgra8Unorm
        return try device.makeRenderPipelineState(descriptor: d)
    }
    let plain = try pipeline("patternFragment"), sharp = try pipeline("sharpenFragment")
    func texture(width: Int, height: Int, usage: MTLTextureUsage) throws -> any MTLTexture {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        d.storageMode = .shared; d.usage = usage
        return try #require(device.makeTexture(descriptor: d))
    }
    func render(_ input: any MTLTexture, _ target: any MTLTexture, preset: SharpeningPreset?, repeats: Int = 1) throws -> [Double] {
        var times: [Double] = []
        for iteration in 0..<repeats {
            let command = try #require(queue.makeCommandBuffer())
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = target
            pass.colorAttachments[0].loadAction = .dontCare
            pass.colorAttachments[0].storeAction = .store
            let encoder = try #require(command.makeRenderCommandEncoder(descriptor: pass))
            encoder.setRenderPipelineState(preset == nil ? plain : sharp)
            encoder.setFragmentTexture(input, index: 0)
            var amount = preset?.amount ?? 0
            encoder.setFragmentBytes(&amount, length: MemoryLayout<Float>.size, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            encoder.endEncoding()
            command.commit(); command.waitUntilCompleted()
            #expect(command.status == .completed)
            if iteration >= 3 { times.append((command.gpuEndTime - command.gpuStartTime) * 1000) }
        }
        return times
    }
    let width = 64, height = 8
    let input = try texture(width: width, height: height, usage: .shaderRead)
    let output = try texture(width: width, height: height, usage: .renderTarget)
    let ramp: [UInt8] = [40, 40, 50, 90, 150, 180, 190, 190]
    var pixels = [UInt8](repeating: 255, count: width * height * 4)
    for y in 0..<height {
        for x in 0..<width {
            let color: [UInt8] = x < 16 ? [18, 68, 227] : Array(repeating: ramp[(x - 16) % 8], count: 3)
            for c in 0..<3 { pixels[(y * width + x) * 4 + c] = color[c] }
        }
    }
    pixels.withUnsafeBytes { input.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: width * 4) }
    func readback() -> [UInt8] {
        var result = pixels
        result.withUnsafeMutableBytes { output.getBytes($0.baseAddress!, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0) }
        return result
    }
    _ = try render(input, output, preset: nil)
    let baseline = readback()
    var darkEdges: [Int] = []
    for preset in SharpeningPreset.allCases {
        _ = try render(input, output, preset: preset)
        let result = readback()
        if preset == .off { #expect(result == baseline) }
        let flat = (4 * width + 8) * 4
        #expect(Array(result[flat..<flat+4]) == [18, 68, 227, 255])
        // Soft dark edge at x=18 should get darker as strength increases.
        darkEdges.append(Int(result[(4 * width + 18) * 4]))
        for i in stride(from: 0, to: result.count, by: 4) {
            #expect(result[i+3] == 255)
            for c in 0..<3 { #expect(abs(Int(result[i+c]) - Int(baseline[i+c])) <= 18) }
        }
    }
    #expect(darkEdges[0] > darkEdges[1] && darkEdges[1] > darkEdges[2] && darkEdges[2] > darkEdges[3])
    let largeInput = try texture(width: 3840, height: 2160, usage: .shaderRead)
    let largePixels = [UInt8](repeating: 128, count: 3840 * 2160 * 4)
    largePixels.withUnsafeBytes {
        largeInput.replace(region: MTLRegionMake2D(0, 0, 3840, 2160), mipmapLevel: 0,
            withBytes: $0.baseAddress!, bytesPerRow: 3840 * 4)
    }
    let large = try texture(width: 3840, height: 2160, usage: .renderTarget)
    for preset: SharpeningPreset? in [nil, .high] {
        let times = try render(largeInput, large, preset: preset, repeats: 23).sorted()
        print("SHARPEN_COMPOSITION_4K \(preset?.title ?? "Off") samples=\(times.count) mean_ms=\(times.reduce(0,+) / Double(times.count)) p95_ms=\(times[18])")
    }
}
