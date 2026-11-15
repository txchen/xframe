import AVFoundation
import CoreImage
import CryptoKit
import Darwin
import QuartzCore

// The pinned research port runs out of process. Its weights stay at the user's
// selected path; only a digest, never the path or contents, enters the report.
enum MLXFrameGenerationBenchmark {
    static let budgetMS = 1000.0 / 30.0

    static func modelDigest(_ url: URL) throws -> String {
        let digest = SHA256.hash(data: try Data(contentsOf: url))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func measure(frames: [CVPixelBuffer], width: Int, height: Int,
                        weightsURL: URL) async throws -> [BenchmarkMeasurement] {
        let id = "mlx\(height)"
        let title = "MLX-DLSS video \(height)p 30 → 60 fps"
        guard let helper = Bundle.main.executableURL?.deletingLastPathComponent()
            .appendingPathComponent("mlxdlss-benchmark"),
              FileManager.default.isExecutableFile(atPath: helper.path) else {
            return [.unavailable(id, title, detail: "The optional MLX-DLSS helper is absent from this build.",
                                 budgetMS: budgetMS)]
        }
        let context = CIContext(options: [.cacheIntermediates: false])
        let child = BenchmarkChild(helper: helper, weightsURL: weightsURL, width: width, height: height)
        let values = try await withTaskCancellationHandler {
            try child.run(frameCount: frames.count) { index in
                try makeRGBFrame(frames[index], width: width, height: height, context: context)
            }
        } onCancel: {
            child.terminate()
        }
        return [
            .measured(id, title,
                detail: "55 adjacent moving-frame pairs after five warmups. Excludes decode and RGB preparation; includes helper input/output transfer and MLX generation. Diagnostic only; capacity uses the preparation-inclusive row.",
                timing: "Helper round-trip wall", values: values.helper, budgetMS: budgetMS),
            .measured("mlxEndToEnd\(height)", "\(title) + RGB preparation",
                detail: "Includes fixture resize, CPU bitmap output, RGB packing, helper transfer and generation. Excludes decode, display and startup. RGB is prepared one frame at a time, not cached for all 61 frames. Research path, not live playback.",
                timing: "Preparation + helper wall", values: values.endToEnd, budgetMS: budgetMS)
        ]
    }

    static func makeRGBFrame(_ buffer: CVPixelBuffer, width: Int, height: Int,
                                     context: CIContext) throws -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        return try autoreleasepool {
            try Task.checkCancellation()
            let source = CIImage(cvPixelBuffer: buffer)
            let image = source.transformed(by: CGAffineTransform(
                scaleX: CGFloat(width) / source.extent.width,
                y: CGFloat(height) / source.extent.height))
            var rgba = [UInt8](repeating: 0, count: width * height * 4)
            rgba.withUnsafeMutableBytes { bytes in
                context.render(image, toBitmap: bytes.baseAddress!, rowBytes: width * 4,
                               bounds: bounds, format: .RGBA8, colorSpace: colorSpace)
            }
            var rgb = Data(count: width * height * 3)
            rgb.withUnsafeMutableBytes { destination in
                rgba.withUnsafeBytes { source in
                    let input = source.bindMemory(to: UInt8.self)
                    let output = destination.bindMemory(to: UInt8.self)
                    for pixel in 0..<(width * height) {
                        output[pixel * 3] = input[pixel * 4]
                        output[pixel * 3 + 1] = input[pixel * 4 + 1]
                        output[pixel * 3 + 2] = input[pixel * 4 + 2]
                    }
                }
            }
            return rgb
        }
    }
}

// Keep only one prepared RGB frame alive. Both distributions use the same pairs
// and completion timestamp; the seed and first five generated pairs are warmup.
struct MLXBenchmarkSamples {
    var helper: [Double] = []
    var endToEnd: [Double] = []

    static func collect(frameCount: Int, prepare: (Int) throws -> Data,
                        clock: () -> Double = CACurrentMediaTime,
                        exchange: (Data, Bool) throws -> Void) throws -> Self {
        var samples = Self()
        for index in 0..<frameCount {
            try Task.checkCancellation()
            try autoreleasepool {
                let start = clock()
                let frame = try prepare(index)
                try Task.checkCancellation()
                let prepared = clock()
                try exchange(frame, index == 0)
                let finished = clock()
                if index > 5 {
                    samples.helper.append((finished - prepared) * 1000)
                    samples.endToEnd.append((finished - start) * 1000)
                }
            }
        }
        return samples
    }
}

final class BenchmarkChild: @unchecked Sendable {
    private let process = Process()
    private let input = Pipe(), output = Pipe()
    private let lock = NSLock()
    private var started = false
    private let neuralRendering: Bool
    private let zeroMotion: Data?
    private var cancelled = false

    init(helper: URL, weightsURL: URL, width: Int, height: Int, neuralRendering: Bool = false) {
        self.neuralRendering = neuralRendering
        self.zeroMotion = neuralRendering ? Data(count: width * height * 2 * MemoryLayout<Float>.size) : nil
        process.executableURL = helper
        process.arguments = ["framegen-stream", "--weights", weightsURL.path,
            "--width", String(width), "--height", String(height),
            "--factor", "2", "--batch", "1", "--format", "u8"]
        if neuralRendering {
            process.arguments = ["stream", weightsURL.path, "--width", String(width), "--height", String(height),
                "--mode", "temporal", "--protocol-version", "4", "--output-format", "u8", "--execution", "metal-fused",
                "--precision", "float16", "--profile", "standard", "--processing-scale", "1",
                "--network-geometry", "vendor-aligned"]
        }
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
    }

    func terminate() {
        lock.withLock {
            cancelled = true
            if started && process.isRunning { process.terminate() }
        }
    }

    func run(frameCount: Int, prepare: (Int) throws -> Data) throws -> MLXBenchmarkSamples {
        guard frameCount == 61 else { throw RenderError.unavailable("MLX-DLSS needs 61 video frames.") }
        try Task.checkCancellation()
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        try lock.withLock {
            if cancelled { throw CancellationError() }
            try process.run()
            started = true
        }
        defer {
            try? input.fileHandleForWriting.close()
            if process.isRunning { process.terminate() }
            process.waitUntilExit()
        }
        let values = try MLXBenchmarkSamples.collect(frameCount: frameCount, prepare: prepare) { frame, seed in
            // Protocol 4: reset history (1), constant-one depth (4), packed RGB8 (8).
            // Reset every frame: the zero-motion plane never reprojects prior content.
            if neuralRendering { try input.fileHandleForWriting.write(contentsOf: Data([13, 0, 0, 0])) }
            try input.fileHandleForWriting.write(contentsOf: frame)
            if let zeroMotion { try input.fileHandleForWriting.write(contentsOf: zeroMotion) }
            if neuralRendering || !seed {
                try readExactly(frame.count, from: output.fileHandleForReading)
            }
        }
        try input.fileHandleForWriting.close()
        process.waitUntilExit()
        try Task.checkCancellation()
        guard process.terminationStatus == 0 else {
            throw RenderError.unavailable("MLX-DLSS helper exited with status \(process.terminationStatus); verify the selected weights.")
        }
        return values
    }

    private func readExactly(_ count: Int, from handle: FileHandle) throws {
        var remaining = count
        while remaining > 0 {
            try Task.checkCancellation()
            guard let data = try handle.read(upToCount: min(remaining, 1 << 20)), !data.isEmpty else {
                throw RenderError.unavailable("MLX-DLSS returned an incomplete frame; verify the selected weights.")
            }
            remaining -= data.count
        }

    }
}
