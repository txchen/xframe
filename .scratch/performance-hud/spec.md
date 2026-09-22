# Performance HUD presets and measured video bitrate

User-approved 2026-09-22: default Compact; Command-Shift-D cycles Compact → Detailed → Hidden. View + Menu should perform the same cycle while playback owns controller input. Expose explicit presets in the View menu and persist the selection. Make background more transparent than the previous 80% black panel; keep text readable and the overlay click-through.

Measure received video Mbps from consecutive video inbound-rtp bytesReceived and report timestamps. Native WebRTC timestamps are microseconds, unlike the browser milliseconds in XStreaming. First/missing/reset/switched-source/out-of-order samples must not fabricate throughput; stale metrics become unavailable. Do not mix video payload bitrate with requested limits or total network bandwidth. Include the optional metric in the explicit diagnostic export allowlist.

Compact uses three short lines for live streams: stream/present average FPS, requested SQ/HQ and measured video Mbps, and network + client latency estimate. Local playback retains two lines. Detailed retains useful network, frame, timing, audio and controller metrics, explicitly stating game-content FPS is not measured. Hidden removes the HUD without disabling collection.

Reserve View+Menu as a local shortcut. Buffer an initial View or Menu press briefly (300 ms) to recognize the chord, preserve standalone press/release semantics, suppress chord buttons until both are released, and trigger once per chord. Reset shortcut state on focus/device/session changes; never trigger while input is unowned. Do not affect other gameplay buttons/axes. Verify actual controller behavior separately from synthetic state tests.

Acceptance: meter math/lifecycle and chord sequencing tests; full suite/build; native compact/detailed/hidden keyboard/menu behavior and click-through; actual Mbps in a cloud stream; supervised Xbox chord without accidental game menu operation.

2026-09-22 follow-up: update HUD at 1 Hz and avoid hidden text formatting/layout. Keep changing controller packet counters out of the observable library status. Latency estimate is RTT + interval-average jitter-buffer residence + mean decode + mean post-decode presentation; do not sum overlapping frame-wait/GPU intervals or claim full input-to-photon. Missing/stale inputs remain unavailable. Use active-session quality, not edited next-session preferences. Window titles explicitly label logical view points and backing canvas pixels. See ../playback-performance/pacing-investigation.md for controller-active preset comparison.
