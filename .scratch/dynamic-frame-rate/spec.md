# Dynamic frame-rate diagnosis and replay samples

Status: ready-for-human

User request: diagnose continuously varying Palworld cadence, roughly high-50s → low-40s → high-50s (for example 58→42→58), before implementing frame interpolation.

Implemented: bounded numeric trace of decoder input, decode completion, delivery and actual presentation, with RTP source timestamps. Active-session export is available through Cloud Games → Export frame timing sample…; no session termination is needed. Schema 9, at most 16,384 events (~68 seconds at 60 fps with all four stages). The buffer overwrites its oldest entries. Export immediately after the transition.

## Real capture acceptance (pending)

Use the rebuilt app. Keep pacing, scaling, refresh rate and window visibility fixed. Play a known Palworld scene for about 30 seconds that includes the natural decline and recovery in frame rate. Exact 60/40 fps values, fixed plateaus, or a specific transition shape are not required. Preserve all variable frame intervals; do not round or normalize them to 60/40. Export immediately as `samples/palworld-variable-fps.json`. Record scene, graphics settings, display refresh rate and observed HUD changes separately. Repeat once. Do not label synthetic traces as gameplay evidence.

This is a timing replay sample, not a playable video. Visual interpolation/duplicate-image assessment still needs an accompanying gameplay recording. No media is automatically captured by the diagnostic export. Actual packet arrival timestamps are unavailable at the decoder API; decoderInput is after WebRTC reassembly/jitter buffering. RTP tracks encoded cadence, not unique game images. RTP absolute time must not be subtracted from host time.

## Replay

```sh
python3 scripts/replay-frame-trace.py .scratch/dynamic-frame-rate/samples/palworld-variable-fps.json --output .scratch/dynamic-frame-rate/samples/palworld-evaluation.json
```

Output includes common one-second stage-rate windows and every target 60 Hz tick: original/interpolate, left/right RTP references, blend alpha, future-source wait and required delay. Missing decoded references remain unavailable. RTP wrap is supported; duplicate/reordered timestamps, resets and gaps over one second fail closed (capture a continuous segment). The ring's incomplete boundary references may be unavailable.

Interpretation: source cadence declines with input and decode → encoded-source cadence changed, without proving game-render cadence; steady source cadence with bursty decoderInput → upstream delivery/jitter buffering; stable input with missing/late decoded → decoder; stable decoded with missing/late presented → local delivery/render/presentation. These are localization signals, not automatic causal proof.

Two-sided interpolation is evaluated against first decoder input + elapsed source time. Required delay includes decode and delivery jitter, excludes interpolation compute and display scheduling. It is not incremental delay over current playback or input-to-photon latency. Add measured generation cost before choosing a real buffer. Extrapolation is not modeled.

## Validation

Synthetic sample is explicitly marked synthetic. An aligned 40 fps second on a 60 Hz grid has 20 originals and 40 interpolated output frames; maximum future-reference wait is 16.67 ms, or 20.67 ms with the fixture's 4 ms decode latency. Other grid phases can approach a full 25 ms source interval. This does not measure Palworld.

Real Palworld transition recording and causal diagnosis remain pending user-controlled scene reproduction. No frame generation or playback pacing changes were made.

Automated verification (2026-09-22): full Swift suite passed 145 tests; Python replay suite passed 3 tests (transition/RTP wrap, missing reference, discontinuity). Release app built and codesign verification passed at `.build/XFrame.app`. Additional presentation-trace regression checks duplicate and zero-time drawable callbacks. Live UI/capture and measurement overhead have not been verified on the rebuilt app.

User clarification: 60→40→60 was shorthand for a range, not exact rate targets. The evaluator uses each actual RTP interval and does not classify frames into fixed 60/40 modes. Added a continuously varying approximately 58→42→58 synthetic trace, including RTP tick quantization, to verify per-tick references and delay. The earlier aligned 40 fps arithmetic is only one model example, not a prediction for gameplay. The current model resamples onto a strict 60 Hz grid; a future policy that keeps nearby originals or repeats frames will yield different generation counts.
