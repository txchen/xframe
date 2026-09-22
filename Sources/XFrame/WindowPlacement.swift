import AppKit

enum WindowPlacement {
    /// Keep the complete frame reachable, including the title bar, on one screen.
    static func constrained(_ frame: CGRect, to screens: [CGRect]) -> CGRect {
        guard let fallback = screens.first else { return frame }
        let screen = screens.max { lhs, rhs in
            area(frame.intersection(lhs)) < area(frame.intersection(rhs))
        }.flatMap { area(frame.intersection($0)) > 0 ? $0 : nil } ?? fallback
        let width = min(frame.width, screen.width)
        let height = min(frame.height, screen.height)
        return CGRect(x: min(max(frame.minX, screen.minX), screen.maxX - width),
                      y: min(max(frame.minY, screen.minY), screen.maxY - height),
                      width: width, height: height)
    }

    private static func area(_ rect: CGRect) -> CGFloat {
        rect.isNull || rect.isEmpty ? 0 : rect.width * rect.height
    }

    @MainActor static func restore(_ window: NSWindow, name: String, preferredContentSize: NSSize) {
        if !window.setFrameUsingName(name) {
            window.setContentSize(preferredContentSize)
            window.center()
        }
        keepVisible(window)
        window.setFrameAutosaveName(name)
    }

    @MainActor static func keepVisible(_ window: NSWindow) {
        guard !window.styleMask.contains(.fullScreen) else { return }
        let screens = NSScreen.screens.map(\.visibleFrame)
        let frame = constrained(window.frame, to: screens)
        if frame != window.frame { window.setFrame(frame, display: window.isVisible) }
    }
}
