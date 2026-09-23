import Foundation
import GameController

@MainActor
final class NativeGamepad {
    private var controller: GCController?
    private let rumble = ControllerRumble()
    var rumbleStatus: String { rumble.status }
    func vibrate(_ command: RumbleCommand) { rumble.play(command) }
    func stopRumble() { rumble.stop() }
    private let systemGestures = GamepadSystemGestures()
    var capturesSystemGestures = false {
        didSet { updateSystemGestures() }
    }
    private func updateSystemGestures() {
        guard capturesSystemGestures, let pad = controller?.extendedGamepad else {
            systemGestures.restore()
            return
        }
        systemGestures.capture([pad.buttonMenu, pad.buttonOptions].compactMap { $0 })
    }
    var changed: ((GamepadSnapshot) -> Void)?
    var replaced: (() -> Void)?
    var name: String? { controller?.vendorName }
    var connected: Bool { controller != nil }

    func refresh() {
        let devices = GCController.controllers().filter { $0.extendedGamepad != nil && !$0.isSnapshot }
        if let controller, devices.contains(where: { $0 === controller }) { return }
        controller?.extendedGamepad?.valueChangedHandler = nil
        systemGestures.restore()
        controller = devices.first
        rumble.select(controller)
        updateSystemGestures()
        replaced?()
        guard let controller, let pad = controller.extendedGamepad else { return }
        controller.handlerQueue = .main
        pad.valueChangedHandler = { [weak self] pad, _ in
            MainActor.assumeIsolated {
                guard let self, pad === self.controller?.extendedGamepad else { return }
                self.changed?(Self.snapshot(pad))
            }
        }
    }

    func sample() -> GamepadSnapshot {
        guard let pad = controller?.extendedGamepad else { return GamepadSnapshot() }
        return Self.snapshot(pad)
    }

    func stop() {
        systemGestures.restore()
        controller?.extendedGamepad?.valueChangedHandler = nil
        controller = nil
        rumble.select(nil)
        changed = nil
        replaced = nil
    }

    static func snapshot(_ pad: GCExtendedGamepad) -> GamepadSnapshot {
        let inputs: [(GamepadButton, GCControllerButtonInput?)] = [
            (.a, pad.buttonA), (.b, pad.buttonB), (.x, pad.buttonX), (.y, pad.buttonY),
            (.up, pad.dpad.up), (.down, pad.dpad.down), (.left, pad.dpad.left), (.right, pad.dpad.right),
            (.leftShoulder, pad.leftShoulder), (.rightShoulder, pad.rightShoulder),
            (.leftThumb, pad.leftThumbstickButton), (.rightThumb, pad.rightThumbstickButton),
            (.menu, pad.buttonMenu), (.view, pad.buttonOptions), (.nexus, pad.buttonHome)
        ]
        return GamepadSnapshot(buttons: Set(inputs.compactMap { $0.1?.isPressed == true ? $0.0 : nil }),
            leftX: Double(pad.leftThumbstick.xAxis.value), leftY: -Double(pad.leftThumbstick.yAxis.value),
            rightX: Double(pad.rightThumbstick.xAxis.value), rightY: -Double(pad.rightThumbstick.yAxis.value),
            leftTrigger: Double(pad.leftTrigger.value), rightTrigger: Double(pad.rightTrigger.value))
    }
}
