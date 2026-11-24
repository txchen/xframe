import Foundation
import GameController
import CoreHaptics

struct RumbleCommand: Equatable, Sendable {
    let gamepadIndex: UInt8
    let strong: Double
    let weak: Double
    let leftTrigger: Double
    let rightTrigger: Double
    let duration: TimeInterval
    let delay: TimeInterval
    let repeatCount: Int

    init(gamepadIndex: UInt8 = 0, strong: Double, weak: Double, leftTrigger: Double, rightTrigger: Double,
         duration: TimeInterval, delay: TimeInterval, repeatCount: Int) {
        self.gamepadIndex = gamepadIndex; self.strong = strong; self.weak = weak
        self.leftTrigger = leftTrigger; self.rightTrigger = rightTrigger
        self.duration = duration; self.delay = delay; self.repeatCount = repeatCount
    }

    var pulse: RumblePulse? {
        guard max(strong, weak, leftTrigger, rightTrigger) > 0 else { return nil }
        return RumblePulse(leftHandle: strong, rightHandle: weak,
                           leftTrigger: leftTrigger, rightTrigger: rightTrigger,
                           duration: min(30, max(0.03, duration)))
    }

    static func parse(_ data: Data) -> RumbleCommand? {
        let bytes = [UInt8](data)
        guard bytes.count >= 2 else { return nil }
        let flags = UInt16(bytes[0]) | UInt16(bytes[1]) << 8
        guard flags & 0x80 != 0 else { return nil }
        let offset = flags & 0x10 != 0 ? 10 : 2
        guard bytes.count >= offset + 11, bytes[offset] == 0, bytes[offset + 1] < 4 else { return nil }
        let duration = Int(bytes[offset + 6]) | Int(bytes[offset + 7]) << 8
        let delay = Int(bytes[offset + 8]) | Int(bytes[offset + 9]) << 8
        return RumbleCommand(gamepadIndex: bytes[offset + 1],
            strong: min(1, Double(bytes[offset + 2]) / 100),
            weak: min(1, Double(bytes[offset + 3]) / 100),
            leftTrigger: min(1, Double(bytes[offset + 4]) / 100),
            rightTrigger: min(1, Double(bytes[offset + 5]) / 100),
            duration: Double(duration) / 1000,
            delay: Double(delay) / 1000,
            repeatCount: Int(bytes[offset + 10]))
    }
}

struct RumblePulse: Equatable, Sendable {
    let leftHandle: Double
    let rightHandle: Double
    let leftTrigger: Double
    let rightTrigger: Double
    let duration: TimeInterval
    var defaultHandle: Double { max(leftHandle, rightHandle) }
}

@MainActor
final class ControllerRumble {
    private weak var controller: GCController?
    private var engines: [GCHapticsLocality: CHHapticEngine] = [:]
    private var startedLocalities: Set<GCHapticsLocality> = []
    private var players: [any CHHapticPatternPlayer] = []
    private var stopTask: Task<Void, Never>?
    private(set) var status = "No controller"

    func select(_ device: GCController?) {
        if controller === device { return }
        stop()
        engines.removeAll()
        startedLocalities.removeAll()
        controller = device
        guard let device else { status = "No controller"; return }
        guard let haptics = device.haptics else { status = "Controller haptics unavailable on this connection"; return }
        let localities = haptics.supportedLocalities
        let candidates: [GCHapticsLocality] = [.leftHandle, .rightHandle,
                          .leftTrigger, .rightTrigger]
        for locality in candidates where localities.contains(locality) {
            if let engine = haptics.createEngine(withLocality: locality) {
                configure(engine, locality: locality)
                engines[locality] = engine
            }
        }
        if engines.isEmpty, let engine = haptics.createEngine(withLocality: .default) {
            configure(engine, locality: .default)
            engines[.default] = engine
        }
        status = engines.isEmpty ? "Controller haptics unavailable on this connection" : "Controller haptics ready"
    }

    private func configure(_ engine: CHHapticEngine, locality: GCHapticsLocality) {
        engine.isAutoShutdownEnabled = true
        engine.resetHandler = { [weak self] in
            Task { @MainActor [weak self] in self?.startedLocalities.remove(locality) }
        }
        engine.stoppedHandler = { [weak self] _ in
            Task { @MainActor [weak self] in self?.startedLocalities.remove(locality) }
        }
    }

    func play(_ command: RumbleCommand) {
        stopPlayers()
        guard !engines.isEmpty, let pulse = command.pulse else { return }
        var hadError = false
        for (locality, engine) in engines {
            let intensity: Double
            switch locality {
            case .leftHandle: intensity = pulse.leftHandle
            case .rightHandle: intensity = pulse.rightHandle
            case .leftTrigger: intensity = pulse.leftTrigger
            case .rightTrigger: intensity = pulse.rightTrigger
            default: intensity = pulse.defaultHandle
            }
            guard intensity > 0 else { continue }
            do {
                if !startedLocalities.contains(locality) {
                    try engine.start()
                    startedLocalities.insert(locality)
                }
                let parameters = [CHHapticEventParameter(parameterID: .hapticIntensity, value: Float(intensity)),
                                  CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)]
                let event = CHHapticEvent(eventType: .hapticContinuous, parameters: parameters,
                                          relativeTime: 0, duration: pulse.duration)
                let pattern = try CHHapticPattern(events: [event], parameters: [])
                let player = try engine.makePlayer(with: pattern)
                try player.start(atTime: 0)
                players.append(player)
            } catch {
                startedLocalities.remove(locality)
                hadError = true
            }
        }
        status = hadError && players.isEmpty ? "Controller haptics could not play" : "Controller haptics ready"
        if !players.isEmpty {
            stopTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(pulse.duration + 0.1))
                guard !Task.isCancelled else { return }
                self?.stopPlayers()
            }
        }
    }

    func stop() {
        stopPlayers()
        startedLocalities.removeAll()
        for engine in engines.values { engine.stop(completionHandler: nil) }
    }

    private func stopPlayers() {
        stopTask?.cancel()
        stopTask = nil
        for player in players { try? player.stop(atTime: 0) }
        players.removeAll()
    }
}
