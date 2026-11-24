import AppKit
import CryptoKit
import Foundation
import Observation
import SwiftUI

/// Bounded memory + disk cache for public Microsoft HTTPS game poster artwork.
@Observable
@MainActor
final class ArtworkCache {
    static let shared = ArtworkCache()
    static let defaultTTL: TimeInterval = 30 * 24 * 60 * 60

    private var images: [String: NSImage] = [:]
    @ObservationIgnored private var order: [String] = []
    @ObservationIgnored private var inFlight: Set<String> = []
    @ObservationIgnored private let directory: URL
    @ObservationIgnored private let ttl: TimeInterval
    @ObservationIgnored private let session: URLSession
    @ObservationIgnored private let maxMemoryEntries = 240

    init(
        directory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/XFrame/Cache/Artwork", isDirectory: true),
        ttl: TimeInterval = defaultTTL
    ) {
        self.directory = directory
        self.ttl = ttl
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config)
    }

    func cachedImage(for url: URL) -> NSImage? {
        images[Self.cacheKey(for: url)]
    }

    func load(_ url: URL, bypassCache: Bool = false) async {
        guard url.scheme?.lowercased() == "https" else { return }
        let key = Self.cacheKey(for: url)
        if !bypassCache, images[key] != nil { return }
        if !bypassCache, inFlight.contains(key) { return }
        inFlight.insert(key)
        defer { inFlight.remove(key) }

        let diskURL = directory.appendingPathComponent(key)
        if !bypassCache, let diskImage = await loadFromDisk(diskURL) {
            storeInMemory(diskImage, for: key)
            return
        }
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  data.count > 0, data.count <= 8_000_000,
                  let image = NSImage(data: data) else { return }
            storeInMemory(image, for: key)
            let dir = directory
            Task.detached(priority: .utility) {
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                try? data.write(to: diskURL, options: .atomic)
            }
        } catch {}
    }

    private func storeInMemory(_ image: NSImage, for key: String) {
        images[key] = image
        order.removeAll { $0 == key }
        order.append(key)
        if order.count > maxMemoryEntries {
            let evicted = order.removeFirst()
            images.removeValue(forKey: evicted)
        }
    }

    private func loadFromDisk(_ file: URL) async -> NSImage? {
        let ttl = self.ttl
        return await Task.detached(priority: .utility) {
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
                  let modified = attrs[.modificationDate] as? Date,
                  Date().timeIntervalSince(modified) < ttl,
                  let data = try? Data(contentsOf: file),
                  let image = NSImage(data: data) else { return nil }
            return image
        }.value
    }

    static func cacheKey(for url: URL) -> String {
        SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

struct CachedPosterImage: View {
    let url: URL?
    let revision: Int

    var body: some View {
        Group {
            if let url, let image = ArtworkCache.shared.cachedImage(for: url) {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    LinearGradient(colors: [LibraryStyle.surface, LibraryStyle.sidebar], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "gamecontroller").font(.system(size: 32)).foregroundStyle(.secondary)
                }
            }
        }
        .task(id: "\(url?.absoluteString ?? "")#\(revision)") {
            guard let url else { return }
            await ArtworkCache.shared.load(url, bypassCache: revision > 0)
        }
    }
}
