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
                        weightsURL: URL) async throws -> BenchmarkMeasurement {
        let id = "mlx\(height)"
        let title = "MLX-DLSS video \(height)p 30 → 60 fps"
        guard let helper = Bundle.main.executableURL?.deletingLastPathComponent()
            .appendingPathComponent("mlxdlss-benchmark"),
              FileManager.default.isExecutableFile(atPath: helper.path) else {
            return .unavailable(id, title, detail: "The optional MLX-DLSS helper is absent from this build.",
                                budgetMS: budgetMS)
        }
        let rgb = try makeRGBFrames(frames, width: width, height: height)
        let child = BenchmarkChild(helper: helper, weightsURL: weightsURL, width: width, height: height)
        let values = try await withTaskCancellationHandler {
            try child.run(frames: rgb)
        } onCancel: {
            child.terminate()
        }
        return .measured(id, title,
            detail: "55 adjacent moving-frame pairs after five warmups. Decode and RGB preparation are outside timing; each sample includes helper input/output transfer and MLX generation. Research video path, not live XFrame playback.",
            timing: "Helper round-trip wall", values: values, budgetMS: budgetMS)
    }

    private static func makeRGBFrames(_ frames: [CVPixelBuffer], width: Int, height: Int) throws -> [Data] {
        let context = CIContext(options: [.cacheIntermediates: false])
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        return try frames.map { buffer in
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

private final class BenchmarkChild: @unchecked Sendable {
    private let process = Process()
    private let input = Pipe(), output = Pipe(), errors = Pipe()
    private let lock = NSLock()
    private var started = false
    private var cancelled = false

    init(helper: URL, weightsURL: URL, width: Int, height: Int) {
        process.executableURL = helper
        process.arguments = ["framegen-stream", "--weights", weightsURL.path,
            "--width", String(width), "--height", String(height),
            "--factor", "2", "--batch", "1", "--format", "u8"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
    }

    func terminate() {
        lock.withLock {
            cancelled = true
            if started && process.isRunning { process.terminate() }
        }
    }

    func run(frames: [Data]) throws -> [Double] {
        guard frames.count == 61 else { throw RenderError.unavailable("MLX-DLSS needs 61 video frames.") }
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
        try input.fileHandleForWriting.write(contentsOf: frames[0])
        var values: [Double] = []
        for index in 1..<frames.count {
            try Task.checkCancellation()
            let started = CACurrentMediaTime()
            try input.fileHandleForWriting.write(contentsOf: frames[index])
            try readExactly(frames[index].count, from: output.fileHandleForReading)
            if index > 5 { values.append((CACurrentMediaTime() - started) * 1000) }
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
