# Streaming reliability validation

Date: 2026-09-22. Implementation is recorded in the commit containing this validation update, on top of the existing roadmap baseline.

## Delivered

- A 15-second bounded recovery window for ICE disconnection; repeated disconnected callbacks do not renew it. A video gap of 2 seconds enters recovery; 15 seconds without video terminates the stream. First-frame timeout remains distinct at 45 seconds after signaling/configuration.
- Recovery status in the library and Compact/Detailed HUD. Input ownership is suspended, queued held state is released, and controls must return to neutral before rearming. Disconnected transport stops input sends; a neutral state is delivered when transport permits. Remote release cannot be guaranteed while packets cannot reach the server.
- Keyframe requests at most once per second during recovery, retaining decoder requests until they can be sent. No ICE restart or automatic new cloud allocation is claimed; recovery depends on the existing WebRTC transport reconnecting.
- Independent heartbeat task: retry transient network errors / HTTP 408, 500, 502, 503, 504 with 1-, 2-, 4- and 8-second delays; fail after five consecutive failures. Authorization and other service failures terminate immediately. Existing service request timeouts still apply. An outstanding HTTP heartbeat no longer blocks the video watchdog; teardown cancels it.
- System sleep ends local input/audio/video immediately and requests remote deletion, retaining creation/transfer handles. Wake retries a previously failed cleanup when idle. No game launches on wake. If cleanup is still in flight and later fails, End Session remains available for explicit retry.
- Retry button is available for the failed/sleep-ended game only after confirmed cleanup, and is cleared by catalog/account reset. A creation request that returned no handle retains the existing unknown-allocation warning without the Retry shortcut.
- Schema-7 exports include allowlisted startup, transport, first-frame, video-stall, decoder, heartbeat and sleep/recovery events. Failure is recorded before close and retained after repeated close. Decode-error counters remain reserved for actual decoder errors.

## Automated evidence

- Red regression: `bash scripts/test.sh --filter closingFailedVideoPreservesFailureForWatchdogAndHUD` failed with two expectations: both the watchdog state and HUD snapshot became `Stopped` instead of `Failed: decoder stopped` after `stop()`.
- Cause: `LiveVideo.stop()` unconditionally replaced the failure state. Separately, connection errors escaped through a `defer { close() }` without recording a terminal failure. Close now preserves failure state, and the connection lifecycle records typed failure before teardown.
- Full suite: `bash scripts/test.sh` — **109 tests passed**, including real VideoToolbox corruption/recovery and Metal rendering tests. Log: `.build/p0-tests.log`.
- New checks cover recovery deadlines and duplicate disconnects, first-frame versus video-stall classification, keyframe rate, connection error/cancellation teardown, transient/terminal heartbeat errors and in-flight cancellation, sleep during creation, wake cleanup retry, retry ownership guard, and HUD recovery status.
- Signed development build: `bash scripts/build-app.sh` succeeded; embedded WebRTC and app signing plus `codesign --verify --deep --strict` passed. Artifact: `.build/XFrame.app`; log: `.build/p0-build.log`.
- `git diff --check` passed.

## Live acceptance still required

These are not replaced by passing unit tests, generated media fixtures or a successful build:

1. Repeat game startup and end/retry at least five times; export any failing timeline. The original intermittent startup VT bad-data root cause remains unconfirmed. See [existing issue](../cloud-video/issues/01-intermittent-startup-decode-errors.md).
2. Play for at least 30 minutes with physical controller and audible game audio. Check A/V synchronization initially, after 15 minutes and at the end; compare fullscreen/window transitions and resizing.
3. During an explicitly supervised session, interrupt network briefly (<15 s), then restore. Verify visible recovery, fresh video, audible audio, neutral input rearming and no replacement session allocation. Repeat with a longer outage and verify cleanup failure/retry behavior if the service is unreachable.
4. **Deferred by user; not a current gate:** Sleep during active play and during startup. On wake, verify local resources are stopped, deletion completes or End Session clearly remains actionable, and a new game requires explicit Play/Retry.
5. Verify Compact/Detailed recovery overlay and Retry layout in the signed app. Hidden HUD remains hidden by user preference.

Live sessions have now been exercised: see [live records](live-validation-2026-09-22.md). Short network interruption, restoration of audio/input, repeated starts, cleanup retry and startup cancellation now have live evidence. Sleep is deferred by user. Long-outage and extended-play acceptance remain. P0 streaming reliability remains unchecked until live acceptance and the original decode evidence gap are resolved.

## Live-driven follow-up

124 tests pass (`.build/recovery-fixes-tests.log`). Input backpressure now enters the same 15-second recovery policy instead of bypassing it with a 2-second teardown. Typed input blocked/recovered, ICE failed and data-channel-closed events make future terminal causes distinguishable. The short-outage failure and cleanup/Retry/startup-cancellation checks are recorded in the live log. Signed build: `.build/recovery-fixes-build.log`.

Short-outage retest passed: 9.949 seconds from recovery start to completion in `.build/p0-live/06-forza-outage-recovered.json`, without new allocation. User confirmed audio and physical input; HUD returned to 60/60 recent fps. Compatible decoder parameter updates retained a single VT configuration and zero decode errors. See live log for precise limits.
