# Series X LAN validation, 2026-10-16

Status: video and keyboard verified by agent; audio and physical controller operation confirmed by user. Presentation lifetime repair passed regression and actual transient LAN verification recovery; longer-run acceptance remains limited to the recorded observation.

## Environment and baseline

The user confirmed a Series X on the Mac's LAN with remote features enabled. The existing app restored the Xbox account and listed one associated XboxSeriesX as ConnectedStandby. No credential values were printed or copied.

The agent clicked Wake Console. The user confirmed that the console stayed asleep, then manually turned it on. The app eventually reported that wake was sent but the console was not visible on the LAN. This does not establish a network timeout root cause or successful wake.

With the console awake, an independent UDP 5050 discovery probe received ten 652-byte `dd01` replies over three seconds. The name length was 4 at byte 12 and 22594 at byte 14. The original `ConsoleDiscovery.discover()` implementation, compiled into a small local probe, returned zero consoles. This reproduces the parser defect on the actual Series X. Raw console IDs, certificates, and network addresses were not retained.

Baseline `bash scripts/test.sh` passed all 167 tests. Baseline tests included a discovery fixture with the same incorrect offset as the parser; they did not detect the real-console incompatibility.

## Corrected discovery

After integrating discovery commit `d3109e3`, the same compiled probe returned **1 parsed LAN console**. This is real-console discovery evidence, not yet streaming evidence. The isolated discovery/wake suite passed all 168 tests with `--no-parallel`; the initial parallel run encountered existing auth teardown/timing failures under concurrent build load.

## Actual stream

The signed release app `.build/XFrame-LAN-Diagnostic.app` listed **1 associated console and 1 on the LAN**, with `On`, `Found on this LAN`, and a separate Connect button. Connect created the home session and displayed the actual Series X dashboard. The view reported H.264 at **1920 × 1080**. Several short HUD observations showed received stream cadence around 60 fps. This is a single dashboard session observation, not a benchmark, game-render FPS, or a long-run stability claim.

Sanitized transport logs accepted two remote UDP host candidates, rejected seven remote unsupported-address candidates, and recorded `home gate waiting -> verified`. The gate checks the selected direct endpoint pair against the current physical IPv4 subnet. No STUN server is configured for this session. These are selected-path and application-policy evidence, not packet-firewall proof.

The agent enabled keyboard input and sent the D-pad-right mapping (`H`). The dashboard selection visibly moved from The Crew Motorfest to Forza Horizon 6. No game was launched. Controller input was then enabled for user testing. Audible audio and physical rumble cannot be inferred from the picture or capability checks.

After the final inline-SDP admission correction, `bash scripts/test.sh` passed **174 tests without skips**. The release app built and passed `codesign --verify --deep --strict`. Packaging first exposed an existing macOS Bash empty-array/nounset error; guarded array expansion fixed it in the actual successful build.

## Development app network observation

The `.build/XFrame-LAN.app` variant failed six discovery sends with errno 65 while the system Local Network pane showed its switch enabled. `.build/XFrame-LAN-Diagnostic.app` consistently sent six requests, received six replies, parsed one console, and matched it to the account. Both have the same designated signing requirement. The cause of the variant-specific network failure is unresolved; do not label it an account mismatch or claim a permission fix. The successful app was registered with LaunchServices. Temporary identifier-format logging was removed; retained discovery logging includes counts and errno only.

## Remaining physical verification

- Physical rumble. The user has confirmed audio and controller operation; the app identifies Xbox Wireless Controller.
- Explicit wake from standby with the new payload and response handling.
- Same-session recovery from a brief network interruption.
- Disconnect leaves the console powered on and reconnect succeeds without changing its game.

Candidate admission and sampled selected-pair verification do not constitute a packet firewall. Keep observed route evidence separate from stronger claims about every possible host routing or ICE behavior.

## Follow-up interruption report

The user confirmed visible video, audible audio, and working physical controller input before another interruption. Two sessions ended with `Stream video stopped receiving frames`. The first lost frames around 21:32:39 and closed at 21:32:54; the second lost selected-path evidence around 21:39:09 and ended with the same UI error. The gate revocation follows the loss of media; it is not established as the initiating fault. Sustained streaming acceptance is failed. The subsequent HUD identifies Xbox Wireless Controller; vibration remains unconfirmed.

## Presentation lifetime regression

A diagnostic session recovered LAN verification one second after a transient selected-pair `in-progress` sample, while STUN responses and HTTP heartbeat kept succeeding. It nevertheless hit the fifteen-second frame watchdog. `MetalRenderer.play(nil)` had permanently stopped the session-owned `LiveVideo`. The regression test `liveVideoKeepsReceivingFramesAfterRendererReattachment` reproduced this without networking: decoded count remained 0 and both requested frames were absent (four failures). Removing renderer lifecycle authority restored repeated detach/reattach, while explicit owner shutdown still rejects later frames. All 175 tests passed after the fix. The subsequent ad-hoc build ran about four minutes before a separate actual ICE communication loss; see the next section.

## Signing identity experiment

After the lifetime repair, the ad-hoc build lost inbound consent traffic around 21:52:06. Responses froze at 104 while requests exceeded 343. A successful heartbeat at 21:51:55 precedes this event and does not prove server state after it. ICE became disconnected at 21:52:11 and the media watchdog ended the session at 21:52:20.

At the failure boundary, macOS refreshed its networkprivacy application UUID cache. CoreSpotlight rejected the ad-hoc process because a higher-provenance Developer ID app also claims the bundle identifier. The same workspace contains Developer ID and ad-hoc builds. This correlation motivates an identity experiment; it is not sufficient to prove that the privacy rule blocked media.

The current `.build/XFrame-LAN-Diagnostic.app` was rebuilt using the project's established Developer ID identity, without modifying credentials or OS network settings. Code signing verification passed; notarization was not performed for this diagnostic artifact. The console was discovered and streaming started around 21:54:46. At 21:58:26 the gate revoked verification, then restored it at 21:58:27. Unlike the old app, the same session continued receiving and presenting video beyond the prior fifteen-second failure boundary. The live HUD showed 60 fps receive/output, with decoded frames continuing past 14,344. This verifies the presentation-lifetime repair on the original physical surface. It does not prove that Developer ID signing alone fixes every possible transport interruption.

## Latency measurement explanation

The user asked why a LAN stream displayed roughly 40 ms latency despite 2 ms RTT. A detailed HUD sample showed an estimate of 38.7 ms: RTT 3.0 ms, receiver buffer 1.8 ms, decode mean approximately 2.6 ms, and decoded arrival-to-presentation mean 31.3 ms. The latter included queue 7.4 ms, GPU queue 0.4 ms, GPU execution 0.3 ms, and GPU-end-to-presented-time 23.2 ms. These are one rolling sample, not a benchmark or optimization result. `pipelineLatencyEstimateMS` sums full RTT, buffer, decode mean and presentation mean; it is not input-to-photon latency and excludes host processing.

`FramePresentation` uses timestamps for the same frame, so the display-wait metric is not callback delivery delay. At 60 Hz, waiting for the immediately next eligible refresh is under one refresh interval; compositor deadlines or queued presentations can defer eligibility to a later refresh. The observed 23 ms is therefore possible, but its specific cause has not been profiled. No latency-tuning change was made during the stability comparison.

The signed session remained active through 21:59:38, approximately five minutes after connection, including the verified one-second gate recovery. It was left running. No long-run or forced network outage acceptance is claimed.
