import Foundation

enum BenchmarkWorkload: String, CaseIterable, Sendable, Identifiable {
    case spatial1440, spatial4k, spatial4kSharpen
    case vt720, vt1080, vt1440
    case coreml720, coreml1080Balanced, coreml1080Quality, coreml1440Balanced, coreml1440Quality
    case mlx720, mlx1080, mlx1440
    case nrSmall720, nrSmall1080, nrSmall1440
    var id: String { rawValue }
    var title: String {
        switch self {
        case .spatial1440: "1440p"
        case .spatial4k: "4K"
        case .spatial4kSharpen: "4K + High sharpening"
        case .coreml720: CoreMLFGProfile.p720.shortTitle
        case .coreml1080Balanced: CoreMLFGProfile.p1080Balanced.shortTitle
        case .coreml1080Quality: CoreMLFGProfile.p1080Quality.shortTitle
        case .coreml1440Balanced: CoreMLFGProfile.p1440Balanced.shortTitle
        case .coreml1440Quality: CoreMLFGProfile.p1440Quality.shortTitle
        default: rawValue.hasSuffix("720") ? "720p" : rawValue.hasSuffix("1080") ? "1080p" : "1440p"
        }
    }
    var group: String {
        if rawValue.hasPrefix("spatial") { return "MetalFX scaling" }
        if rawValue.hasPrefix("vt") { return "VideoToolbox interpolation" }
        if rawValue.hasPrefix("coreml") { return "Core ML frame generation · ANE + Metal" }
        if rawValue.hasPrefix("mlx") { return "MLX frame generation" }
        return "Small NR · research"
    }
}

enum BenchmarkLength: String, CaseIterable, Sendable {
    case quick, standard
    var samples: Int { self == .quick ? 15 : 55 }
    var title: String { self == .quick ? "Quick · 15 samples" : "Standard · 55 samples" }
}

struct BenchmarkSelection: Sendable {
    var workloads: Set<BenchmarkWorkload> = [.spatial1440, .spatial4k, .spatial4kSharpen, .vt720, .vt1080]
    var length: BenchmarkLength = .quick
    func contains(_ id: String) -> Bool { BenchmarkWorkload(rawValue: id).map(workloads.contains) ?? false }
    var needsFG: Bool { workloads.contains { $0.rawValue.hasPrefix("mlx") || $0.rawValue.hasPrefix("coreml") } }
    var needsCoreMLFG: Bool { workloads.contains { $0.rawValue.hasPrefix("coreml") } }
    var needsMLXFG: Bool { workloads.contains { $0.rawValue.hasPrefix("mlx") } }
    var needsNR: Bool { workloads.contains { $0.rawValue.hasPrefix("nrSmall") } }
}
