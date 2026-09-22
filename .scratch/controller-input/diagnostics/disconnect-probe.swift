// Read-only physical-controller probe. No network, game input or system settings.
import Foundation
import GameController
import QuartzCore

let started = CACurrentMediaTime()
func report(_ message: String) {
    print(String(format: "%.3f %@", CACurrentMediaTime() - started, message))
    fflush(stdout)
}
GCController.shouldMonitorBackgroundEvents = true
var previousIDs: Set<ObjectIdentifier> = []
var controller: GCController?
let observer = NotificationCenter.default.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { _ in
    report("OS_DISCONNECT_NOTIFICATION")
}
let timer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { _ in
    let devices = GCController.controllers().filter { !$0.isSnapshot && $0.extendedGamepad != nil }
    let ids = Set(devices.map(ObjectIdentifier.init))
    guard ids != previousIDs else { return }
    previousIDs = ids
    report("ENUMERATED_CONTROLLERS count=\(devices.count)")
    controller?.extendedGamepad?.valueChangedHandler = nil
    controller = devices.first
    controller?.handlerQueue = .main
    controller?.extendedGamepad?.valueChangedHandler = { pad, _ in
        report(String(format: "INPUT leftX=%.2f leftY=%.2f", pad.leftThumbstick.xAxis.value, pad.leftThumbstick.yAxis.value))
    }
}
report("READY: move the left stick, immediately remove the batteries, then reconnect")
RunLoop.main.run(until: Date().addingTimeInterval(120))
timer.invalidate()
controller?.extendedGamepad?.valueChangedHandler = nil
NotificationCenter.default.removeObserver(observer)
report("DONE")
