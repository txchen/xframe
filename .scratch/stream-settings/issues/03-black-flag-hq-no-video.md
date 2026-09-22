# Black Flag receives audio but no decoded video with HQ

Status: needs-triage
Type: bug
Workaround: Standard profile restores video in the observed comparison
Root cause: not established

## Reproduction and evidence — 2026-09-22

The user reported audio without any picture, followed by return to the library, and confirmed Assassin's Creed IV Black Flag was the affected title.

Two HQ / Simplified Chinese / Balanced starts, requested region Automatic (WESTUS2), ended with `firstFrameTimeout`. The second was an agent-driven retry of the same title and settings. Native UI inspection confirmed zero input/output frames throughout the wait and the exact 45-second timeout message afterward. The real-service loop takes startup time plus the 45-second watchdog; a fast offline equivalent has not been established.

- Original user report: `.build/fixtures/black-flag-first-frame-timeout.json`, duration 56.273 s; 2,205 audio packets and nonzero energy; 231 video packets; zero decoder configurations, decoded/presented frames, IDR submissions, decode errors, lost packets and NACKs.
- HQ retry: `.build/fixtures/black-flag-hq-retry.json`, duration 56.253 s; 2,206 audio packets and nonzero energy; the same zero-video/configuration result and 231 received video packets.
- Rendering mode was selected Integer Scaling, effectively Original due to windowed output. No decoded frame reached MetalFX; this symptom is separate from the MetalFX motion-quality observation.
- Single setting changed: stream quality HQ → Standard. Same title/language/pacing/region selection and scaling configuration. The third start produced native 1920×1080 H.264 hardware-decoded video. Native screenshot showed the Black Flag title screen and Press A prompt. At the recorded observation: 1,257 decoded / 1,245 presented frames, recent 60.0 / 60.0 fps, 16.8 Mbps, zero decode errors, 3 IDR submissions, 33,784 received packets, lost=0 / NACK=0. Stream frame rate is not internal game FPS.

## Interpretation and disposition

The application did not crash: the first-frame watchdog ended the two failed sessions. The comparison strongly implicates title/profile compatibility, but a single successful Standard start does not prove the precise backend or negotiation cause, nor exclude server-instance variability. No speculative decoder or rendering change was applied. Preserve HQ's experimental label; Standard is a verified workaround for this observation. Current preference and live session were left on Standard so the user can play.

Further investigation, if pursued, should collect sanitized negotiated codec and receive/depacketization counters, and use repeated matched HQ/Standard starts before changing the device profile or keyframe policy. Do not capture credentials, raw SDP, or game media by default.
