# Investigate sustained STREAM / OUT frame-rate gap

Status: ready-for-human
Resolution: controller-triggered UI invalidation fixed; three HUD presets pass live pacing gate; extended gameplay remains manual follow-up
Type: task

## User request

2026-09-22: Record the Palworld playback discrepancy. The user expects output frame rate to closely match input frame rate during normal playback.

## Observed behavior and current definitions

During Palworld sessions, HUD STREAM averaged about 60 fps while OUT averaged about 53–54 fps. These were session-wide averages, not controlled foreground-only or rolling-window measurements. This is an unresolved performance issue, not an accepted steady-state loss budget.

- STREAM counts decoded RTCVideoFrame callbacks delivered to LiveVideo, divided by time since its first frame.
- OUT counts new-video-frame drawable presentation callbacks over the same elapsed period. It is not the display refresh rate.
- LiveVideo holds one latest frame; a newer arrival overwrites an unconsumed frame and increments skipped. MetalRenderer can also replace a pending unsubmitted frame. Its in-flight permits and drawable availability can defer work.
- Neither metric detects repeated image content. 60 stream frames may contain fewer distinct game images; this is separate from local presentation loss.

The mechanism permits skipped frames, but the dominant cause of this observed gap has not been measured. GPU overload, main-thread scheduling, display cadence mismatch, bursty frame delivery, window visibility changes and accounting issues are hypotheses, not findings. Earlier sampled GPU time was low; that does not rule out other rendering/presentation bottlenecks.

## Investigation and acceptance

1. Reproduce with a stable foreground Palworld window and known display refresh rate; separately measure startup, focus/visibility changes and steady playback.
2. Add bounded rolling-window input/output counters and categorized skip/wait evidence. Trace arrival, consumption, submission and presentation timing sufficiently to distinguish actual loss from counter artifacts.
3. During stable foreground playback on a display capable of the input rate, OUT should closely track STREAM. A persistent roughly 60-to-54 gap must be explained and corrected; define a measured tolerance and duration before declaring acceptance.
4. Preserve bounded latency and native hardware decoding/Metal surfaces. Do not inflate OUT with redraws of an old frame, or hide the loss by accumulating an unbounded queue.
5. Verify frame pacing and latency together; distinguish stream frames, unique game images and presented frames. Higher bitrate is not the proposed remedy for this issue.
6. Record automated regression checks separately from live display/game acceptance.

## Comments

- 2026-09-22: Created at the user's request. This records investigation work; no playback scheduling or counters were changed. High-bitrate and startup-language settings remain separately authorized in ../../stream-settings/issues/01-cloud-stream-preferences.md.

- 2026-09-22: User confirmed Simplified Chinese works and reported the continuously increasing FRAMES skipped counter. Two live HUD observations approximately 40 seconds apart showed skipped 834 → 1203 (+369, roughly 9–10 skipped frames/s), STREAM avg 60.0 and OUT avg 53.2 → 52.6. Both observations reported focused/active Xbox input, zero decode errors, zero reported network loss, GPU p95 0.6 ms and presentation p95 approximately 43 ms. This supports sustained local pre-presentation skipping rather than just an old startup count. It does not isolate the pacing/scheduling cause or prove there were no intermediate visibility changes. Current skipped counter increments when an unconsumed latest frame or an unsubmitted renderer frame is replaced; it does not measure distinct game images or network packet loss. Make the HUD label explicitly cumulative and add a recent-window skip rate in the investigation.

- 2026-09-22: Investigation localized all measured skips to inbox overwrite, not GPU busy/drawable failure. Added a red regression on the real LiveVideo callback/consumption path, then a bounded two-frame FIFO with 50 ms stale discard. 88 tests and signed release build pass. Controlled main-menu window improved from 59.79 in / 58.31 out, 1.47 skips/s to 60.12 in / 59.80 out, 0.31 skips/s. Recent presentation p95 approximately 38 ms before and 42 ms after; not an input-to-photon measurement. See ../pacing-investigation.md. Remaining: extended gameplay/controller feel and direct rolling HUD skip-rate display.

- 2026-09-22: User tested the rebuilt version and reported: “我感觉比之前的效果好不少, 轻微的卡顿丢帧感明显减少了”. Physical gameplay feedback confirms a noticeable reduction in stutter/frame-loss sensation. No separate statement about perceived input delay or test duration was provided; do not infer either. Core smoothness improvement is accepted; longer sessions and remaining occasional skips remain follow-up work.

- 2026-09-22: Reopened after same-process long-session failure: 7.42 skips/s, output ~53 fps, draw interval p95 ~54 ms while arrival/GPU timing remain normal. Main-thread sampling shows significant SwiftUI library layout work; changing controller packet counts embedded in the 250 ms observable status update are a concrete candidate. Earlier controlled tests disabled controller input and missed this workload. See ../pacing-investigation.md.

- 2026-09-22: Removed per-250 ms library status updates containing changing controller packet counts. HUD samples now refresh at 1 Hz and hidden mode skips text layout. Old controller reconnect reproduced 7.16 skips/s; rebuilt process with controller input active measured Detailed 0.40/s, Hidden 0.17/s, Compact 0.21/s over 33–41 second windows. All pass the existing <=1/s diagnostic threshold. HUD OUT avg 59.7 vs STREAM avg 60.0. User observed “out avg 有 59.7fps 这个很不错哦, 比之前好很多”. This is controlled main-menu acceptance, not hours-long gameplay or zero diagnostic overhead proof. 90 tests and signed release build pass.
