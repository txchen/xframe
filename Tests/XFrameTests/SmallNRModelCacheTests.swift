import CryptoKit
import Foundation
import Testing
@testable import XFrame

@Test func smallNRImportValidatesTopologyAndIntegrity() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("source.dlssmodel")
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    func writePackage(topology: String) throws {
        let header = try JSONSerialization.data(withJSONObject: ["__metadata__": ["topology": topology]])
        var size = UInt64(header.count).littleEndian
        var weights = withUnsafeBytes(of: &size) { Data($0) }
        weights.append(header)
        let digest = SHA256.hash(data: weights).map { String(format: "%02x", $0) }.joined()
        try weights.write(to: source.appendingPathComponent("weights.safetensors"))
        try JSONSerialization.data(withJSONObject: ["weights": ["file": "weights.safetensors", "sha256": digest]])
            .write(to: source.appendingPathComponent("manifest.json"))
    }
    let cache = SmallNRModelCache(directory: root.appendingPathComponent("cache"))
    try writePackage(topology: "4,4,6,8,8")
    #expect(throws: (any Error).self) { try cache.importModel(from: source) }
    #expect(try cache.cachedModel() == nil)
    try writePackage(topology: "2,2,2,2,2")
    let imported = try cache.importModel(from: source)
    #expect(try cache.cachedModel() == imported)
    #expect(try cache.importModel(from: source) == imported)
    try Data([0]).write(to: source.appendingPathComponent("weights.safetensors"))
    #expect(throws: (any Error).self) { try cache.importModel(from: source) }
    #expect(try cache.cachedModel() == imported)
    try Data([0]).write(to: imported.appendingPathComponent("weights.safetensors"))
    #expect(throws: (any Error).self) { try cache.cachedModel() }
}
