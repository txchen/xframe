import Foundation
import GameController
import CoreHaptics

struct RumbleCommand: Equatable, Sendable {
    let strong: Double
    let weak: Double
    let leftTrigger: Double
    let rightTrigger: Double
    let duration: TimeInterval
    let delay: TimeInterval
    let repeatCount: Int

    static func parse(_ data: Data) -> RumbleCommand? {
        let bytes = [UInt8](data)
        guard bytes.count >= 2 else { return nil }
        let flags = UInt16(bytes[0]) | UInt16(bytes[1]) << 8
        guard flags & 0x80 != 0 else { return nil }
        let offset = flags & 0x10 != 0 ? 10 : 2
        guard bytes.count >= offset + 11, bytes[offset] == 0, bytes[offset + 1] == 0 else { return nil }
        let duration = Int(bytes[offset + 6]) | Int(bytes[offset + 7]) << 8
        let delay = Int(bytes[offset + 8]) | Int(bytes[offset + 9]) << 8
        return RumbleCommand(strong: min(1, Double(bytes[offset + 2]) / 100),
            weak: min(1, Double(bytes[offset + 3]) / 100),
            leftTrigger: min(1, Double(bytes[offset + 4]) / 100),
            rightTrigger: min(1, Double(bytes[offset + 5]) / 100),
            duration: Double(min(duration, 2000)) / 1000,
            delay: Double(min(delay, 2000)) / 1000,
            repeatCount: min(Int(bytes[offset + 10]), 3))
    }
}

@MainActor
final class ControllerRumble {
    private weak var controller: GCController?
    private var engines: [GCHapticsLocality: CHHapticEngine] = [:]
    private var players: [any CHHapticPatternPlayer] = []
    private(set) var status = "No controller"

    func select(_ device: GCController?) {
        if controller === device { return }
        stop()
        engines.removeAll()
        controller = device
        guard let device else { status = "No controller"; return }
        guard let haptics = device.haptics else { status = "Controller haptics unavailable on this connection"; return }
        let localities = haptics.supportedLocalities
        let candidates: [GCHapticsLocality] = [.leftHandle, .rightHandle,
                          .leftTrigger, .rightTrigger]
        for locality in candidates where localities.contains(locality) {
            if let engine = haptics.createEngine(withLocality: locality) { engines[locality] = engine }
        }
        if engines.isEmpty, let engine = haptics.createEngine(withLocality: .default) {
            engines[.default] = engine
        }
        status = engines.isEmpty ? "Controller haptics unavailable on this connection" : "Controller haptics ready"
    }

    func play(_ command: RumbleCommand) {
        guard !engines.isEmpty else { return }
        players.removeAll()
        let handles = max(command.strong, command.weak)
        if max(handles, max(command.leftTrigger, command.rightTrigger)) == 0 || command.duration == 0 {
            stop()
            return
        }
        for (locality, engine) in engines {
            let intensity: Double
            switch locality {
            case .leftHandle: intensity = command.strong
            case .rightHandle: intensity = command.weak
            case .leftTrigger: intensity = command.leftTrigger
            case .rightTrigger: intensity = command.rightTrigger
            default: intensity = max(handles, max(command.leftTrigger, command.rightTrigger))
            }
            guard intensity > 0, command.duration > 0 else { continue }
            do {
                try engine.start()
                let parameters = [CHHapticEventParameter(parameterID: .hapticIntensity, value: Float(intensity)),
                                  CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)]
                let events = (0...command.repeatCount).map { index in
                    CHHapticEvent(eventType: .hapticContinuous, parameters: parameters,
                                  relativeTime: command.delay + Double(index) * (command.delay + command.duration),
                                  duration: command.duration)
                }
                let pattern = try CHHapticPattern(events: events, parameters: [])
                let player = try engine.makePlayer(with: pattern)
                try player.start(atTime: 0)
                players.append(player)
            } catch { status = "Controller haptics could not play" }
        }
    }

    func stop() {
        players.removeAll()
        for engine in engines.values { engine.stop(completionHandler: nil) }
    }
}
