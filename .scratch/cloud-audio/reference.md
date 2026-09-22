# Cloud audio reference findings

Reviewed on 2026-09-21. Scope: received game audio, local mute/gain, and teardown. This is implementation guidance, not proof of audible output on this Mac.

## Source revisions

- Better xCloud: current remote checkout `f8397043f6d2148d2345d508902a38c69cf1ee20`.
- XStreaming: existing pinned checkout `383e19d324f2d3029d1c304752f4d38a9360bb95`.
- WebRTC upstream source: main resolved to `48de43219ddc3a47188814d512875eaeb0bcf0d0`. Upstream main is explanatory, not a claim that the bundled binary has this exact revision.
- Installed XFrame dependency: stasel/WebRTC `153.0.0`. Its bundled `RTCAudioTrack.h` and `RTCAudioSource.h` expose `source` and remote source `volume` (gain range 0 through 10).

## XStreaming: native remote-track gain

`NativeStream.tsx` keeps the selected gain separately, clamps it to 0 through 10, applies `_setVolume` to existing remote audio tracks, and reapplies the current value whenever a new audio track arrives. This is the useful lifecycle pattern: settings must work before and after track arrival. [NativeStream source](https://github.com/Geocld/XStreaming/blob/383e19d324f2d3029d1c304752f4d38a9360bb95/src/pages/NativeStream.tsx#L591-L611)

Its peer connection requests video `recvonly` but audio `sendrecv`. Do not copy that audio direction for XFrame's receive-only milestone: the reference also implements microphone capture, sender replacement, and chat. Keep XFrame audio `recvonly`, with no local audio source or track. [Peer setup](https://github.com/Geocld/XStreaming/blob/383e19d324f2d3029d1c304752f4d38a9360bb95/src/webrtc/index.ts#L200-L206), [chat capture](https://github.com/Geocld/XStreaming/blob/383e19d324f2d3029d1c304752f4d38a9360bb95/src/webrtc/Channel/Chat.ts)

An optional stereo setting adds `stereo=1`, `minptime=10`, and `useinbandfec=1` to the negotiated Opus fmtp entry. This is separate from enabling playback and need not be bundled into the first audio change. Its close path closes the peer, resets audio-level tracking, destroys channel processors, and stops input. [Stereo and audio-level logic](https://github.com/Geocld/XStreaming/blob/383e19d324f2d3029d1c304752f4d38a9360bb95/src/webrtc/index.ts#L790-L819), [close](https://github.com/Geocld/XStreaming/blob/383e19d324f2d3029d1c304752f4d38a9360bb95/src/webrtc/index.ts#L309-L325)

## Better xCloud: separate mute from remembered volume

The browser implementation routes the received stream through a gain node to the audio context destination and mutes the original media element to avoid duplicate output. Gain is initialized from the saved volume percentage. Mute sets effective gain to zero while retaining the chosen volume for unmute. When gain control is unavailable, it toggles the media element's mute property. [Audio routing](https://github.com/redphx/better-xcloud/blob/f8397043f6d2148d2345d508902a38c69cf1ee20/src/utils/bx-exposed.ts#L179-L203), [gain initialization](https://github.com/redphx/better-xcloud/blob/f8397043f6d2148d2345d508902a38c69cf1ee20/src/utils/monkey-patches.ts#L130-L154), [mute and volume](https://github.com/redphx/better-xcloud/blob/f8397043f6d2148d2345d508902a38c69cf1ee20/src/modules/shortcuts/sound-shortcut.ts)

Transfer the mute/remembered-volume semantics, not browser `AudioContext`, DOM monkey patches, or media-element workarounds. The inspected gain helpers do not establish a standalone native teardown design; XFrame must explicitly stop its own remote track and peer lifecycle.

## Native WebRTC playback path

The Objective-C factory supplies built-in audio encoders and decoders even when callers customize only video factories. With no custom audio device supplied, the voice engine can create the platform-default device; the macOS implementation selects `AudioDeviceMac`. Therefore the first implementation should use WebRTC's native playback path rather than add a second PCM pipeline. This remains an inference to verify against the shipped framework at runtime. [Objective-C factory](https://webrtc.googlesource.com/src/+/48de43219ddc3a47188814d512875eaeb0bcf0d0/sdk/objc/api/peerconnection/RTCPeerConnectionFactory.mm), [default device creation](https://webrtc.googlesource.com/src/+/48de43219ddc3a47188814d512875eaeb0bcf0d0/media/engine/webrtc_voice_engine.cc), [macOS device selection](https://webrtc.googlesource.com/src/+/48de43219ddc3a47188814d512875eaeb0bcf0d0/modules/audio_device/audio_device_impl.cc)

The native receiver observes track enabled state and source gain. A disabled track has zero effective output, while requested gain remains cached for later re-enabling. Source gain is constrained to 0 through 10. [Audio receiver implementation](https://webrtc.googlesource.com/src/+/48de43219ddc3a47188814d512875eaeb0bcf0d0/pc/audio_rtp_receiver.cc)

## Suggested XFrame boundary and acceptance

1. Keep the audio transceiver receive-only. Enable the received `RTCAudioTrack`; retain it for local controls and teardown.
2. Store mute and volume independently. Start with an unamplified 0 through 1 gain range, apply settings on attachment, and reject late attachment after shutdown.
3. On cleanup, disable retained audio tracks, clear references, and close the peer. Do not create microphone tracks or request microphone permission.
4. Surface received audio packets/bytes, decoded samples, and energy separately from output state. Incoming statistics alone do not prove physical speaker output or correct mute behavior.
5. Verify audible playback, mute/unmute, volume changes, video continuing while muted, and no continuing audio after End Session. Treat lack of human or captured-output evidence as an explicit audible-playback validation gap.
