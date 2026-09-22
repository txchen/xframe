import Foundation

// XFrame post-processing after MetalFX, not a MetalFX quality setting.
enum SharpeningPreset: String, CaseIterable, Sendable {
    case off, low, medium, high
    static let preferenceKey = "XFrame.MetalFXSharpening"
    var title: String { rawValue.capitalized }
    var amount: Float {
        switch self { case .off: 0; case .low: 0.25; case .medium: 0.5; case .high: 0.85 }
    }
    static func load(from defaults: UserDefaults = .standard) -> Self {
        Self(rawValue: defaults.string(forKey: preferenceKey) ?? "") ?? .off
    }
    func save(to defaults: UserDefaults = .standard) { defaults.set(rawValue, forKey: Self.preferenceKey) }
}
