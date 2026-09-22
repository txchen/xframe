import AppKit

@MainActor
protocol PlaybackWindowSurface: AnyObject {
    var isFullScreen: Bool { get }
    func showPlayback()
    func hidePlayback()
    func exitFullScreen()
}

extension NSWindow: PlaybackWindowSurface {
    var isFullScreen: Bool { styleMask.contains(.fullScreen) }
    func showPlayback() {
        isExcludedFromWindowsMenu = false
        if isMiniaturized { deminiaturize(nil) }
        WindowPlacement.keepVisible(self)
        makeKeyAndOrderFront(nil)
    }
    func hidePlayback() {
        isExcludedFromWindowsMenu = true
        orderOut(nil)
    }
    func exitFullScreen() { toggleFullScreen(nil) }
}

// Owns playback visibility across asynchronous native full-screen transitions.
@MainActor
final class PlaybackWindowPresentation {
    private let surface: any PlaybackWindowSurface
    init(surface: any PlaybackWindowSurface) { self.surface = surface }

    private var transitioning = false
    private var pendingVisibility: Bool?

    func showWindowed() {
        pendingVisibility = true
        reconcile()
    }
    func hide() {
        pendingVisibility = false
        reconcile()
    }
    func willTransitionFullScreen() { transitioning = true }
    func didTransitionFullScreen() {
        transitioning = false
        reconcile()
    }
    func failedTransitionFullScreen() {
        transitioning = false
        // A failed entry can still fulfill a windowed request. A failed exit
        // retains the request for an explicit retry, without an animation loop.
        if !surface.isFullScreen { reconcile() }
    }

    private func reconcile() {
        guard !transitioning, let visible = pendingVisibility else { return }
        if surface.isFullScreen {
            transitioning = true
            surface.exitFullScreen()
            return
        }
        pendingVisibility = nil
        if visible { surface.showPlayback() }
        else { surface.hidePlayback() }
    }
}
