import Testing
@testable import XFrame

@Test func inputOwnershipSwitchesOnlyOnFreshActivity() {
    var owner = InputOwnership()
    let changed1 = owner.observeController(GamepadSnapshot(buttons: [.a]), enabled: true)
    #expect(changed1)
    #expect(owner.active == .controller)
    let changed2 = owner.claimKeyboard()
    #expect(changed2)
    let changed3 = !owner.observeController(GamepadSnapshot(buttons: [.a]), enabled: true)
    #expect(changed3)
    let changed4 = !owner.observeController(GamepadSnapshot(), enabled: true)
    #expect(changed4)
    #expect(owner.active == .keyboard)
    let changed5 = owner.observeController(GamepadSnapshot(buttons: [.b]), enabled: true)
    #expect(changed5)
    #expect(owner.active == .controller)
}

@Test func inactiveControllerDriftAndHeldAxesDoNotStealKeyboard() {
    var owner = InputOwnership()
    _ = owner.claimKeyboard()
    for x in [0.02, -0.1, 0.24, 0] {
        let changed6 = !owner.observeController(GamepadSnapshot(leftX: x), enabled: true)
        #expect(changed6)
    }
    let changed7 = owner.observeController(GamepadSnapshot(leftX: 0.8), enabled: true)
    #expect(changed7)
    _ = owner.claimKeyboard()
    let changed8 = !owner.observeController(GamepadSnapshot(leftX: 0.75), enabled: true)
    #expect(changed8)
    let changed9 = !owner.observeController(GamepadSnapshot(), enabled: true)
    #expect(changed9)
    let changed10 = owner.observeController(GamepadSnapshot(rightTrigger: 0.6), enabled: true)
    #expect(changed10)
}

@Test func disabledControllerAndBoundaryHeldButtonsCannotClaim() {
    var owner = InputOwnership()
    owner.reset(controller: GamepadSnapshot(buttons: [.a]))
    let changed11 = !owner.observeController(GamepadSnapshot(buttons: [.a]), enabled: true)
    #expect(changed11)
    _ = owner.claimKeyboard()
    let changed12 = !owner.observeController(GamepadSnapshot(buttons: [.b]), enabled: false)
    #expect(changed12)
    #expect(owner.active == .keyboard)
}

@Test func handoffSendsNeutralBeforeNewDeviceAndDropsOldQueuedKeys() {
    var input = GamepadInput()
    input.update(GamepadSnapshot(), ownsInput: true)
    input.send(timestampMS: 0) { _ in true }
    input.update(GamepadSnapshot(buttons: [.a]), ownsInput: true)
    input.send(timestampMS: 16, minimumButtonHoldMS: 50) { _ in true }
    input.update(GamepadSnapshot(buttons: [.b]), ownsInput: true)
    input.release()
    input.update(GamepadSnapshot(), ownsInput: true)
    input.update(GamepadSnapshot(buttons: [.x]), ownsInput: true)
    var packets: [UInt8] = []
    for t in [17.0, 33.0] {
        input.send(timestampMS: t, minimumButtonHoldMS: 50) { packets.append($0[16]); return true }
    }
    #expect(packets == [0, UInt8(GamepadButton.x.rawValue)])
}
