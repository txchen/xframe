import Foundation
import Testing
@testable import XFrame

@MainActor private final class TestAudioOutput: CloudAudioOutput {
    var enabled = true
    var gain = 1.0
    var updates = 0
    func apply(enabled: Bool, gain: Double) {
        self.enabled = enabled; self.gain = gain; updates += 1
    }
}

@Test @MainActor func gameAudioAppliesPreferencesBeforeAndAfterTrackArrival() {
    let audio = CloudAudioPlayback()
    audio.configure(muted: true, volume: 0.4)
    let track = TestAudioOutput()
    audio.attach(track)
    #expect(!track.enabled)
    #expect(track.gain == 0)
    audio.configure(muted: false, volume: audio.volume)
    #expect(track.enabled)
    #expect(track.gain == 0.4)
    audio.configure(muted: false, volume: 0)
    #expect(!track.enabled)
    audio.configure(muted: false, volume: 5)
    #expect(track.gain == 1)
    audio.configure(muted: false, volume: .nan)
    #expect(!track.enabled)
    #expect(track.gain == 0)
}

@Test @MainActor func gameAudioDisablesReplacedStoppedAndLateTracks() {
    let audio = CloudAudioPlayback()
    let first = TestAudioOutput(), second = TestAudioOutput(), late = TestAudioOutput()
    audio.attach(first)
    #expect(first.enabled)
    audio.attach(second)
    #expect(!first.enabled && first.gain == 0)
    #expect(second.enabled)
    audio.stop()
    #expect(!second.enabled && second.gain == 0)
    #expect(!audio.hasTrack)
    audio.configure(muted: false, volume: 1)
    audio.attach(late)
    #expect(!late.enabled && late.gain == 0)
    #expect(!audio.hasTrack)
}

@Test func audioDiagnosticsDoNotClaimAudibilityOrAcceptLateUpdates() {
    let video = LiveVideo()
    #expect(!video.snapshot().audioAttached)
    #expect(video.snapshot().audioPacketsReceived == nil)
    video.audioPlayback(attached: true, muted: false, volume: 0.5)
    video.audioNetworkSample(received: 10, energy: 0.1)
    #expect(video.snapshot().audioPacketsReceived == 10)
    #expect(video.snapshot().audioEnergy == 0.1)
    video.audioNetworkSample(received: 20, energy: .infinity)
    #expect(video.snapshot().audioEnergy == nil)
    video.stop()
    video.audioPlayback(attached: false, muted: true, volume: 0)
    video.audioNetworkSample(received: 30, energy: 1)
    #expect(video.snapshot().audioPacketsReceived == 20)
}
