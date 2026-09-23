import AVFoundation
import CoreImage
import CoreMedia
import CoreVideo
import Foundation
import Metal
import QuartzCore
import VideoToolbox

@main
struct BenchmarkVT {
    static func percentile(_ values: [Double], _ p: Double) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        return sorted[max(0, Int(ceil(p * Double(sorted.count))) - 1)]
    }

    static func makeDestination(attributes: [String: Any]) throws -> CVPixelBuffer {
        guard let width = attributes[kCVPixelBufferWidthKey as String] as? Int,
              let height = attributes[kCVPixelBufferHeightKey as String] as? Int,
              let format = attributes[kCVPixelBufferPixelFormatTypeKey as String] as? OSType else {
            throw NSError(domain: "benchmark.attributes", code: 1)
        }
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, format,
            attributes as CFDictionary, &pixelBuffer)
        guard status == kCVReturnSuccess, let pixelBuffer else {
            throw NSError(domain: "benchmark.destination", code: Int(status))
        }
        return pixelBuffer
    }

    static func main() async throws {
        guard CommandLine.arguments.count >= 2 else {
            fputs("Usage: benchmark-vt VIDEO.mp4 [MAX_PAIRS=60] [PREVIEW.png]\n", stderr)
            exit(2)
        }
        let url = URL(fileURLWithPath: CommandLine.arguments[1])
        let maxPairs = CommandLine.arguments.count > 2 ? Int(CommandLine.arguments[2])! : 60
        let previewURL = CommandLine.arguments.count > 3 ? URL(fileURLWithPath: CommandLine.arguments[3]) : nil
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw NSError(domain: "benchmark.noVideo", code: 1)
        }
        let dimensions = try await track.load(.naturalSize)
        let width = Int(dimensions.width), height = Int(dimensions.height)
        let maxPixels = VTLowLatencyFrameInterpolationConfiguration.maximumPixelCount(forSpatialScaleFactor: 1) ?? 0
        let maxDimension = VTLowLatencyFrameInterpolationConfiguration.maximumDimension(forSpatialScaleFactor: 1) ?? 0
        guard let configuration = VTLowLatencyFrameInterpolationConfiguration(
            frameWidth: width, frameHeight: height, numberOfInterpolatedFrames: 1) else {
            throw NSError(domain: "benchmark.configuration", code: 1)
        }
        let processor = VTFrameProcessor()
        let sessionStart = CACurrentMediaTime()
        try processor.startSession(configuration: configuration)
        let sessionMS = (CACurrentMediaTime() - sessionStart) * 1000
        defer { processor.endSession() }

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any]
        ])
        output.alwaysCopiesSampleData = false
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? NSError(domain: "benchmark.reader", code: 1) }
        guard let first = output.copyNextSampleBuffer(), let firstBuffer = CMSampleBufferGetImageBuffer(first) else {
            throw NSError(domain: "benchmark.firstFrame", code: 1)
        }
        var previous = firstBuffer
        var previousPTS = CMSampleBufferGetPresentationTimeStamp(first)
        var timings: [Double] = []
        var decodeMS: [Double] = []
        var preview: CVPixelBuffer?
        for _ in 0..<maxPairs {
            let decodeStart = CACurrentMediaTime()
            guard let sample = output.copyNextSampleBuffer(), let current = CMSampleBufferGetImageBuffer(sample) else { break }
            decodeMS.append((CACurrentMediaTime() - decodeStart) * 1000)
            let currentPTS = CMSampleBufferGetPresentationTimeStamp(sample)
            let destination = try makeDestination(attributes: configuration.destinationPixelBufferAttributes)
            guard let a = VTFrameProcessorFrame(buffer: previous, presentationTimeStamp: previousPTS),
                  let b = VTFrameProcessorFrame(buffer: current, presentationTimeStamp: currentPTS),
                  let mid = VTFrameProcessorFrame(buffer: destination, presentationTimeStamp: CMTimeMultiplyByFloat64(CMTimeAdd(previousPTS, currentPTS), multiplier: 0.5)),
                  let parameters = VTLowLatencyFrameInterpolationParameters(sourceFrame: b, previousFrame: a,
                    interpolationPhase: [0.5], destinationFrames: [mid]) else {
                throw NSError(domain: "benchmark.notIOSurface", code: 1)
            }
            let start = CACurrentMediaTime()
            var outputs = 0
            for try await _ in processor.process(parameters: parameters) { outputs += 1 }
            guard outputs == 1 else { throw NSError(domain: "benchmark.noOutput", code: outputs) }
            timings.append((CACurrentMediaTime() - start) * 1000)
            if preview == nil { preview = destination }
            previous = current
            previousPTS = currentPTS
        }
        guard !timings.isEmpty else { throw NSError(domain: "benchmark.noPairs", code: 1) }
        if let previewURL, let preview {
            let context = CIContext()
            try context.writePNGRepresentation(of: CIImage(cvPixelBuffer: preview), to: previewURL,
                format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
        }
        let steady = Array(timings.dropFirst(min(5, timings.count)))
        let result: [String: Any] = [
            "backend": "VideoToolbox low-latency", "input": url.path,
            "device": MTLCreateSystemDefaultDevice()?.name ?? "unknown", "width": width, "height": height,
            "supported": VTLowLatencyFrameInterpolationConfiguration.isSupported,
            "maximumPixelCount": maxPixels, "maximumDimension": maxDimension,
            "sessionStartMS": sessionMS, "pairs": timings.count, "warmupPairs": min(5, timings.count),
            "processMS": timings, "steadyP50MS": percentile(steady, 0.5) as Any,
            "steadyP95MS": percentile(steady, 0.95) as Any,
            "steadyMaxMS": steady.max() as Any,
            "decodeP50MS": percentile(decodeMS, 0.5) as Any
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([10]))
    }
}
