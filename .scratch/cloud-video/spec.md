# First Cloud Video Slice

## Goal

Extend the verified cloud session lifecycle into a continuously updating native video preview. Start with Fortnite on the existing Microsoft account. Audio playback, microphone/camera capture, controller input, MetalFX, HDR, and reconnect are out of scope.

## Implementation Boundaries

- Pin the community-distributed native WebRTC XCFramework to 153.0.0; commit SwiftPM's resolved revision and verify its artifact checksum. Bundle and sign its macOS framework with the app.
- Use the reference xCloud SDP/ICE endpoints and control/message handshake. Exchange only with the authenticated Xbox service. Use Microsoft's STUN endpoint; no third-party TURN credentials, relay subscription, or region spoofing.
- Negotiate H.264 only. Inject a VideoToolbox decoder requiring hardware acceleration and check the session's hardware property. Reject initialization when that check fails.
- WebRTC supplies compressed Annex B access units. Build VideoToolbox samples from compressed data; never copy decoded pixel planes to the CPU. Preserve RTP timestamps in decoded WebRTC frames.
- Feed native video-range NV12/IOSurface buffers into the existing Metal texture-cache renderer. Preserve Aspect Fit and drawable-backed geometry.
- Keep one latest decoded frame for display, skipping superseded frames. The existing local-file bounded read-ahead remains separate.
- Keep audio receive-only for service negotiation and disable its track; create no local media capture tracks. The input channel sends client capability metadata only, not controller reports. Advertise no custom system UI support.
- Distinguish connection progress from actually decoded and presented frames. Show resolution, verified hardware decoding, average decode/presentation FPS, and skipped-frame counts.
- Require a first frame within 45 seconds after ICE exchange; fail on a 15-second frame stall or failed ICE transport. Bound SDP/ICE response polling and ICE gathering. Honor the service keepalive interval.
- End Session/Command-0/closing the render window stops video and releases WebRTC before deleting the cloud session. Known deletion failures retain ownership and retry, as in the previous slice. Normal app termination still requires confirmed cloud cleanup.
- Do not print tokens, SDP, candidate addresses, or raw service responses. Native WebRTC debug logging is disabled.

## Stable Development Signing

With explicit user approval, create `XFrame Local Development`, a local self-signed code-signing identity in the user's login Keychain. No private key goes in the repo or app bundle, and no system trust setting changes. Limit imported private-key application access to `/usr/bin/codesign`.

Builds prefer this identity, with an explicit `XFRAME_SIGNING_IDENTITY` override and an announced ad-hoc fallback when it is absent. Certificate-backed designated requirements must remain identical across changed app binaries. Migration from older ad-hoc builds may require one new Keychain approval. This is not a notarized distribution identity.

## Verification

- Hardware integration fixture: decode all 720 Annex B H.264 frames; verify hardware, video-range NV12, IOSurface, latest-frame bounds, and stop behavior.
- Unit/contract coverage: Annex B framing, ICE index variants, SDP/ICE envelope exchange, keepalive, and existing account/session cleanup and local-video tests.
- Real acceptance: launch a cloud game, visibly render continuously changing frames, verify counters and geometry, stop, and confirm server cleanup.
- Rebuild with changed binary and prove the signing designated requirement is stable. A working one-off signature alone does not prove the repeated-prompt issue is solved.

## References

- XStreaming commit `383e19d324f2d3029d1c304752f4d38a9360bb95`: `src/xCloud/index.ts`, `src/webrtc/index.ts`, `src/webrtc/Channel/{Control,Message,Input}.ts`, and `src/webrtc/Packet/index.ts`.
- [WebRTC distribution](https://github.com/stasel/WebRTC/tree/153.0.0); artifact license is copied into the application bundle.
- [Apple code-signing requirements](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements).

Force-quit recovery, creation requests with ambiguous server outcomes, automatic account-token renewal during long streams, broader network traversal, and seamless reconnect remain deferred.
