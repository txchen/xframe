import Testing
@testable import XFrame

@MainActor
private final class PlaybackSurface: PlaybackWindowSurface {
    var isFullScreen = true
    var operations: [String] = []
    func showPlayback() { operations.append("show") }
    func hidePlayback() { operations.append("hide") }
    func exitFullScreen() { operations.append("exit") }
}

@Test @MainActor func endingFullscreenPlaybackExitsBeforeHiding() {
    let surface = PlaybackSurface()
    let presentation = PlaybackWindowPresentation(surface: surface)
    presentation.hide()
    #expect(surface.operations == ["exit"])
    surface.isFullScreen = false
    presentation.didTransitionFullScreen()
    #expect(surface.operations == ["exit", "hide"])
}

@Test @MainActor func newPlaybackDoesNotRevealRetainedFullscreenWindow() {
    let surface = PlaybackSurface()
    let presentation = PlaybackWindowPresentation(surface: surface)
    presentation.hide()
    presentation.showWindowed()
    #expect(!surface.operations.contains("show"))
    #expect(surface.operations.filter { $0 == "exit" }.count == 1)
    surface.isFullScreen = false
    presentation.didTransitionFullScreen()
    #expect(surface.operations == ["exit", "show"])
}

@Test @MainActor func endingDuringFullscreenEntryWaitsThenExitsAndHides() {
    let surface = PlaybackSurface()
    surface.isFullScreen = false
    let presentation = PlaybackWindowPresentation(surface: surface)
    presentation.showWindowed()
    presentation.willTransitionFullScreen()
    presentation.hide()
    #expect(surface.operations == ["show"])
    surface.isFullScreen = true
    presentation.didTransitionFullScreen()
    #expect(surface.operations == ["show", "exit"])
    surface.isFullScreen = false
    presentation.didTransitionFullScreen()
    #expect(surface.operations == ["show", "exit", "hide"])
}

@Test @MainActor func normalFullscreenEntryStaysFullscreenAndLatestRequestWins() {
    let surface = PlaybackSurface()
    surface.isFullScreen = false
    let presentation = PlaybackWindowPresentation(surface: surface)
    presentation.showWindowed()
    presentation.willTransitionFullScreen()
    surface.isFullScreen = true
    presentation.didTransitionFullScreen()
    #expect(surface.operations == ["show"])
    presentation.hide()
    presentation.showWindowed()
    presentation.hide()
    surface.isFullScreen = false
    presentation.didTransitionFullScreen()
    #expect(surface.operations == ["show", "exit", "hide"])
}

@Test @MainActor func failedFullscreenExitDoesNotHideOrLoopAndCanRetry() {
    let surface = PlaybackSurface()
    let presentation = PlaybackWindowPresentation(surface: surface)
    presentation.hide()
    presentation.failedTransitionFullScreen()
    #expect(surface.operations == ["exit"])
    presentation.showWindowed()
    #expect(surface.operations == ["exit", "exit"])
    surface.isFullScreen = false
    presentation.didTransitionFullScreen()
    #expect(surface.operations == ["exit", "exit", "show"])
}
