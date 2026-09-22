# Keyboard fallback validation — 2026-09-22

- `bash scripts/test.sh`: 114 tests passed, including axis normalization, opposites, every documented button, alias release, quick edge preservation through the production packet scheduler, repeat suppression, shortcut release, and mode exclusion. Log `.build/keyboard-tests.log`.
- `bash scripts/build-app.sh`: signed development build and signature verification passed. Log `.build/keyboard-build.log`.
- Signed app exposes Enable Keyboard Input and a readable Keyboard Controls dialog. Catalog search remained editable with keyboard mode selected.
- Forza live keyboard navigation is under validation; some tool-generated taps did not visibly register. Do not treat synthetic scheduler tests as proof of reliable physical keyboard gameplay.
- P0 live results, source FPS concerns and physical controller observations are tracked in ../stream-reliability/live-validation-2026-09-22.md.

## Automatic ownership update

- Both enable switches are now independent. Signed app UI confirmed `Keyboard + Controller · automatic switching`; library search still accepts text.
- 119 tests pass (`.build/auto-input-tests.log`); signed release build verified (`.build/auto-input-build.log`). Coverage includes fresh-button ownership, inactive stick drift, held controls, disabled devices, neutral-before-new-device ordering, and 50 ms keyboard tap hold with immediate explicit release.
- Basic bidirectional takeover is live-verified below. Long-duration alternating use and held-control/focus-loss cases still need physical acceptance.

- Live new Forza session: both switches enabled, initial HUD awaiting input; a computer-use J tap changed HUD to `Keyboard · input active` and advanced the title screen to loading. Fresh session measured around 60 decoded / 59.4 presented fps. Left running for physical controller takeover check.

## Bidirectional live takeover confirmed

- User confirmed the physical Xbox controller took over after keyboard input. Computer-use observation independently showed `Xbox Wireless Controller · input active` on the Forza festival playlist.
- A subsequent computer-use K/B tap switched HUD to `Keyboard · input active` and returned the game to its garage menu. This verifies the reverse takeover and an actual game response with both devices enabled.
- Session left open for user play. At this observation stream lifetime averages were approximately 59.3 decoded / 59.1 presented fps. Two asynchronous decode errors and 18 recovery skips were visible; this is not a clean decoder/P0 acceptance result.
