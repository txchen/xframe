import Foundation

enum CloudStreamQuality: String, CaseIterable, Sendable {
    case standard, hq
    var title: String { self == .standard ? "Standard (1080p)" : "HQ (1440p / 4K)" }
    var osName: String { self == .standard ? "macos" : "tizen" }
    var width: Int { self == .standard ? 1920 : 4096 }
    var height: Int { self == .standard ? 1080 : 2160 }
    var maxMacroblocksPerFrame: Int? { self == .standard ? 8160 : nil }
    var maxMacroblocksPerSecond: Int? { self == .standard ? 489_600 : nil }
    var supportsCustomResolution: Bool { self == .hq }
}

enum CloudGameLanguage: String, CaseIterable, Sendable {
    case english = "en-US", simplifiedChinese = "zh-CN", traditionalChinese = "zh-TW"
    case japanese = "ja-JP", korean = "ko-KR", french = "fr-FR", german = "de-DE"
    case spanish = "es-ES", italian = "it-IT", portuguese = "pt-BR"
    var title: String {
        switch self {
        case .english: "English"
        case .simplifiedChinese: "简体中文"
        case .traditionalChinese: "繁體中文"
        case .japanese: "日本語"
        case .korean: "한국어"
        case .french: "Français"
        case .german: "Deutsch"
        case .spanish: "Español"
        case .italian: "Italiano"
        case .portuguese: "Português (Brasil)"
        }
    }
}

enum CloudMaxBitrate: Int, CaseIterable, Sendable {
    case auto = 0
    case mbps10 = 10
    case mbps15 = 15
    case mbps20 = 20
    case mbps30 = 30
    case mbps50 = 50
    var title: String { self == .auto ? "Auto" : "\(rawValue) Mbps" }
}

struct CloudStreamPreferences: Equatable, Sendable {
    var quality: CloudStreamQuality = .standard
    var language: CloudGameLanguage = .english
    var framePacing: FramePacingMode = .balanced
    var maxBitrate: CloudMaxBitrate = .auto
    var summary: String {
        let base = "\(quality.title) · \(language.title) · \(framePacing.title)"
        return maxBitrate == .auto ? base : "\(base) · \(maxBitrate.title)"
    }
}

struct CloudStreamPreferencesStore {
    let defaults: UserDefaults
    func load() -> CloudStreamPreferences {
        CloudStreamPreferences(
            quality: defaults.string(forKey: "XFrame.StreamQuality").flatMap(CloudStreamQuality.init(rawValue:)) ?? .standard,
            language: defaults.string(forKey: "XFrame.GameLanguage").flatMap(CloudGameLanguage.init(rawValue:)) ?? .english,
            framePacing: defaults.string(forKey: "XFrame.FramePacing").flatMap(FramePacingMode.init(rawValue:)) ?? .balanced,
            maxBitrate: CloudMaxBitrate(rawValue: defaults.integer(forKey: "XFrame.MaxBitrateMbps")) ?? .auto)
    }
    func save(_ value: CloudStreamPreferences) {
        defaults.set(value.framePacing.rawValue, forKey: "XFrame.FramePacing")
        defaults.set(value.quality.rawValue, forKey: "XFrame.StreamQuality")
        defaults.set(value.language.rawValue, forKey: "XFrame.GameLanguage")
        defaults.set(value.maxBitrate.rawValue, forKey: "XFrame.MaxBitrateMbps")
    }
}
