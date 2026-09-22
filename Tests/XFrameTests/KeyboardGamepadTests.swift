import Foundation
import Testing
@testable import XFrame

@Test func keyboardAxesOppositesAndDiagonals() {
    var keyboard = KeyboardGamepad()
    keyboard.handle(code: 13, down: true)
    #expect(keyboard.snapshot.leftY == -1)
    keyboard.handle(code: 2, down: true)
    #expect(abs(hypot(keyboard.snapshot.leftX, keyboard.snapshot.leftY) - 1) < 0.00001)
    keyboard.handle(code: 0, down: true)
    #expect(keyboard.snapshot.leftX == 0 && keyboard.snapshot.leftY == -1)
    keyboard.handle(code: 1, down: true)
    #expect(keyboard.snapshot == GamepadSnapshot())
    keyboard.handle(code: 124, down: true)
    keyboard.handle(code: 126, down: true)
    #expect(keyboard.snapshot.rightX > 0 && keyboard.snapshot.rightY < 0)
    keyboard.handle(code: 6, down: true)
    keyboard.handle(code: 8, down: true)
    #expect(keyboard.snapshot.leftTrigger == 1 && keyboard.snapshot.rightTrigger == 1)
    keyboard.release()
    #expect(keyboard.snapshot == GamepadSnapshot())
}

@Test func keyboardAliasesAndShortEdgesReachGamepadScheduler() {
    var keyboard = KeyboardGamepad()
    var input = GamepadInput()
    input.update(keyboard.snapshot, ownsInput: true)
    keyboard.handle(code: 38, down: true)
    input.update(keyboard.snapshot, ownsInput: true)
    keyboard.handle(code: 49, down: true)
    keyboard.handle(code: 38, down: false)
    #expect(keyboard.snapshot.buttons == [.a])
    keyboard.handle(code: 49, down: false)
    input.update(keyboard.snapshot, ownsInput: true)
    #expect(input.queue.map(\.buttons) == [[.a], []])
    var packets: [Data] = []
    for _ in 0..<3 { input.send(timestampMS: 1) { packets.append($0); return true } }
    #expect(packets.count == 3)
    #expect(packets[1][16] == UInt8(GamepadButton.a.rawValue))
    #expect(packets[2][16] == 0)
}

@Test func keyboardReleaseIgnoresHeldKeyRepeatAndLeavesShortcutsAlone() {
    var keyboard = KeyboardGamepad()
    keyboard.handle(code: 13, down: true)
    keyboard.release()
    keyboard.handle(code: 13, down: true, repeatKey: true)
    #expect(keyboard.snapshot == GamepadSnapshot())
    keyboard.handle(code: 13, down: false)
    keyboard.handle(code: 13, down: true)
    #expect(keyboard.snapshot.leftY == -1)
    let handled = keyboard.handle(code: 0, down: true, shortcut: true)
    #expect(!handled && keyboard.snapshot == GamepadSnapshot())
    let unknown = keyboard.handle(code: 999, down: true)
    #expect(!unknown && keyboard.snapshot == GamepadSnapshot())
}

@Test @MainActor func keyboardAndControllerCanBothBeEnabled() {
    let library = CloudLibrary()
    #expect(!library.keyboardEnabled && !library.controllerEnabled)
    library.controllerEnabled = true
    library.keyboardEnabled = true
    #expect(library.keyboardEnabled && library.controllerEnabled)
    library.controllerEnabled = false
    #expect(library.keyboardEnabled && !library.controllerEnabled)
}

@Test func keyboardMapsEveryGamepadButtonInHelp() {
    let mappings: [UInt16: GamepadButton] = [38:.a,40:.b,32:.x,34:.y,12:.leftShoulder,14:.rightShoulder,
        3:.left,17:.up,4:.right,5:.down,37:.leftThumb,31:.rightThumb,36:.menu,48:.view]
    for (code, button) in mappings {
        var keyboard = KeyboardGamepad()
        keyboard.handle(code: code, down: true)
        #expect(keyboard.snapshot.buttons == [button])
        keyboard.handle(code: code, down: false)
        #expect(keyboard.snapshot == GamepadSnapshot())
    }
}

@Test func keyboardQuickTapSurvivesSlowerGameSamplingAndFocusReleaseIsImmediate() {
    var input = GamepadInput()
    input.update(GamepadSnapshot(), ownsInput: true)
    input.send(timestampMS: 0, minimumButtonHoldMS: 50) { _ in true }
    // Tool-generated keydown/up can land between send ticks. A one-packet press
    // at 16 ms is already released by the game's next 30 Hz poll around 34 ms.
    input.update(GamepadSnapshot(buttons: [.b]), ownsInput: true)
    input.update(GamepadSnapshot(), ownsInput: true)
    var observed: [UInt8] = []
    for time in [16.0, 33.0, 50.0, 67.0] {
        input.send(timestampMS: time, minimumButtonHoldMS: 50) { observed.append($0[16]); return true }
    }
    #expect(observed == [0x20, 0x20, 0x20, 0])
    input.update(GamepadSnapshot(buttons: [.a]), ownsInput: true)
    input.send(timestampMS: 80, minimumButtonHoldMS: 50) { _ in true }
    input.release()
    var released: UInt8 = 255
    input.send(timestampMS: 81, minimumButtonHoldMS: 50) { released = $0[16]; return true }
    #expect(released == 0)
}
