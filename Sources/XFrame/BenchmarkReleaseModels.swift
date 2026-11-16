import CryptoKit
import Foundation

enum BenchmarkReleaseModels {
    static let fgURL = URL(string: "https://github.com/txchen/xframe/releases/download/v0.1.2/framegen.safetensors")!
    static let nrURL = URL(string: "https://github.com/txchen/xframe/releases/download/v0.1.2/NeuralRendering-Small.zip")!
    static let nrArchiveSHA256 = "f550437620f190206ad93561ee37910896972bcff9a3399eb7f449f305052380"
    static let nrWeightsSHA256 = "c496209573133d430cc510c0ae424ba67a73fb1c957d96191e0227c42832607b"

    static func downloadNR(cache: SmallNRModelCache) async throws -> URL {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForResource = 600
        let session = URLSession(configuration: configuration, delegate: HTTPSModelRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (file, response) = try await session.download(from: nrURL)
        defer { try? FileManager.default.removeItem(at: file) }
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              http.url?.scheme == "https" else { throw BenchmarkModelCacheError.downloadFailed }
        let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= 120_000_000 else { throw BenchmarkModelCacheError.invalidModel }
        let digest = SHA256.hash(data: try Data(contentsOf: file, options: .mappedIfSafe)).map { String(format: "%02x", $0) }.joined()
        guard digest == nrArchiveSHA256 else { throw RenderError.unavailable("Small NR download checksum mismatch. Please retry.") }
        // Only the pinned, verified release archive reaches the extractor.
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("xframe-nr-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: folder) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", file.path, folder.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        try Task.checkCancellation()
        guard process.terminationStatus == 0 else { throw RenderError.unavailable("Cannot extract Small NR download.") }
        let model = folder.appendingPathComponent("NeuralRendering-Small.dlssmodel")
        guard try SmallNRModelCache.validate(model) == nrWeightsSHA256 else { throw BenchmarkModelCacheError.invalidModel }
        return try cache.importModel(from: model)
    }
}
