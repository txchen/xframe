import AVFoundation
import CoreImage
import CryptoKit
import Foundation

struct SmallNRModelCache: Sendable {
    let directory: URL
    init(directory: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/XFrame/BenchmarkModels/SmallNR")) {
        self.directory = directory
    }
    var modelURL: URL { directory.appendingPathComponent("NeuralRendering-Small.dlssmodel") }

    static func validate(_ url: URL) throws -> String {
        let manifestURL = url.appendingPathComponent("manifest.json")
        let weightsURL = url.appendingPathComponent("weights.safetensors")
        for (file, limit) in [(manifestURL, 4_000_000), (weightsURL, 600_000_000)] {
            let info = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard info.isRegularFile == true, info.isSymbolicLink != true,
                  let size = info.fileSize, size > 0, size <= limit else {
                throw RenderError.unavailable("Invalid Small NR package file.")
            }
        }
        let manifestData = try Data(contentsOf: manifestURL)
        let manifest = try JSONSerialization.jsonObject(with: manifestData) as? [String: Any]
        let weights = try Data(contentsOf: weightsURL, options: .mappedIfSafe)
        guard weights.count >= 8 else { throw RenderError.unavailable("Missing Small NR tensor header.") }
        let length = weights.withUnsafeBytes { $0.loadUnaligned(as: UInt64.self).littleEndian }
        guard length > 0, length <= 4_000_000, length <= weights.count - 8 else {
            throw RenderError.unavailable("Invalid Small NR tensor header.")
        }
        let header = try JSONSerialization.jsonObject(with: weights.subdata(in: 8..<(8 + Int(length)))) as? [String: Any]
        let metadata = header?["__metadata__"] as? [String: String]
        let digest = SHA256.hash(data: weights).map { String(format: "%02x", $0) }.joined()
        let receipt = manifest?["weights"] as? [String: Any]
        guard metadata?["topology"] == "2,2,2,2,2", receipt?["file"] as? String == "weights.safetensors",
              receipt?["sha256"] as? String == digest else {
            throw RenderError.unavailable("Choose the extracted Small NR package (31 blocks), with matching manifest and weights. HT and frame-generation models are not accepted.")
        }
        return digest
    }

    func cachedModel() throws -> URL? {
        guard FileManager.default.fileExists(atPath: modelURL.path) else { return nil }
        _ = try Self.validate(modelURL)
        return modelURL
    }

    func importModel(from source: URL) throws -> URL {
        _ = try Self.validate(source)
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700])
        let staging = directory.appendingPathComponent(UUID().uuidString + ".dlssmodel")
        try manager.createDirectory(at: staging, withIntermediateDirectories: false,
                                    attributes: [.posixPermissions: 0o700])
        defer { try? manager.removeItem(at: staging) }
        for name in ["manifest.json", "weights.safetensors"] {
            try manager.copyItem(at: source.appendingPathComponent(name), to: staging.appendingPathComponent(name))
        }
        _ = try Self.validate(staging)
        if manager.fileExists(atPath: modelURL.path) {
            _ = try manager.replaceItemAt(modelURL, withItemAt: staging)
        } else { try manager.moveItem(at: staging, to: modelURL) }
        return modelURL
    }
}

enum SmallNRBenchmark {
    static let upstream = "7870371e8bf6c03967213f1a5d40db6c5a3bee38"
    static let budgetMS = 1000.0 / 30.0

    static func measure(frames: [CVPixelBuffer], width: Int, height: Int, modelURL: URL) async throws -> [BenchmarkMeasurement] {
        let id = "nrSmall\(height)", title = "Small NR \(height)p · independent frames"
        guard let helper = Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("mlxdlss-benchmark"),
              FileManager.default.isExecutableFile(atPath: helper.path) else {
            return [.unavailable(id, title, detail: "The MLX-DLSS helper is absent from this build.", budgetMS: budgetMS)]
        }
        let child = BenchmarkChild(helper: helper, weightsURL: modelURL, width: width, height: height, neuralRendering: true)
        let context = CIContext(options: [.cacheIntermediates: false])
        let values = try await withTaskCancellationHandler {
            try child.run(frameCount: frames.count) { index in
                try MLXFrameGenerationBenchmark.makeRGBFrame(frames[index], width: width, height: height, context: context)
            }
        } onCancel: { child.terminate() }
        return [
            .measured(id, title, detail: "\(values.helper.count) moving frames after six warmups. Small 31-block network, FP16, Metal fused, standard profile, scale 1. GPU preprocessing and composition, packed RGB8 readback. Includes IPC and inference; excludes RGB preparation. History resets each frame; zero motion and constant depth are placeholders.",
                      timing: "Helper round-trip wall", values: values.helper, budgetMS: budgetMS),
            .measured("nrSmallEndToEnd\(height)", title + " + RGB preparation",
                      detail: "Includes resize, RGB packing, guide transfer, GPU preprocessing, inference, composition and RGB8 readback. Excludes decode, startup and display. Budget is 30 source frames/s; independent-frame research test, not live temporal NR.",
                      timing: "Preparation + helper wall", values: values.endToEnd, budgetMS: budgetMS)
        ]
    }
}
