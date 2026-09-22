import Foundation

// Selected mode persists; effective mode is derived from the current picture.
enum VideoScalingMode: String, CaseIterable, Codable, Sendable {
    case original, integer, metalFX
    static let preferenceKey = "XFrame.VideoScaling"
    var title: String {
        switch self { case .original: "Original"; case .integer: "Integer Scaling"; case .metalFX: "MetalFX Spatial" }
    }
}

struct ScalingExtent: Equatable, Codable, Sendable {
    let width, height: Int
    var title: String { "\(width)×\(height)" }
}

struct ScalingStatus: Equatable, Codable, Sendable {
    enum Bypass: String, Codable, Sendable {
        case windowed, nonInteger, noEnlargement, unsupported, initializationFailed
        var title: String {
            switch self {
            case .windowed: "Integer scaling requires fullscreen"
            case .nonInteger: "No exact integer fit"
            case .noEnlargement: "No enlargement needed"
            case .unsupported: "MetalFX unavailable"
            case .initializationFailed: "MetalFX initialization failed"
            }
        }
    }
    let selected: VideoScalingMode
    var effective: VideoScalingMode
    let source, output: ScalingExtent
    var bypass: Bypass?
    var title: String {
        let detail = bypass.map { " · \($0.title)" } ?? ""
        return "SCALE \(effective.title) · \(source.title) → \(output.title)\(detail)"
    }
}

struct ScalingPlan: Equatable {
    var status: ScalingStatus
    let x, y, width, height: Double

    static func make(mode: VideoScalingMode, source: ScalingExtent, canvas: ScalingExtent,
                     fullscreen: Bool, supported: Bool) -> Self {
        precondition(source.width > 0 && source.height > 0 && canvas.width > 0 && canvas.height > 0)
        let scale = min(Double(canvas.width) / Double(source.width), Double(canvas.height) / Double(source.height))
        let width = Double(source.width) * scale, height = Double(source.height) * scale
        let output = ScalingExtent(width: max(1, Int(width.rounded())), height: max(1, Int(height.rounded())))
        var status = ScalingStatus(selected: mode, effective: mode, source: source, output: output)
        if mode != .original {
            if scale <= 1 { status.bypass = .noEnlargement }
            else if mode == .integer {
                if !fullscreen { status.bypass = .windowed }
                else if abs(scale - scale.rounded()) > 0.000001 { status.bypass = .nonInteger }
            } else if !supported { status.bypass = .unsupported }
        }
        if status.bypass != nil { status.effective = .original }
        // Integer output starts on a backing-pixel boundary, including odd-sized black bars.
        let integer = status.effective == .integer
        return Self(status: status,
            x: integer ? floor((Double(canvas.width) - width) / 2) : (Double(canvas.width) - width) / 2,
            y: integer ? floor((Double(canvas.height) - height) / 2) : (Double(canvas.height) - height) / 2,
            width: width, height: height)
    }
}
