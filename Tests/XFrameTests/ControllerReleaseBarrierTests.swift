import Testing
@testable import XFrame

@Test func controllerResumeDoesNotReplayAButtonWhenKeyboardAlreadyArmedTheWire() {
    let held = GamepadSnapshot(buttons: [.a])
    let fresh = GamepadSnapshot(buttons: [.a, .b])
    var input = GamepadInput()
    var ownership = InputOwnership()
    ownership.reset(controller: held)
    // Existing behavior: a keyboard-neutral poll re-arms the shared scheduler.
    input.update(GamepadSnapshot(), ownsInput: true)
    let claimedBefore = ownership.observeController(fresh, enabled: true)
    #expect(claimedBefore)
    input.update(fresh, ownsInput: true)
    #expect(input.queue.last?.buttons == [.a, .b])

    // The physical-device barrier survives virtual keyboard ownership and only
    // removes the old A. A fresh B can still take ownership and reach the wire.
    var barrier = ControllerReleaseBarrier()
    barrier.pause(held)
    input.release()
    input.update(GamepadSnapshot(), ownsInput: true)
    ownership.reset()
    let filtered = barrier.filter(fresh, accepting: true)
    let claimedAfter = ownership.observeController(filtered, enabled: true)
    #expect(claimedAfter)
    input.update(filtered, ownsInput: true)
    #expect(input.queue.last?.buttons == [.b])
    #expect(barrier.filter(GamepadSnapshot(buttons: [.b]), accepting: true).buttons == [.b])
    #expect(barrier.filter(fresh, accepting: true).buttons == [.a, .b])
}

@Test func controllerPauseTracksMenuChangesAndRequiresIndependentAnalogRelease() {
    var barrier = ControllerReleaseBarrier()
    barrier.pause(GamepadSnapshot(buttons: [.a]))
    let menu = GamepadSnapshot(buttons: [.b], leftX: 0.8, rightY: -0.7, leftTrigger: 1, rightTrigger: 0.5)
    #expect(barrier.filter(menu, accepting: false) == GamepadSnapshot())
    #expect(barrier.filter(menu, accepting: true) == GamepadSnapshot())
    // Reversing a held stick or releasing only one of its axes is not a release.
    let reversed = GamepadSnapshot(buttons: [.b, .x], leftY: -1, rightX: 0.5, leftTrigger: 0.4)
    let filtered = barrier.filter(reversed, accepting: true)
    #expect(filtered == GamepadSnapshot(buttons: [.x]))
    // Each control becomes available when it visits its own release region.
    _ = barrier.filter(GamepadSnapshot(leftX: 0.05, leftY: 0.05, leftTrigger: 0.1), accepting: true)
    #expect(barrier.filter(menu, accepting: true) == menu)
}

@Test func controllerReplacementWhileKeyboardOwnsInputCannotClaimWithHeldControls() {
    var ownership = InputOwnership()
    _ = ownership.claimKeyboard()
    var barrier = ControllerReleaseBarrier()
    let replacement = GamepadSnapshot(buttons: [.a], leftTrigger: 1)
    barrier.pause(replacement)
    ownership.reset()
    _ = ownership.claimKeyboard()
    let heldClaim = ownership.observeController(barrier.filter(replacement, accepting: true), enabled: true)
    #expect(!heldClaim)
    #expect(ownership.active == .keyboard)
    _ = barrier.filter(GamepadSnapshot(), accepting: true)
    let freshClaim = ownership.observeController(barrier.filter(replacement, accepting: true), enabled: true)
    #expect(freshClaim)
    #expect(ownership.active == .controller)
}

@Test func controllerReleaseRegionArmsInputWithoutRequiringPerfectAnalogZero() {
    var barrier = ControllerReleaseBarrier()
    barrier.pause(GamepadSnapshot(leftX: 0.9, leftTrigger: 1))
    var input = GamepadInput()
    let resting = GamepadSnapshot(leftX: 0.05, leftY: 0.05, rightTrigger: 0.05)
    input.update(barrier.filter(resting, accepting: true), ownsInput: true)
    #expect(input.armed && input.queue.isEmpty)
    input.update(barrier.filter(GamepadSnapshot(buttons: [.a], leftX: 0.9), accepting: true), ownsInput: true)
    #expect(input.queue.last?.buttons == [.a] && input.queue.last?.leftX == 0.9)
}
