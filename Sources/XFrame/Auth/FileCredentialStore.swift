import Foundation
import Darwin

enum CredentialFileError: Error, LocalizedError {
    case unavailable
    var errorDescription: String? { "Cannot access the local sign-in file securely. Check its ownership and permissions." }
}

// Temporary development storage. Owner-only permissions are not encryption.
// Never fall back to Keychain or print file contents on failure.
@MainActor
struct FileCredentialStore: CredentialStore {
    let directory: URL
    private let filename = "microsoft-refresh-token"
    init(directory: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/XFrame/Credentials", isDirectory: true)) {
        self.directory = directory
    }

    private func openDirectory(create: Bool) throws -> Int32? {
        if create {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
        }
        let fd = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        if fd < 0 {
            if !create && errno == ENOENT { return nil }
            throw CredentialFileError.unavailable
        }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_uid == geteuid(),
              info.st_mode & 0o077 == 0 else {
            close(fd); throw CredentialFileError.unavailable
        }
        return fd
    }

    func load() throws -> String? {
        guard let dir = try openDirectory(create: false) else { return nil }
        defer { close(dir) }
        let fd = openat(dir, filename, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        if fd < 0 {
            if errno == ENOENT { return nil }
            throw CredentialFileError.unavailable
        }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_uid == geteuid(),
              info.st_mode & S_IFMT == S_IFREG, info.st_mode & 0o077 == 0,
              info.st_nlink == 1, info.st_size > 0, info.st_size <= 65536 else {
            throw CredentialFileError.unavailable
        }
        var bytes = [UInt8](repeating: 0, count: Int(info.st_size))
        let count = bytes.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
        guard count == bytes.count, let token = String(bytes: bytes, encoding: .utf8), !token.isEmpty else {
            throw CredentialFileError.unavailable
        }
        return token
    }

    func save(_ refreshToken: String) throws {
        let data = Data(refreshToken.utf8)
        guard !data.isEmpty, data.count <= 65536, let dir = try openDirectory(create: true) else {
            throw CredentialFileError.unavailable
        }
        defer { close(dir) }
        let temporary = ".refresh-\(UUID().uuidString)"
        let fd = openat(dir, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw CredentialFileError.unavailable }
        defer { close(fd); unlinkat(dir, temporary, 0) }
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw CredentialFileError.unavailable }
                offset += count
            }
        }
        guard fsync(fd) == 0, renameat(dir, temporary, dir, filename) == 0 else {
            throw CredentialFileError.unavailable
        }
    }

    func delete() throws {
        guard let dir = try openDirectory(create: false) else { return }
        defer { close(dir) }
        guard unlinkat(dir, filename, 0) == 0 || errno == ENOENT else { throw CredentialFileError.unavailable }
    }
}
