# Evaluate user-selectable frame pacing

Status: ready-for-human
Type: research
Resolution: implemented and packaged; 97 tests pass; UI and live comparative acceptance pending

## Request

2026-09-22: Investigate Moonlight frame pacing controls and whether XFrame should provide something similar.

## Recommendation

Keep the current bounded two-frame / 25 ms catch-up / 50 ms stale policy as the default Balanced behavior. Evaluate an opt-in Low latency experimental policy, with a reversible per-playback setting and measured actual presentation improvement before shipping. Do not expose four upstream Android labels as if their implementation were portable to macOS. A bounded smoothness-first option is deferred until it demonstrates cadence benefits beyond Balanced.

## Validation requirements

- Separate decoded-frame queue policy from Metal VSync/display scheduling; vary one mechanism at a time. Keep controller packet frequency and 1 Hz telemetry unchanged.
- Hold received stream FPS, physical refresh, window mode, controller input and scene constant. Use repeated A/B/A windows to reduce phase bias.
- Compare actual drawable presentation mean/p95, display interval distribution and tail stalls, output coverage and separate skip reasons. Average output FPS alone does not measure pacing.
- Preserve bounded frame count and maximum age in all modes. Mode changes must retire excess queued frames explicitly, remain thread-safe and not replay stale frames after focus changes/stalls.
- Do not assume a one-frame latency gain, restore the previously rejected 16.7 ms cutoff as a proven improvement, or relabel the larger skip rate as success. Candidate needs both measured latency benefit and an explicit smoothness tradeoff assessment.
- Do not implement a 59 Hz local render cap as a substitute for controlling a 60 fps cloud host. No host-FPS control is established by current session settings.
- Surface active policy in detailed HUD and exported diagnostics if implemented; avoid per-frame observable settings/UI work.

## References

See ../moonlight-frame-pacing-options.md for upstream source analysis, and ../latency-optimization-validation.md for prior rejected experiments and current baseline.

## Comments

Research only for this request; running game and application code are unchanged.

2026-09-22 user authorized implementing the selectable option. Initial delivery uses next-session application, consistent with other streaming settings; no live queue mutation. Low latency is explicitly experimental and retains only the newest waiting frame. Measured latency benefit remains unclaimed.

Validation: scripts/test.sh passed all 97 tests; signed scripts/build-app.sh succeeded; git diff --check clean. Preferences snapshot test now includes differing pacing policies; low-latency test checks queue replacement, stale expiry, stop behavior, active HUD label and exported enum. Native UI inspection returned cgWindowNotFound although the existing process is running; no forced restart or live latency claims.
