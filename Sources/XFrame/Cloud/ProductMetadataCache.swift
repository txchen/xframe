import Foundation

protocol ProductMetadataCaching: Sendable {
    func load(market: String) -> [String: CloudProductMetadata]
    func save(_ products: [String: CloudProductMetadata], market: String)
}

final class FileProductMetadataCache: ProductMetadataCaching, @unchecked Sendable {
    static let shared = FileProductMetadataCache()
    static let defaultTTL: TimeInterval = 7 * 24 * 60 * 60

    private struct Entry: Codable, Sendable {
        let metadata: CloudProductMetadata
        let cachedAt: Date
    }

    private struct Snapshot: Codable, Sendable {
        let version: Int
        let products: [String: Entry]
    }

    private let directory: URL
    private let ttl: TimeInterval
    private let now: @Sendable () -> Date
    private let lock = NSLock()
    private var memory: [String: [String: Entry]] = [:]

    init(
        directory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/XFrame/Cache", isDirectory: true),
        ttl: TimeInterval = defaultTTL,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.directory = directory
        self.ttl = ttl
        self.now = now
    }

    func load(market: String) -> [String: CloudProductMetadata] {
        let key = Self.sanitizedMarket(market)
        let current = now()
        return lock.withLock {
            let entries = validEntries(for: key, now: current)
            return entries.mapValues(\.metadata)
        }
    }

    func save(_ products: [String: CloudProductMetadata], market: String) {
        guard !products.isEmpty else { return }
        let key = Self.sanitizedMarket(market)
        let current = now()
        let snapshot: [String: Entry] = lock.withLock {
            var entries = validEntries(for: key, now: current)
            for (id, metadata) in products {
                entries[id] = Entry(metadata: metadata, cachedAt: current)
            }
            memory[key] = entries
            return entries
        }
        persist(snapshot, for: key)
    }

    private func validEntries(for key: String, now current: Date) -> [String: Entry] {
        let source: [String: Entry]
        if let cached = memory[key] {
            source = cached
        } else if let loaded = readFromDisk(for: key) {
            source = loaded
        } else {
            memory[key] = [:]
            return [:]
        }
        let filtered = source.filter { _, entry in
            let age = current.timeIntervalSince(entry.cachedAt)
            return age >= 0 && age < ttl
        }
        memory[key] = filtered
        return filtered
    }

    private func readFromDisk(for key: String) -> [String: Entry]? {
        let file = fileURL(for: key)
        guard let data = try? Data(contentsOf: file) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let snapshot = try? decoder.decode(Snapshot.self, from: data),
              snapshot.version == 1 else { return nil }
        return snapshot.products
    }

    private func persist(_ entries: [String: Entry], for key: String) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(Snapshot(version: 1, products: entries))
            try data.write(to: fileURL(for: key), options: .atomic)
        } catch {
            // Cache persistence is best-effort and must never break catalog loading.
        }
    }

    private func fileURL(for key: String) -> URL {
        directory.appendingPathComponent("catalog-metadata-\(key).json")
    }

    static func sanitizedMarket(_ raw: String) -> String {
        let cleaned = String(raw.uppercased().unicodeScalars.filter {
            ($0.value >= 65 && $0.value <= 90) || ($0.value >= 48 && $0.value <= 57) || $0 == "-"
        }.prefix(16))
        return cleaned.isEmpty ? "US" : cleaned
    }
}
