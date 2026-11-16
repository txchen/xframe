# Library, startup and benchmark redesign

Approved 2026-11-15 from design-v1.png. Implementation in progress.

- Readable library cards, standard/large density, clean sidebar and inline stream preferences.
- Immediate playback window on launch, observable connecting overlay until the first frame finishes GPU rendering; cancel uses existing session cleanup. No test pattern during streaming startup.
- Benchmark: individual workload selection, quick/standard sample counts, automatic pinned GitHub Release model downloads with hashes, manual imports retained.
- Include pending HUD GPU queue / display wait change.
- Verify relevant behavioral tests, full suite, rendered UI previews, signed/notarized archive and public Homebrew fetch. Live Xbox and M5/large-screen acceptance remain user checks.
- Publish 0.1.3 build 4; preserve user processes and .audit files.

## Validation

- 209 tests passed; separate opt-in window test verified the real decoded frame / Metal completion callback hides the startup overlay.
- Presentation-time callback was unsuitable as a loading gate: the native test environment reported zero presented timestamps both with and without the overlay. GPU completion is used for readiness; presentation statistics remain unchanged. No claim that the test measured physical display latency.
- FG and NR public downloads exercised through the app cache code, including archive and weights hashes.
- Signed app selected VT720/FG720/NR720 Quick run: see m1-quick-validation.json; only selected rows and their preparation-inclusive counterparts, 15 samples each.
- Rendered native catalog components at 900/1440 points, connecting view, and benchmark view; no live Xbox session started by the agent.
