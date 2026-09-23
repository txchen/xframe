import AVFoundation
import CoreMedia
import CoreVideo
import CryptoKit
import Foundation
import Metal
import MetalFX
import QuartzCore
import VideoToolbox

// Offline cost of one 1080p source frame -> 720p VT midpoint -> 1080p MetalFX
// midpoint. The original 1080p frame is kept native; decode/display are omitted.
@main
struct BenchmarkVT720Spatial {
    struct Frame {
        let buffer: CVPixelBuffer
        let pts: CMTime
    }

    struct Timing {
        var downscale = [Double]()
        var interpolation = [Double]()
        var upscaleWall = [Double]()
        var upscaleGPU = [Double]()
        var combined = [Double]()
    }

    static func percentile(_ samples: [Double], _ fraction: Double) -> Double {
        let ordered = samples.sorted()
        return ordered[max(0, Int(ceil(Double(ordered.count) * fraction)) - 1)]
    }

    static func summarize(_ samples: [Double]) -> [String: Double] {
        ["medianMS": percentile(samples, 0.5), "p95MS": percentile(samples, 0.95),
         "maxMS": samples.max()!]
    }

    static func allocate(width: Int, height: Int, format: OSType,
                         attributes: [String: Any]) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, format,
                                         attributes as CFDictionary, &buffer)
        guard status == kCVReturnSuccess, let buffer else {
            throw NSError(domain: "com.xframe.composite.allocate", code: Int(status))
        }
        return buffer
    }

    static func decode(_ url: URL) async throws -> [Frame] {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw NSError(domain: "com.xframe.composite.noVideo", code: 1)
        }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any]
        ])
        reader.add(output)
        guard reader.startReading() else {
            throw reader.error ?? NSError(domain: "com.xframe.composite.reader", code: 1)
        }
        var frames = [Frame]()
        while frames.count < 61, let sample = output.copyNextSampleBuffer() {
            if let buffer = CMSampleBufferGetImageBuffer(sample) {
                frames.append(Frame(buffer: buffer, pts: CMSampleBufferGetPresentationTimeStamp(sample)))
            }
        }
        reader.cancelReading()
        guard frames.count == 61 else {
            throw NSError(domain: "com.xframe.composite.shortFixture", code: frames.count)
        }
        return frames
    }

    final class SpatialStage {
        private let queue: any MTLCommandQueue
        private let cache: CVMetalTextureCache
        private let scaler: any MTLFXSpatialScaler
        private let input: any MTLTexture
        private let output: any MTLTexture
        private let target: any MTLTexture
        private let conversion: any MTLRenderPipelineState
        private let composition: any MTLRenderPipelineState

        init(device: any MTLDevice, shaderURL: URL) throws {
            guard let queue = device.makeCommandQueue() else {
                throw NSError(domain: "com.xframe.composite.queue", code: 1)
            }
            self.queue = queue
            var createdCache: CVMetalTextureCache?
            guard CVMetalTextureCacheCreate(nil, nil, device, nil, &createdCache) == kCVReturnSuccess,
                  let createdCache else {
                throw NSError(domain: "com.xframe.composite.cache", code: 1)
            }
            cache = createdCache
            let descriptor = MTLFXSpatialScalerDescriptor()
            descriptor.inputWidth = 1280; descriptor.inputHeight = 720
            descriptor.outputWidth = 1920; descriptor.outputHeight = 1080
            descriptor.colorTextureFormat = .bgra8Unorm
            descriptor.outputTextureFormat = .bgra8Unorm
            descriptor.colorProcessingMode = .perceptual
            guard MTLFXSpatialScalerDescriptor.supportsDevice(device),
                  let scaler = descriptor.makeSpatialScaler(device: device) else {
                throw NSError(domain: "com.xframe.composite.spatialUnavailable", code: 1)
            }
            self.scaler = scaler
            func texture(width: Int, height: Int, usage: MTLTextureUsage) throws -> any MTLTexture {
                let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
                    width: width, height: height, mipmapped: false)
                d.storageMode = .private; d.usage = usage
                guard let texture = device.makeTexture(descriptor: d) else {
                    throw NSError(domain: "com.xframe.composite.texture", code: 1)
                }
                return texture
            }
            input = try texture(width: 1280, height: 720,
                                usage: scaler.colorTextureUsage.union([.renderTarget]))
            output = try texture(width: 1920, height: 1080,
                                 usage: scaler.outputTextureUsage.union([.shaderRead]))
            target = try texture(width: 1920, height: 1080, usage: .renderTarget)
            scaler.colorTexture = input; scaler.outputTexture = output
            scaler.inputContentWidth = 1280; scaler.inputContentHeight = 720

            let shader = try String(contentsOf: shaderURL, encoding: .utf8)
            let library = try device.makeLibrary(source: shader, options: nil)
            func pipeline(fragment: String) throws -> any MTLRenderPipelineState {
                let d = MTLRenderPipelineDescriptor()
                d.vertexFunction = library.makeFunction(name: "patternVertex")
                d.fragmentFunction = library.makeFunction(name: fragment)
                d.colorAttachments[0].pixelFormat = .bgra8Unorm
                return try device.makeRenderPipelineState(descriptor: d)
            }
            conversion = try pipeline(fragment: "videoFragment")
            composition = try pipeline(fragment: "patternFragment")
        }

        func process(_ buffer: CVPixelBuffer) throws -> (wallMS: Double, gpuMS: Double) {
            let started = CACurrentMediaTime()
            guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange else {
                throw NSError(domain: "com.xframe.composite.format", code: 1)
            }
            var yRef: CVMetalTexture?, uvRef: CVMetalTexture?
            let yStatus = CVMetalTextureCacheCreateTextureFromImage(nil, cache, buffer, nil,
                .r8Unorm, 1280, 720, 0, &yRef)
            let uvStatus = CVMetalTextureCacheCreateTextureFromImage(nil, cache, buffer, nil,
                .rg8Unorm, 640, 360, 1, &uvRef)
            guard yStatus == kCVReturnSuccess, uvStatus == kCVReturnSuccess,
                  let yRef, let uvRef,
                  let y = CVMetalTextureGetTexture(yRef), let uv = CVMetalTextureGetTexture(uvRef),
                  let command = queue.makeCommandBuffer() else {
                throw NSError(domain: "com.xframe.composite.import", code: 1)
            }
            let convertPass = MTLRenderPassDescriptor()
            convertPass.colorAttachments[0].texture = input
            convertPass.colorAttachments[0].loadAction = .dontCare
            convertPass.colorAttachments[0].storeAction = .store
            guard let convert = command.makeRenderCommandEncoder(descriptor: convertPass) else {
                throw NSError(domain: "com.xframe.composite.convertEncoder", code: 1)
            }
            convert.setRenderPipelineState(conversion)
            convert.setFragmentTexture(y, index: 0)
            convert.setFragmentTexture(uv, index: 1)
            var color = SIMD4<Float>(0.2126, 0.0722, 0, 0)
            convert.setFragmentBytes(&color, length: MemoryLayout<SIMD4<Float>>.size, index: 0)
            convert.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            convert.endEncoding()
            scaler.encode(commandBuffer: command)
            let composePass = MTLRenderPassDescriptor()
            composePass.colorAttachments[0].texture = target
            composePass.colorAttachments[0].loadAction = .dontCare
            composePass.colorAttachments[0].storeAction = .store
            guard let compose = command.makeRenderCommandEncoder(descriptor: composePass) else {
                throw NSError(domain: "com.xframe.composite.composeEncoder", code: 1)
            }
            compose.setRenderPipelineState(composition)
            compose.setFragmentTexture(output, index: 0)
            compose.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            compose.endEncoding()
            command.commit()
            command.waitUntilCompleted()
            guard command.status == .completed else {
                throw command.error ?? NSError(domain: "com.xframe.composite.gpu", code: 1)
            }
            let wallMS = (CACurrentMediaTime() - started) * 1000
            let gpuMS = command.gpuStartTime > 0 && command.gpuEndTime >= command.gpuStartTime
                ? (command.gpuEndTime - command.gpuStartTime) * 1000 : -1
            return (wallMS, gpuMS)
        }
    }

    static func main() async throws {
        guard CommandLine.arguments.count == 3 || CommandLine.arguments.count == 4 else {
            fputs("Usage: benchmark-vt720-spatial VIDEO.mp4 Shaders.metal [full|pre-resize|no-spatial|pre-resize-no-spatial]\n", stderr)
            exit(2)
        }
        let mode = CommandLine.arguments.count == 4 ? CommandLine.arguments[3] : "full"
        guard ["full", "pre-resize", "no-spatial", "pre-resize-no-spatial"].contains(mode) else {
            fputs("Unknown benchmark mode.\n", stderr)
            exit(2)
        }
        let preResize = mode.hasPrefix("pre-resize")
        let useSpatial = !mode.hasSuffix("no-spatial")
        let videoURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let fixtureSHA256 = SHA256.hash(data: try Data(contentsOf: videoURL))
            .map { String(format: "%02x", $0) }.joined()
        let frames = try await decode(videoURL)
        guard frames.allSatisfy({ CVPixelBufferGetWidth($0.buffer) == 1920 &&
                                   CVPixelBufferGetHeight($0.buffer) == 1080 }) else {
            throw NSError(domain: "com.xframe.composite.sourceSize", code: 1)
        }
        guard (1..<frames.count).allSatisfy({ index in
            abs(CMTimeGetSeconds(CMTimeSubtract(frames[index].pts,
                frames[index - 1].pts)) - 1.0 / 30.0) < 0.001
        }) else {
            throw NSError(domain: "com.xframe.composite.sourceFrameRate", code: 1)
        }
        guard let device = MTLCreateSystemDefaultDevice(),
              let config = VTLowLatencyFrameInterpolationConfiguration(frameWidth: 1280,
                  frameHeight: 720, numberOfInterpolatedFrames: 1) else {
            throw NSError(domain: "com.xframe.composite.unavailable", code: 1)
        }
        let spatial = useSpatial ? try SpatialStage(device: device,
            shaderURL: URL(fileURLWithPath: CommandLine.arguments[2])) : nil
        var transfer: VTPixelTransferSession?
        let transferStatus = VTPixelTransferSessionCreate(allocator: kCFAllocatorDefault,
            pixelTransferSessionOut: &transfer)
        guard transferStatus == noErr, let transfer else {
            throw NSError(domain: "com.xframe.composite.transfer", code: Int(transferStatus))
        }
        defer { VTPixelTransferSessionInvalidate(transfer) }
        let processor = VTFrameProcessor()
        try processor.startSession(configuration: config)
        defer { processor.endSession() }
        let sourceAttrs: [String: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any],
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]
        let scaled = try (0..<61).map { _ in try allocate(width: 1280, height: 720,
            format: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, attributes: sourceAttrs) }
        guard let destinationFormat = config.destinationPixelBufferAttributes[
            kCVPixelBufferPixelFormatTypeKey as String] as? OSType else {
            throw NSError(domain: "com.xframe.composite.destinationFormat", code: 1)
        }
        let generated = try (0..<60).map { _ in try allocate(width: 1280, height: 720,
            format: destinationFormat, attributes: config.destinationPixelBufferAttributes) }
        if preResize {
            for index in 0..<61 {
                guard VTPixelTransferSessionTransferImage(transfer, from: frames[index].buffer,
                    to: scaled[index]) == noErr else {
                    throw NSError(domain: "com.xframe.composite.preResize", code: index)
                }
            }
        } else {
            guard VTPixelTransferSessionTransferImage(transfer, from: frames[0].buffer,
                to: scaled[0]) == noErr else {
                throw NSError(domain: "com.xframe.composite.firstResize", code: 1)
            }
        }
        var times = Timing()
        for index in 1..<61 {
            let start = CACurrentMediaTime()
            if !preResize {
                let status = VTPixelTransferSessionTransferImage(transfer, from: frames[index].buffer,
                    to: scaled[index])
                guard status == noErr else {
                    throw NSError(domain: "com.xframe.composite.resize", code: Int(status))
                }
            }
            let downscaleMS = (CACurrentMediaTime() - start) * 1000
            guard let previous = VTFrameProcessorFrame(buffer: scaled[index - 1],
                        presentationTimeStamp: frames[index - 1].pts),
                  let current = VTFrameProcessorFrame(buffer: scaled[index],
                        presentationTimeStamp: frames[index].pts),
                  let midpoint = VTFrameProcessorFrame(buffer: generated[index - 1],
                        presentationTimeStamp: CMTimeMultiplyByFloat64(
                            CMTimeAdd(frames[index - 1].pts, frames[index].pts), multiplier: 0.5)),
                  let parameters = VTLowLatencyFrameInterpolationParameters(sourceFrame: current,
                      previousFrame: previous, interpolationPhase: [0.5],
                      destinationFrames: [midpoint]) else {
                throw NSError(domain: "com.xframe.composite.parameters", code: 1)
            }
            let vtStart = CACurrentMediaTime()
            var outputs = 0
            for try await _ in processor.process(parameters: parameters) { outputs += 1 }
            guard outputs == 1 else {
                throw NSError(domain: "com.xframe.composite.outputs", code: outputs)
            }
            let vtMS = (CACurrentMediaTime() - vtStart) * 1000
            let upscale = try spatial?.process(generated[index - 1])
            if index > 5 {
                times.downscale.append(downscaleMS)
                times.interpolation.append(vtMS)
                if let upscale {
                    times.upscaleWall.append(upscale.wallMS)
                    if upscale.gpuMS >= 0 { times.upscaleGPU.append(upscale.gpuMS) }
                }
                times.combined.append((CACurrentMediaTime() - start) * 1000)
            }
        }
        let result: [String: Any] = [
            "device": device.name, "macOS": ProcessInfo.processInfo.operatingSystemVersionString,
            "source": "1080p30 H.264 video, 61 decoded frames",
            "sourceSHA256": fixtureSHA256,
            "generated": "720p midpoint → MetalFX Spatial 1080p",
            "samples": times.combined.count, "warmups": 5, "mode": mode,
            "downscale": summarize(times.downscale),
            "interpolation": summarize(times.interpolation),
            "upscaleWall": times.upscaleWall.isEmpty ? NSNull() : summarize(times.upscaleWall) as Any,
            "upscaleGPU": times.upscaleGPU.isEmpty ? NSNull() : summarize(times.upscaleGPU) as Any,
            "combinedWall": summarize(times.combined),
            "budgetMS": 1000.0 / 30.0,
            "notes": "Full mode: one new 1080p source per pair, only the generated midpoint is upscaled. Pre-resize and no-spatial modes isolate stage interaction. CVPixelBuffer allocations, video decode, model/scaler setup and display are outside timing. Combined wall is sequential and includes per-frame Metal texture wrapping, encoding and GPU completion when spatial runs."
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([10]))
    }
}
