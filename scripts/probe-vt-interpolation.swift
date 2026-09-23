import CoreMedia
import CoreVideo
import Foundation
import QuartzCore
import VideoToolbox

// Synthetic throughput/capability probe. Does not measure game-image quality or playback latency.
@main
struct Probe {
    static func buffer(attributes: [String: Any], shift: Int) throws -> CVPixelBuffer {
        var result: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, attributes[kCVPixelBufferWidthKey as String] as! Int,
            attributes[kCVPixelBufferHeightKey as String] as! Int,
            attributes[kCVPixelBufferPixelFormatTypeKey as String] as! OSType,
            attributes as CFDictionary, &result)
        guard status == kCVReturnSuccess, let result else { throw NSError(domain: "probe.buffer", code: Int(status)) }
        CVPixelBufferLockBaseAddress(result, [])
        defer { CVPixelBufferUnlockBaseAddress(result, []) }
        for plane in 0..<CVPixelBufferGetPlaneCount(result) {
            guard let base = CVPixelBufferGetBaseAddressOfPlane(result, plane) else { continue }
            let stride = CVPixelBufferGetBytesPerRowOfPlane(result, plane)
            let height = CVPixelBufferGetHeightOfPlane(result, plane)
            let width = CVPixelBufferGetWidthOfPlane(result, plane)
            let bytes = base.assumingMemoryBound(to: UInt8.self)
            for y in 0..<height {
                for x in 0..<width {
                    bytes[y * stride + x] = plane == 0 ? UInt8((x / 4 + y / 4 + shift) & 255) : 128
                }
            }
        }
        return result
    }

    static func main() async throws {
        let width = CommandLine.arguments.count > 1 ? Int(CommandLine.arguments[1])! : 1920
        let height = CommandLine.arguments.count > 2 ? Int(CommandLine.arguments[2])! : 1080
        let iterations = CommandLine.arguments.count > 3 ? Int(CommandLine.arguments[3])! : 20
        print("supported=\(VTLowLatencyFrameInterpolationConfiguration.isSupported) maxPixels=\(VTLowLatencyFrameInterpolationConfiguration.maximumPixelCount(forSpatialScaleFactor: 1) ?? -1) maxDimension=\(VTLowLatencyFrameInterpolationConfiguration.maximumDimension(forSpatialScaleFactor: 1) ?? -1) requested=\(width)x\(height)")
        guard let config = VTLowLatencyFrameInterpolationConfiguration(frameWidth: width, frameHeight: height, numberOfInterpolatedFrames: 1) else {
            print("configuration unavailable"); return
        }
        print("formats=\(config.supportedPixelFormats)")
        let processor = VTFrameProcessor()
        let startedAt = CACurrentMediaTime()
        do { try processor.startSession(configuration: config) }
        catch { print("session failed: \(error)"); return }
        print(String(format: "sessionStartMS=%.2f", (CACurrentMediaTime() - startedAt) * 1000))
        let previous = try buffer(attributes: config.sourcePixelBufferAttributes, shift: 0)
        let current = try buffer(attributes: config.sourcePixelBufferAttributes, shift: 16)
        let destination = try buffer(attributes: config.destinationPixelBufferAttributes, shift: 0)
        let a = VTFrameProcessorFrame(buffer: previous, presentationTimeStamp: CMTime(value: 0, timescale: 60))!
        let b = VTFrameProcessorFrame(buffer: current, presentationTimeStamp: CMTime(value: 2, timescale: 60))!
        let mid = VTFrameProcessorFrame(buffer: destination, presentationTimeStamp: CMTime(value: 1, timescale: 60))!
        var timings: [Double] = []
        for i in 0..<iterations {
            let params = VTLowLatencyFrameInterpolationParameters(sourceFrame: b, previousFrame: a,
                interpolationPhase: [0.5], destinationFrames: [mid])!
            let start = CACurrentMediaTime()
            do {
                for try await _ in processor.process(parameters: params) {}
            } catch { print("process failed at \(i): \(error)"); break }
            timings.append((CACurrentMediaTime() - start) * 1000)
        }
        if !timings.isEmpty {
            print("processMS=" + timings.map { String(format: "%.2f", $0) }.joined(separator: ","))
            let steady = timings.dropFirst().sorted()
            if !steady.isEmpty {
                print(String(format: "steadyMedianMS=%.2f steadyMaxMS=%.2f", steady[steady.count / 2], steady.last!))
            }
        }
        processor.endSession()
    }
}
