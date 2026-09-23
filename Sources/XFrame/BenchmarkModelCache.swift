import CryptoKit
import Darwin
import Foundation

enum BenchmarkModelCacheError: LocalizedError {
    case invalidModel
    case invalidURL
    case downloadFailed
    case storageFailed

    var errorDescription: String? {
        switch self {
        case .invalidModel: "The file is not the supported DLSS 310.7.0 frame-generation model (SHA-256 mismatch)."
        case .invalidURL: "Enter an HTTPS URL for the supported frame-generation model."
        case .downloadFailed: "The model download failed. Check the HTTPS URL and try again."
        case .storageFailed: "Cannot securely store the model in XFrame's local cache."
        }
    }
}

struct BenchmarkModelCache: Sendable {
    static let expectedSHA256 = "21faede75312631273f930a6fc1aed17f1eb5ac4a476a485551afc6d7ced2958"
    private static let maxBytes = 5_000_000
    let directory: URL
    let expectedSHA256: String

    init(directory: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/XFrame/BenchmarkModels", isDirectory: true),
         expectedSHA256: String = Self.expectedSHA256) {
        self.directory = directory
        self.expectedSHA256 = expectedSHA256
    }

    var modelURL: URL { directory.appendingPathComponent("framegen-310.7.0.safetensors") }

    func cachedModel() throws -> URL? {
        var info = stat()
        if lstat(modelURL.path, &info) < 0 {
            if errno == ENOENT { return nil }
            throw BenchmarkModelCacheError.storageFailed
        }
        guard info.st_mode & S_IFMT == S_IFREG, info.st_uid == geteuid(),
              info.st_mode & 0o077 == 0, info.st_nlink == 1,
              info.st_size > 0, info.st_size <= Self.maxBytes else {
            throw BenchmarkModelCacheError.storageFailed
        }
        let data = try Data(contentsOf: modelURL)
        guard digest(data) == expectedSHA256 else { throw BenchmarkModelCacheError.invalidModel }
        return modelURL
    }

    func importModel(from source: URL) throws -> URL {
        let data = try Data(contentsOf: source)
        return try store(data)
    }

    func download(from remote: URL) async throws -> URL {
        guard remote.scheme?.lowercased() == "https", remote.host != nil,
              remote.user == nil, remote.password == nil else {
            throw BenchmarkModelCacheError.invalidURL
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForResource = 120
        let session = URLSession(configuration: configuration, delegate: HTTPSModelRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: remote)
        request.timeoutInterval = 60
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let downloaded: (URL, URLResponse)
        do {
            downloaded = try await session.download(for: request)
        } catch {
            throw BenchmarkModelCacheError.downloadFailed
        }
        let (temporary, response) = downloaded
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              http.url?.scheme?.lowercased() == "https" else {
            throw BenchmarkModelCacheError.downloadFailed
        }
        let size = try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= Self.maxBytes else { throw BenchmarkModelCacheError.invalidModel }
        return try store(Data(contentsOf: temporary))
    }

    func remove() throws {
        if FileManager.default.fileExists(atPath: modelURL.path) {
            try FileManager.default.removeItem(at: modelURL)
        }
    }

    private func store(_ data: Data) throws -> URL {
        guard !data.isEmpty, data.count <= Self.maxBytes,
              digest(data) == expectedSHA256 else { throw BenchmarkModelCacheError.invalidModel }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            var info = stat()
            guard lstat(directory.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR,
                  info.st_uid == geteuid(), info.st_mode & 0o077 == 0 else {
                throw BenchmarkModelCacheError.storageFailed
            }
            let temporary = directory.appendingPathComponent(".framegen-\(UUID().uuidString)")
            let fd = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
            guard fd >= 0 else { throw BenchmarkModelCacheError.storageFailed }
            defer { close(fd); unlink(temporary.path) }
            try data.withUnsafeBytes { bytes in
                var offset = 0
                while offset < bytes.count {
                    let count = write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                    if count < 0 && errno == EINTR { continue }
                    guard count > 0 else { throw BenchmarkModelCacheError.storageFailed }
                    offset += count
                }
            }
            guard fsync(fd) == 0, rename(temporary.path, modelURL.path) == 0 else {
                throw BenchmarkModelCacheError.storageFailed
            }
            return modelURL
        } catch let error as BenchmarkModelCacheError {
            throw error
        } catch {
            throw BenchmarkModelCacheError.storageFailed
        }
    }

    private func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

private final class HTTPSModelRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url?.scheme?.lowercased() == "https" ? request : nil)
    }
}
