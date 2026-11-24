import Foundation
import GameController

@MainActor
final class NativeGamepad {
    static let maxControllers = 4
    private var slots: [GCController?] = Array(repeating: nil, count: maxControllers)
    private let rumbles: [ControllerRumble] = (0..<maxControllers).map { _ in ControllerRumble() }
    private let systemGestures: [GamepadSystemGestures] = (0..<maxControllers).map { _ in GamepadSystemGestures() }

    var rumbleStatus: String { rumbles[0].status }
    func vibrate(_ command: RumbleCommand) {
        let slot = Int(command.gamepadIndex)
        if slot >= 0 && slot < Self.maxControllers && slots[slot] != nil {
            rumbles[slot].play(command)
        } else {
            rumbles[0].play(command)
        }
    }
    func stopRumble() {
        for r in rumbles { r.stop() }
    }

    var capturesSystemGestures = false {
        didSet {
            for slot in 0..<Self.maxControllers { updateSystemGestures(slot: slot) }
        }
    }

    private func updateSystemGestures(slot: Int) {
        guard capturesSystemGestures, let pad = slots[slot]?.extendedGamepad else {
            systemGestures[slot].restore()
            return
        }
        systemGestures[slot].capture([pad.buttonMenu, pad.buttonOptions, pad.buttonHome].compactMap { $0 })
    }

    var changed: ((GamepadSnapshot) -> Void)?
    var replaced: (() -> Void)?
    var slotChanged: ((Int, GamepadSnapshot) -> Void)?
    var slotReplaced: ((Int) -> Void)?
    var name: String? { slots[0]?.vendorName }
    var connected: Bool { slots[0] != nil }
    var connectedCount: Int { slots.compactMap { $0 }.count }
    func isConnected(slot: Int) -> Bool { slot >= 0 && slot < Self.maxControllers && slots[slot] != nil }

    func refresh() {
        let devices = GCController.controllers().filter { $0.extendedGamepad != nil && !$0.isSnapshot }
        // Detach disconnected controllers from their slots first.
        for slot in 0..<Self.maxControllers {
            if let existing = slots[slot], !devices.contains(where: { $0 === existing }) {
                detach(slot: slot)
            }
        }
        // Assign newly connected controllers to free slots (up to 4).
        for device in devices {
            if slots.contains(where: { $0 === device }) { continue }
            guard let freeSlot = slots.firstIndex(where: { $0 == nil }) else { break }
            attach(device, to: freeSlot)
        }
    }

    private func detach(slot: Int) {
        slots[slot]?.extendedGamepad?.valueChangedHandler = nil
        systemGestures[slot].restore()
        slots[slot] = nil
        rumbles[slot].select(nil)
        if slot == 0 { replaced?() }
        slotReplaced?(slot)
    }

    private func attach(_ controller: GCController, to slot: Int) {
        slots[slot] = controller
        rumbles[slot].select(controller)
        updateSystemGestures(slot: slot)
        if slot == 0 { replaced?() }
        slotReplaced?(slot)
        guard let pad = controller.extendedGamepad else { return }
        controller.handlerQueue = .main
        pad.valueChangedHandler = { [weak self] pad, _ in
            MainActor.assumeIsolated {
                guard let self, pad === self.slots[slot]?.extendedGamepad else { return }
                let snap = Self.snapshot(pad)
                if slot == 0 { self.changed?(snap) }
                self.slotChanged?(slot, snap)
            }
        }
    }

    func sample(slot: Int = 0) -> GamepadSnapshot {
        guard slot >= 0, slot < Self.maxControllers, let pad = slots[slot]?.extendedGamepad else { return GamepadSnapshot() }
        return Self.snapshot(pad)
    }

    func stop() {
        for slot in 0..<Self.maxControllers {
            systemGestures[slot].restore()
            slots[slot]?.extendedGamepad?.valueChangedHandler = nil
            slots[slot] = nil
            rumbles[slot].select(nil)
        }
        changed = nil
        replaced = nil
        slotChanged = nil
        slotReplaced = nil
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
