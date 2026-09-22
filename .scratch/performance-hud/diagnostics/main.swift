// Read-only physical button capture, replayed through the shipping shortcut recognizer.
import Foundation
import GameController
import QuartzCore
let started = CACurrentMediaTime()
func report(_ s: String) { print(String(format: "%.3f %@", CACurrentMediaTime()-started, s)); fflush(stdout) }
GCController.shouldMonitorBackgroundEvents = true
var device: GCController?
var previous = Set<GamepadButton>()
var shortcut = GamepadHUDShortcut()
let timer = Timer.scheduledTimer(withTimeInterval: 0.008, repeats: true) { _ in
    let current = GCController.controllers().first { !$0.isSnapshot && $0.extendedGamepad != nil }
    if current !== device {
        device = current
        shortcut.reset()
        report("DEVICE \(current?.vendorName ?? "none") optionsPresent=\(current?.extendedGamepad?.buttonOptions != nil)")
    }
    guard let pad = device?.extendedGamepad else { return }
    var buttons = Set<GamepadButton>()
    if pad.buttonMenu.isPressed { buttons.insert(.menu) }
    if pad.buttonOptions?.isPressed == true { buttons.insert(.view) }
    if buttons != previous { report("BUTTONS view=\(buttons.contains(.view)) menu=\(buttons.contains(.menu))"); previous = buttons }
    let result = shortcut.process(GamepadSnapshot(buttons: buttons), now: CACurrentMediaTime())
    if result.cycle { report("SHORTCUT_CYCLE") }
}
report("READY")
RunLoop.main.run(until: Date().addingTimeInterval(600))
timer.invalidate()
report("DONE")
