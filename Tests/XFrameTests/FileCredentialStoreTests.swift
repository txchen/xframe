import Foundation
import Testing
@testable import XFrame

@Test @MainActor func fileCredentialsRotateRestoreAndDeleteWithPrivatePermissions() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = FileCredentialStore(directory: root)
    #expect(try store.load() == nil)
    try store.save("test-refresh-one")
    let file = root.appendingPathComponent("microsoft-refresh-token")
    #expect((try FileManager.default.attributesOfItem(atPath: root.path)[.posixPermissions] as? NSNumber)?.intValue == 0o700)
    #expect((try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    #expect(try FileCredentialStore(directory: root).load() == "test-refresh-one")
    try store.save("test-refresh-two")
    #expect(try store.load() == "test-refresh-two")
    #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == ["microsoft-refresh-token"])
    try store.delete()
    #expect(try store.load() == nil)
    try store.delete()
}

@Test @MainActor func fileCredentialsRejectSymlinksAndPublicPermissions() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = FileCredentialStore(directory: root)
    try store.save("test-only")
    let file = root.appendingPathComponent("microsoft-refresh-token")
    try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
    #expect(throws: (any Error).self) { try store.load() }
    try store.delete()
    try FileManager.default.createSymbolicLink(at: file, withDestinationURL: root.appendingPathComponent("missing"))
    #expect(throws: (any Error).self) { try store.load() }
    try store.save("replacement")
    #expect(try store.load() == "replacement")
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
    #expect(throws: (any Error).self) { try store.load() }
    #expect(throws: (any Error).self) { try store.save("blocked") }
}
