# Cloud Video Validation

## Automated

`bash scripts/test.sh`: 26 tests passed. The new VideoToolbox/WebRTC decoder integration decoded all 720 fixture access units, verified hardware decoding and video-range NV12/IOSurface output, and verified a one-frame display buffer and stop behavior. Existing authentication, session cleanup, and local-video checks passed. SDP/ICE response envelopes and keepalive were covered with stubbed HTTP responses. A regression test first reproduced fatal handling of `kVTVideoDecoderBadDataErr`, then passed after making that error recoverable and requesting a keyframe.

`bash scripts/build-app.sh` succeeded with the pinned WebRTC 153.0.0 framework. Both framework and app were certificate-signed, and `codesign --verify --deep --strict` passed.

## Signing

With explicit user approval, `XFrame Local Development` was created/imported into the user login Keychain. Temporary key/export files were removed by the setup script. No system trust setting was changed.

The ad-hoc designated requirement was code-hash-bound. The certificate-backed requirement is now the application identifier plus certificate fingerprint. It remained identical across different source builds. This proves signing-identity stability, not the absence of future Keychain prompts. An earlier UI timeout was incorrectly interpreted as an authorization prompt: the user reported seeing none, and the account subsequently appeared restored. Launching the latest recovery build again timed out while a SecurityAgent process was present. The UI tool explicitly disallows inspecting SecurityAgent, so no prompt contents or pending authorization could be verified. No security prompt was acted upon. Unattended restart validation remains incomplete.

## Live Video

### Startup Error Counters Follow-up

A changed build adds bounded numeric diagnostics: recoverable errors before the first rendered decoded frame, submitted H.264 IDR access units, and WebRTC decoder missingFrames hints. No video payloads, credentials, SDP, or candidate addresses are logged. These are diagnostic counters, not a fix or complete packet-loss telemetry.

A WESTUS2 Fortnite run showed 60 recoverable errors, zero before the first frame, 12 IDR submissions, and zero missing-frame hints. A later observation showed 60 errors, 13 IDR submissions, and zero hints while average decode/presentation rose from 48.9/47.3 to 55.4/54.1 FPS. The queue remained 1/1. The hypothesis that all errors occur before initial decoded output is false for this run. Zero missing-frame hints does not prove zero packet loss. IDR submission counts do not indicate successful IDR decode and cannot establish the error cause.

The session was explicitly ended and the library confirmed Session ended. Next investigation should distinguish synchronous versus asynchronous VT failures, associate failures with IDR/delta access units and parameter-set changes, and correlate them with inbound RTP statistics before changing decoding behavior. All 29 tests passed with the new counters; the release build succeeded.

### Recovery Build Acceptance (2026-09-22 UTC)

The same installed build restarted and restored the account in approximately two seconds; the user confirmed that no password prompt appeared. This verifies one same-binary restart only. Rebuild-related repeated authorization remains unresolved.

A fresh Fortnite session was started at approximately 04:40:48 UTC. Video was observed continuously for more than three minutes after the first decoded-frame observation, including entering and leaving full screen. The final overlay showed 1920×1080 H.264, hardware decoding enabled, average decode 59.2 FPS, average presentation 57.9 FPS, 273 skipped frames, and a bounded 1/1 display queue. Twenty recoverable decode errors accumulated early; the count then stayed at 20 while playback continued. This exercises the recovery path against the real service, not only the regression test.

The preview remained at Fortnite's animated account-link screen. No game input, confirmation, account linking, or audio validation was performed; this is not an active-gameplay or long-duration stability result.

Command-0 stopped video and restored the static render view. The library then showed `Session ended`, with Start Session enabled and End Session absent. This UI state is reached after a successful session-deletion response. No active test session was left running.

The automated suite was rerun: all 26 tests passed in 3.249 seconds. `git diff --check` and `codesign --verify --deep --strict .build/XFrame.app` passed. The installed app was not rebuilt or re-signed during this acceptance run.

### Earlier Runs and Diagnosis

Fortnite produced a real 1920×1080 H.264 picture in the native Metal window. The overlay confirmed Hardware: Yes. Separate observations showed average decode/presentation rates increasing from 43.5/40.3 to 53.8/52.3 FPS, with a bounded 1/1 queue. Full screen used a 3840×2160 drawable and preserved picture proportions. No game input or Epic account linking was performed.

The initial sustained test ended prematurely with the generic connection error. The cloud session was successfully cleaned up. Diagnostics were then split to distinguish video-pipeline errors from ICE connection failure. A second live run identified VideoToolbox status -12909 (`kVTVideoDecoderBadDataErr`). The recovery build drops that bad frame and requests a keyframe, with rate limiting and the existing no-frame timeout retained. Automated regression coverage and the subsequent supervised live acceptance above passed.
