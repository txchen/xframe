# Live acceptance — 2026-09-22

In progress. User explicitly requested computer-use acceptance, including the previously proposed test plan.

- The existing process had started at 11:18, before the new 13:09 build. Its library showed Session ended and an old connection error. Quit it normally and launched the current signed app at 13:14; restored account access and loaded 2,673 catalog games.
- Configuration: Palworld, Automatic/WESTUS2 requested region, HQ, Simplified Chinese, Balanced, controller enabled, Detailed HUD, audio volume 100%.
- Host default route is Ethernet, not Wi-Fi. Passwordless administrator access is unavailable, so an autonomous timed host wake / privileged Ethernet rollback cannot currently be guaranteed. No host network or sleep mutation has been performed.
- Computer-use can inspect and manipulate the app, but cannot physically operate the Bluetooth controller or certify audible A/V synchronization. The user has been offered the option to provide physical controller input while automated inspection continues.

## Runs

1. Palworld: successful live start, first frame at 14.438 s after local connection creation. 83.73 s connection duration; 4,153 decoded / 3,987 presented frames, 0 decode errors, 0 lost packets, 1 NACK. Audio track attached, 3,586 audio packets and nonzero energy; actual sound not independently heard by the agent. Fullscreen at 3840x2160 backing pixels, return to window, and resize to 3064x1634 backing pixels retained Aspect Fit and playback. Window/fullscreen transitions contributed skipped/not-presented frames; this is not a pristine pacing benchmark. Closing playback ended the cloud session and restored Play. Export: `.build/p0-live/01-palworld-window-transitions.json` (schema 7, stopped).

## Scope update

The user connected a controller, requested a different game and an opt-in keyboard fallback, then requested a game that supports 60 fps on Series S. Selected Forza Horizon 5: the live catalog shows Game Pass / Playable, and the official performance specification lists Series S Performance at 1080p60 versus Quality at 1440p30: https://forza.net/news/forza-horizon-5-early-access . Actual cloud hardware/profile and game settings still need observation; stream fps is not game fps. Keyboard implementation proceeds before continuing live tests.

2. Forza Horizon 5, HQ / zh-CN / Balanced / Automatic (now WESTUS requested): title screen and loading sequence measured approximately 29.7–29.9 decoded fps and 29.6–29.8 presented fps. User correctly flagged that this is not yet a 60 fps test. Keyboard J (A) visibly advanced from title screen to game loading, proving a real keyboard-to-game input round trip. One asynchronous decoder error and nine recovery-skipped frames occurred, with 0 RTP packet loss / 0 NACK at the observed point; retain/export its timeline before concluding causality. Game performance mode is not yet verified.

The user confirmed handover for Forza graphics settings. Switched View > Enable Controller Input; HUD subsequently reported `Xbox Wireless Controller · input active`, with keyboard mode disabled. No game UI actions will be sent while the user adjusts the mode. At handover the stream remained 29.9/29.9 fps, 1 decoder error and 9 recovery skips; lost packets and NACK were still zero.

## Forza mode change and session close

- User changed graphics mode and restarted the game within the cloud session. Post-restart counter deltas over 35.257 s gave approximately 59.85 decoded / 59.48 presented fps; HUD lifetime average remained in the 30s and rose slowly. This measures stream frames, not internal game rendering FPS.
- Exported `.build/p0-live/02-forza-mode-switch.json`: outcome stopped, duration 1358.9 s. Four asynchronous badData events followed decoder configuration changes; each was followed by a keyframe request and resumed frames. No root cause claimed.
- Ended normally before installing automatic input ownership build. This session included loading, mode changes and background operation; not a clean steady-state performance acceptance run.

## Short outage failure and lifecycle checks

- Rolling-FPS build live title screen showed STREAM/OUT 30.0 fps over 2s separately from SESSION avg 30.7/29.8. This particular fresh session started with a 30 fps stream; do not reuse the preceding session's 60 fps conclusion.
- User performed requested ~5 s network interruption and reported completion. Session terminated: recoveryStarted at 93364 ms, transportFailed at 95649 ms. Export `.build/p0-live/04-forza-short-outage-failed.json`. The previous diagnostic schema did not distinguish input backpressure, ICE failure or channel closure, so the exact terminal trigger is not proven. Short-outage acceptance failed.
- Initial remote cleanup failed while offline; after user restored connectivity, End Session succeeded and Retry appeared. Explicit Retry launched Forza again (attempt 5); End Session during startup returned to Session ended with Play enabled. This is startup-cancellation evidence, not a fifth completed gameplay session.
- Fix candidate unifies input-send backpressure with 15 s health policy, clears stale held input, extends transient heartbeat retry delays to 1/2/4/8 s, and adds typed input/ICE/channel cause events. Full 124 tests pass; a new live outage run is required.

## Short outage retest — recovery build

- Signed `.build/recovery-fixes-build.log` build, attempt 6 (fifth attempt to reach video; attempt 5 was cancelled during startup). Same HQ/zh-CN/Balanced session settings, both input devices enabled.
- User performed another requested ~5-second interruption and reported automatic recovery. Observed the same playback window and cumulative counters continuing without Play/Retry; recent input/output returned to 60/60 fps while SESSION average remained ~52.5/51.6 due to the gap.
- Tool-generated J resumed game loading and HUD became Keyboard; user then confirmed both audio and physical controller operated normally. Independently observed Xbox Wireless Controller input active.
- After loading, recent rate 60.0/59.5, zero decoder errors/recovery skips. This is a successful short-outage retest and promising format-change result, not a 30-minute soak or proof that every historic decoder error is resolved. Final timeline exported after normal session end (below).

## Final retained evidence and scope

- `.build/p0-live/06-forza-outage-recovered.json`, normal stopped outcome, ~245.8 seconds. RecoveryStarted 56797 ms -> recoveryCompleted 66746 ms (9.949 s); inputSendBlocked 57030 ms, transportDisconnected 62271 ms, transportRecovered 64978 ms, inputSendRecovered 66475 ms, IDR 66564 ms. The requested physical interruption was approximately five seconds; end-to-end transport/media recovery took longer.
- DecoderFormatUpdated at 124627 and 127958 ms while configuration count remained 1, with zero badData. This demonstrates compatible session reuse in the actual Forza loading path that previously rebuilt and errored. Historic Fortnite failures are not all proven equivalent.
- Final recent HUD input/output 60/60 fps, Xbox controller active. End Session completed; library Play re-enabled. No cloud session remains active.
- User explicitly deferred sleep/wake testing as low importance on 2026-09-22. It is no longer a gate for this iteration; implementation remains, physical acceptance is deferred.
- Remaining live scope: controlled 30+ minute gameplay/A/V soak and long-outage terminal behavior; the normal 30-minute soak was not completed. Five attempts reached video across six starts; one startup cancellation was separately verified.
