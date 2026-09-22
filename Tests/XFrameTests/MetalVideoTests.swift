import Foundation
import CoreVideo
import Metal
import Testing
@testable import XFrame

// Offscreen GPU execution only: no NSWindow, drawable, display or UI automation.
// CPU plane writes/readback exist only in this synthetic verification fixture.
@Test(arguments: [false, true])
func metalImportsNV12AndConvertsVideoRangeOnTheGPU(use601: Bool) throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let queue = try #require(device.makeCommandQueue())
    var buffer: CVPixelBuffer?
    let attributes: [CFString: Any] = [kCVPixelBufferMetalCompatibilityKey: true,
        kCVPixelBufferIOSurfacePropertiesKey: [:] as [String: Any]]
    #expect(CVPixelBufferCreate(nil, 24, 8, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
        attributes as CFDictionary, &buffer) == kCVReturnSuccess)
    let pixels = try #require(buffer)
    CVBufferSetAttachment(pixels, kCVImageBufferYCbCrMatrixKey,
        use601 ? kCVImageBufferYCbCrMatrix_ITU_R_601_4 : kCVImageBufferYCbCrMatrix_ITU_R_709_2, .shouldPropagate)
    #expect(CVPixelBufferLockBaseAddress(pixels, []) == kCVReturnSuccess)
    let yPlane = try #require(CVPixelBufferGetBaseAddressOfPlane(pixels, 0)).assumingMemoryBound(to: UInt8.self)
    let uvPlane = try #require(CVPixelBufferGetBaseAddressOfPlane(pixels, 1)).assumingMemoryBound(to: UInt8.self)
    for y in 0..<8 {
        for x in 0..<24 { yPlane[y * CVPixelBufferGetBytesPerRowOfPlane(pixels, 0) + x] = x < 8 ? 16 : (x < 16 ? 235 : 100) }
    }
    for y in 0..<4 {
        for x in 0..<12 {
            let offset = y * CVPixelBufferGetBytesPerRowOfPlane(pixels, 1) + x * 2
            uvPlane[offset] = x < 8 ? 128 : 90
            uvPlane[offset + 1] = x < 8 ? 128 : 200
        }
    }
    CVPixelBufferUnlockBaseAddress(pixels, [])
    var cache: CVMetalTextureCache?
    #expect(CVMetalTextureCacheCreate(nil, nil, device, nil, &cache) == kCVReturnSuccess)
    let imported = try VideoTextures(frame: VideoFrame(buffer: pixels, time: 0, id: 1), cache: #require(cache))
    #expect(imported.luma.pixelFormat == .r8Unorm && imported.chroma.pixelFormat == .rg8Unorm)
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let shader = try String(contentsOf: root.appendingPathComponent("Sources/XFrame/Shaders.metal"), encoding: .utf8)
    let library = try device.makeLibrary(source: shader, options: nil)
    let pipeline = MTLRenderPipelineDescriptor()
    pipeline.vertexFunction = library.makeFunction(name: "patternVertex")
    pipeline.fragmentFunction = library.makeFunction(name: "videoFragment")
    pipeline.colorAttachments[0].pixelFormat = .bgra8Unorm
    let state = try device.makeRenderPipelineState(descriptor: pipeline)
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 24, height: 8, mipmapped: false)
    descriptor.storageMode = .shared; descriptor.usage = [.renderTarget]
    let target = try #require(device.makeTexture(descriptor: descriptor))
    let pass = MTLRenderPassDescriptor()
    pass.colorAttachments[0].texture = target
    pass.colorAttachments[0].loadAction = .clear
    pass.colorAttachments[0].storeAction = .store
    let command = try #require(queue.makeCommandBuffer())
    let encoder = try #require(command.makeRenderCommandEncoder(descriptor: pass))
    encoder.setRenderPipelineState(state)
    encoder.setFragmentTexture(imported.luma, index: 0)
    encoder.setFragmentTexture(imported.chroma, index: 1)
    var conversion = imported.conversion
    encoder.setFragmentBytes(&conversion, length: MemoryLayout<SIMD4<Float>>.size, index: 0)
    encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    encoder.endEncoding()
    command.commit(); command.waitUntilCompleted() // Test only; production never waits synchronously.
    #expect(command.status == .completed)
    withExtendedLifetime(imported) {}
    var output = [UInt8](repeating: 0, count: 24 * 8 * 4)
    output.withUnsafeMutableBytes {
        target.getBytes($0.baseAddress!, bytesPerRow: 24 * 4, from: MTLRegionMake2D(0, 0, 24, 8), mipmapLevel: 0)
    }
    func sample(_ x: Int) -> [Int] { output[((4 * 24 + x) * 4)..<((4 * 24 + x) * 4 + 4)].map(Int.init) }
    #expect(sample(4) == [0, 0, 0, 255])
    #expect(sample(12) == [255, 255, 255, 255])
    let expected = use601 ? [21, 54, 213, 255] : [18, 68, 227, 255]
    #expect(zip(sample(20), expected).allSatisfy { abs($0 - $1) <= 1 })
    if command.gpuStartTime > 0 {
        print("OFFSCREEN_GPU_MS \((command.gpuEndTime - command.gpuStartTime) * 1000)")
    }
}
