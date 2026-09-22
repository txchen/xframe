import Foundation
import Testing
@testable import XFrame

@Test func streamPreferencesPersistAndInvalidFieldsFallBackIndependently() throws {
    let suite = "XFrameTests.StreamPreferences.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = CloudStreamPreferencesStore(defaults: defaults)
    #expect(store.load() == CloudStreamPreferences())
    let selected = CloudStreamPreferences(quality: .hq, language: .simplifiedChinese)
    store.save(selected)
    #expect(CloudStreamPreferencesStore(defaults: defaults).load() == selected)
    defaults.set("unsupported", forKey: "XFrame.StreamQuality")
    #expect(store.load() == CloudStreamPreferences(quality: .standard, language: .simplifiedChinese))
    defaults.set("unsupported", forKey: "XFrame.GameLanguage")
    #expect(store.load() == CloudStreamPreferences())
}

@Test func pacingPreferencePersistsAndUnknownValueUsesBalanced() throws {
    let suite = "XFrameTests.Pacing.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = CloudStreamPreferencesStore(defaults: defaults)
    let chosen = CloudStreamPreferences(quality: .hq, language: .japanese, framePacing: .lowLatency)
    store.save(chosen)
    #expect(store.load() == chosen)
    defaults.set("future-mode", forKey: "XFrame.FramePacing")
    #expect(store.load() == CloudStreamPreferences(quality: .hq, language: .japanese))
}
