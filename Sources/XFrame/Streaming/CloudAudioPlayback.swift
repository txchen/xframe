import Foundation
@preconcurrency import WebRTC

@MainActor
protocol CloudAudioOutput: AnyObject {
    func apply(enabled: Bool, gain: Double)
}

@MainActor
final class WebRTCAudioOutput: CloudAudioOutput {
    private let track: RTCAudioTrack
    init(track: RTCAudioTrack) { self.track = track }
    func apply(enabled: Bool, gain: Double) {
        track.source.volume = gain
        track.isEnabled = enabled
    }
}

// Remote game audio only. WebRTC owns decoding, jitter buffering and native
// output. This module never creates a capture source or local sender track.
@MainActor
final class CloudAudioPlayback {
    private var output: (any CloudAudioOutput)?
    private var stopped = false
    private(set) var muted = false
    private(set) var volume = 1.0
    var hasTrack: Bool { output != nil }

    func configure(muted: Bool, volume: Double) {
        self.muted = muted
        self.volume = volume.isFinite ? min(1, max(0, volume)) : 0
        apply()
    }
    func attach(_ output: any CloudAudioOutput) {
        guard !stopped else { output.apply(enabled: false, gain: 0); return }
        self.output?.apply(enabled: false, gain: 0)
        self.output = output
        apply()
    }
    func stop() {
        stopped = true
        output?.apply(enabled: false, gain: 0)
        output = nil
    }
    private func apply() {
        guard !stopped else { return }
        output?.apply(enabled: !muted && volume > 0, gain: muted ? 0 : volume)
    }
}
