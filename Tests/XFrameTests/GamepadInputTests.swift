import Foundation
import GameController
import Testing
@testable import XFrame

@Test func gamepadRetriesPreservePressReleaseOrderAndSequence() {
    var input = GamepadInput()
    input.update(GamepadSnapshot(), ownsInput: true)
    _ = input.send(timestampMS: 0) { _ in true }
    input.update(GamepadSnapshot(buttons: [.a]), ownsInput: true)
    input.update(GamepadSnapshot(), ownsInput: true)
    let rejected = input.send(timestampMS: 1) { _ in false }
    #expect(!rejected && input.encoder.sequence == 1 && input.queue.count == 2)
    var packets: [Data] = []
    _ = input.send(timestampMS: 2) { packets.append($0); return true }
    _ = input.send(timestampMS: 3) { packets.append($0); return true }
    #expect(packets.map { $0[16] } == [0x10, 0])
    #expect(input.encoder.sequence == 3 && input.queue.isEmpty)
}

@Test func gamepadFocusLossPrioritizesNeutralAndRequiresRelease() {
    var input = GamepadInput()
    input.update(GamepadSnapshot(), ownsInput: true)
    _ = input.send(timestampMS: 0) { _ in true }
    input.update(GamepadSnapshot(buttons: [.a]), ownsInput: true)
    input.update(GamepadSnapshot(buttons: [.b]), ownsInput: true)
    input.update(GamepadSnapshot(buttons: [.b]), ownsInput: false)
    #expect(input.queue.isEmpty && input.needsNeutral && !input.armed)
    _ = input.send(timestampMS: 1) { _ in false }
    #expect(input.needsNeutral)
    var packet = Data()
    _ = input.send(timestampMS: 2) { packet = $0; return true }
    #expect(packet[16] == 0 && packet[17] == 0)
    input.update(GamepadSnapshot(buttons: [.b]), ownsInput: true)
    #expect(!input.armed && input.queue.isEmpty)
    input.update(GamepadSnapshot(), ownsInput: true)
    input.update(GamepadSnapshot(buttons: [.b]), ownsInput: true)
    #expect(input.armed && input.queue.count == 1)
}

@Test func gamepadOverflowAndDeviceReplacementCannotReplayOldPresses() {
    var input = GamepadInput()
    input.update(GamepadSnapshot(), ownsInput: true)
    for index in 0...GamepadInput.capacity {
        input.update(GamepadSnapshot(buttons: index.isMultiple(of: 2) ? [.a] : []), ownsInput: true)
    }
    #expect(input.queue.isEmpty && input.needsNeutral && !input.armed)
    input.update(GamepadSnapshot(), ownsInput: true)
    input.update(GamepadSnapshot(buttons: [.a]), ownsInput: true)
    input.release() // same path for disconnect, replacement, disable and close
    #expect(input.queue.isEmpty && !input.armed && input.needsNeutral)
    let newSession = GamepadInput()
    #expect(newSession.encoder.sequence == 0 && newSession.needsNeutral)
}

@Test @MainActor func nativeGamepadMapsButtonsTriggersAndUpwardAxes() throws {
    let controller = GCController.withExtendedGamepad()
    let pad = try #require(controller.extendedGamepad)
    let buttons: [(GamepadButton, GCControllerButtonInput?)] = [
        (.a, pad.buttonA), (.b, pad.buttonB), (.x, pad.buttonX), (.y, pad.buttonY),
        (.menu, pad.buttonMenu), (.view, pad.buttonOptions), (.nexus, pad.buttonHome),
        (.leftShoulder, pad.leftShoulder), (.rightShoulder, pad.rightShoulder),
        (.leftThumb, pad.leftThumbstickButton), (.rightThumb, pad.rightThumbstickButton)
    ]
    for (expected, button) in buttons {
        guard let button else { continue } // Optional controls depend on the framework's synthetic profile.
        button.setValue(1)
        #expect(NativeGamepad.snapshot(pad).buttons == [expected])
        button.setValue(0)
    }
    for (x, y, expected) in [(Float(0), Float(1), GamepadButton.up),
                             (0, -1, .down), (-1, 0, .left), (1, 0, .right)] {
        pad.dpad.setValueForXAxis(x, yAxis: y)
        #expect(NativeGamepad.snapshot(pad).buttons == [expected])
    }
    pad.dpad.setValueForXAxis(0, yAxis: 0)
    pad.leftThumbstick.setValueForXAxis(0.5, yAxis: 1)
    pad.rightThumbstick.setValueForXAxis(-1, yAxis: -1)
    pad.leftTrigger.setValue(0.5)
    pad.rightTrigger.setValue(1)
    let state = NativeGamepad.snapshot(pad)
    #expect(state.leftY == -1 && state.rightY == 1)
    #expect(state.leftX == 0.5 && state.rightX == -1)
    #expect(state.leftTrigger == 0.5 && state.rightTrigger == 1)
    let packet = try GamepadPacketEncoder.encode(state, sequence: 1, timestampMS: 0)
    #expect(Array(packet[20..<22]) == [0xff, 0x7f]) // Apple up is positive on the wire.
    #expect(Array(packet[24..<26]) == [0x01, 0x80])
}

@Test func gamepadFastAnalogMotionCoalescesWithoutLosingTriggerEdges() {
    var input = GamepadInput()
    input.update(GamepadSnapshot(), ownsInput: true)
    for index in 1...200 {
        input.update(GamepadSnapshot(leftX: Double(index) / 200), ownsInput: true)
    }
    #expect(input.queue.count == 1 && input.queue.first?.leftX == 1 && input.armed)
    input.update(GamepadSnapshot(leftTrigger: 0.5), ownsInput: true)
    input.update(GamepadSnapshot(leftTrigger: 1), ownsInput: true)
    input.update(GamepadSnapshot(), ownsInput: true)
    #expect(input.queue.count == 3)
    #expect(input.queue.map(\.leftTrigger) == [0, 1, 0])
}
