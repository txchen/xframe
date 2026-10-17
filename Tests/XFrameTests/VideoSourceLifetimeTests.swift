import CoreVideo
import MetalKit
import Testing
@preconcurrency import WebRTC
@testable import XFrame

@Test @MainActor func liveVideoKeepsReceivingFramesAfterRendererReattachment() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let view = MTKView(frame: .zero, device: device)
    let renderer = try MetalRenderer(view: view)
    renderer.hudPreset = .hidden
    let source = LiveVideo()
    defer {
        renderer.play(nil, in: view)
        source.stop()
    }
    var buffer: CVPixelBuffer?
    #expect(CVPixelBufferCreate(kCFAllocatorDefault, 16, 16,
        kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, nil, &buffer) == kCVReturnSuccess)
    let pixels = try #require(buffer)
    renderer.play(source, in: view)

    for frameID in 1...2 {
        renderer.play(nil, in: view)
        #expect(view.isPaused)
        renderer.play(source, in: view)
        source.renderFrame(RTCVideoFrame(buffer: RTCCVPixelBuffer(pixelBuffer: pixels),
            rotation: ._0, timeStampNs: Int64(frameID)))
        #expect(source.snapshot().decoded == frameID)
        #expect(source.nextFrame(at: 0)?.id == frameID)
    }

    source.stop()
    source.renderFrame(RTCVideoFrame(buffer: RTCCVPixelBuffer(pixelBuffer: pixels),
        rotation: ._0, timeStampNs: 3))
    #expect(source.snapshot().decoded == 2)
    #expect(source.nextFrame(at: 0) == nil)
}
