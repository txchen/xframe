import AppKit
import Foundation
import IOKit.pwr_mgt

/// Holds a macOS display sleep assertion while video playback or streaming is active.
@MainActor
final class PlaybackDisplayAssertion {
    private var assertionID: IOPMAssertionID = 0
    private var active = false

    func acquire(reason: String = "XFrame active video playback") {
        guard !active else { return }
        var id: IOPMAssertionID = 0
        let status = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &id
        )
        if status == kIOReturnSuccess {
            assertionID = id
            active = true
        }
    }

    func release() {
        guard active else { return }
        IOPMAssertionRelease(assertionID)
        assertionID = 0
        active = false
    }

    deinit {
        if active { IOPMAssertionRelease(assertionID) }
    }
}

/// Hides the mouse cursor after brief inactivity during focused fullscreen playback.
/// Strictly balances NSCursor.hide() / NSCursor.unhide() calls.
@MainActor
final class FullscreenCursorHider {
    private var timer: Timer?
    private(set) var isHidden = false
    private var enabled = false
    private let delay: TimeInterval

    init(delay: TimeInterval = 2.5) {
        self.delay = delay
    }

    func update(eligible: Bool) {
        enabled = eligible
        if eligible {
            scheduleHide()
        } else {
            reveal()
        }
    }

    func mouseMoved() {
        reveal()
        if enabled { scheduleHide() }
    }

    func reveal() {
        timer?.invalidate()
        timer = nil
        guard isHidden else { return }
        NSCursor.unhide()
        isHidden = false
    }

    private func scheduleHide() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.enabled, !self.isHidden else { return }
                NSCursor.hide()
                self.isHidden = true
            }
        }
    }

    isolated deinit {
        timer?.invalidate()
        if isHidden { NSCursor.unhide() }
    }
}
