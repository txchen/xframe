import Foundation
import Metal
import MetalFX
import Testing
@testable import XFrame

// Executes the native backend on the actual GPU. This is correctness and cost
// evidence only; it does not measure decoded playback or physical presentation.
@Test func metalFXPreservesSDRColorsAndMeasures4KCost() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    #expect(MTLFXSpatialScalerDescriptor.supportsDevice(device))
    let queue = try #require(device.makeCommandQueue())
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let shader = try String(contentsOf: root.appendingPathComponent("Sources/XFrame/Shaders.metal"), encoding: .utf8)
    let library = try device.makeLibrary(source: shader, options: nil)
    let descriptor = MTLRenderPipelineDescriptor()
    descriptor.vertexFunction = library.makeFunction(name: "patternVertex")
    descriptor.fragmentFunction = library.makeFunction(name: "patternFragment")
    descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
    let pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
    let source = ScalingExtent(width: 1920, height: 1080)
    let output = ScalingExtent(width: 3840, height: 2160)
    let scaler = try SpatialUpscaler(device: device, source: source, output: output)
    let inputDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: source.width, height: source.height, mipmapped: false)
    inputDescriptor.storageMode = .shared; inputDescriptor.usage = .shaderRead
    let input = try #require(device.makeTexture(descriptor: inputDescriptor))
    let colors: [[UInt8]] = [[0, 0, 0, 255], [255, 255, 255, 255], [18, 68, 227, 255], [128, 128, 128, 255]]
    var pixels = [UInt8](repeating: 0, count: source.width * source.height * 4)
    for y in 0..<source.height {
        for x in 0..<source.width {
            let color = colors[x / (source.width / 4)]
            for c in 0..<4 { pixels[(y * source.width + x) * 4 + c] = color[c] }
        }
    }
    pixels.withUnsafeBytes { input.replace(region: MTLRegionMake2D(0, 0, source.width, source.height), mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: source.width * 4) }
    let targetDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: output.width, height: output.height, mipmapped: false)
    targetDescriptor.storageMode = .shared; targetDescriptor.usage = .renderTarget
    let target = try #require(device.makeTexture(descriptor: targetDescriptor))
    var total: [Double] = [], spans: [Double] = []
    for iteration in 0..<65 {
        let counter = scaler.takeCounter()
        let command = try #require(queue.makeCommandBuffer())
        let conversion = MTLRenderPassDescriptor()
        conversion.colorAttachments[0].texture = scaler.input
        conversion.colorAttachments[0].loadAction = .dontCare; conversion.colorAttachments[0].storeAction = .store
        if let counter {
            let a = conversion.sampleBufferAttachments[0]!
            a.sampleBuffer = counter.buffer
            a.startOfVertexSampleIndex = MTLCounterDontSample; a.endOfVertexSampleIndex = MTLCounterDontSample
            a.startOfFragmentSampleIndex = MTLCounterDontSample; a.endOfFragmentSampleIndex = 0
        }
        let first = try #require(command.makeRenderCommandEncoder(descriptor: conversion))
        first.setRenderPipelineState(pipeline); first.setFragmentTexture(input, index: 0)
        first.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4); first.endEncoding()
        scaler.scaler.encode(commandBuffer: command)
        let presentation = MTLRenderPassDescriptor()
        presentation.colorAttachments[0].texture = target
        presentation.colorAttachments[0].loadAction = .dontCare; presentation.colorAttachments[0].storeAction = .store
        if let counter {
            let a = presentation.sampleBufferAttachments[0]!
            a.sampleBuffer = counter.buffer
            a.startOfVertexSampleIndex = MTLCounterDontSample; a.endOfVertexSampleIndex = MTLCounterDontSample
            a.startOfFragmentSampleIndex = 1; a.endOfFragmentSampleIndex = MTLCounterDontSample
        }
        let last = try #require(command.makeRenderCommandEncoder(descriptor: presentation))
        last.setRenderPipelineState(pipeline); last.setFragmentTexture(scaler.output, index: 0)
        last.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4); last.endEncoding()
        command.commit(); command.waitUntilCompleted()
        #expect(command.status == .completed)
        if iteration >= 5 { total.append((command.gpuEndTime - command.gpuStartTime) * 1000) }
        if let counter {
            if let seconds = SpatialUpscaler.scalerSeconds(counter), iteration >= 5 { spans.append(seconds * 1000) }
            scaler.returnCounter(counter)
        }
    }
    var result = [UInt8](repeating: 0, count: output.width * output.height * 4)
    result.withUnsafeMutableBytes { target.getBytes($0.baseAddress!, bytesPerRow: output.width * 4,
        from: MTLRegionMake2D(0, 0, output.width, output.height), mipmapLevel: 0) }
    for index in 0..<4 {
        let x = (index * 2 + 1) * output.width / 8, y = output.height / 2
        let color = Array(result[((y * output.width + x) * 4)..<((y * output.width + x) * 4 + 4)])
        #expect(zip(color, colors[index]).allSatisfy { abs(Int($0) - Int($1)) <= 2 })
    }
    #expect(spans.count == 60)
    func summary(_ values: [Double]) -> String {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return "n/a" }
        return "mean=\(values.reduce(0, +) / Double(values.count)) p95=\(sorted[Int(ceil(Double(sorted.count) * 0.95)) - 1])"
    }
    print("METALFX_OFFSCREEN device=\(device.name) 1080p_to_4K samples=60 total_ms \(summary(total)) scaler_span_ms \(summary(spans))")
}
