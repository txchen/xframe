import Foundation
import Testing
@testable import XFrame

@Test func windowPlacementPreservesVisibleFramesAndRecoversDisconnectedScreens() {
    let main = CGRect(x: 0, y: 30, width: 1440, height: 850)
    let second = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
    let saved = CGRect(x: 100, y: 80, width: 1240, height: 800)
    #expect(WindowPlacement.constrained(saved, to: [main]) == saved)
    let external = CGRect(x: -1800, y: 100, width: 1000, height: 720)
    #expect(WindowPlacement.constrained(external, to: [main, second]) == external)
    #expect(WindowPlacement.constrained(external, to: [main]) == CGRect(x: 0, y: 100, width: 1000, height: 720))
    let oversized = CGRect(x: -100, y: -100, width: 3000, height: 2000)
    #expect(WindowPlacement.constrained(oversized, to: [main]) == main)
    let belowDock = CGRect(x: 1000, y: -50, width: 800, height: 600)
    #expect(WindowPlacement.constrained(belowDock, to: [main]) == CGRect(x: 640, y: 30, width: 800, height: 600))
    #expect(WindowPlacement.constrained(saved, to: []) == saved)
}
