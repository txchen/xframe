# XFrame feature roadmap

Updated: 2026-09-22. Baseline: `1944c38`.

This is the agreed implementation order, not a claim that every item is fully specified. Keep this document current as features ship; link detailed specs and validation evidence rather than marking an item complete after compilation alone. The broader product requirements remain in [Design & Requirements](../../xframe_requirement.md).

## Current baseline

- macOS 27+ on Apple Silicon; repository content and UI are English.
- Microsoft sign-in and restoration, xCloud catalog and session lifecycle.
- Native WebRTC H.264, verified VideoToolbox hardware decoding, Metal rendering, Aspect Fit and Retina output.
- Native game audio, mute and volume; the user has confirmed audible output.
- Unified account/library window, on-demand playback window, independent window geometry persistence.
- Search, categories, favorites, sorting, pagination, grid/list layouts and account-aware playable filtering.
- Explicit denied/unknown entitlement labels and launch guards. Catalog access is not proof of permanent ownership.
- Bounded diagnostics, JSON export, local timing distributions and offline regression checks.
- Pure controller packet encoding exists; live controller input and rumble remain disabled.
- At this baseline, 64 tests pass and the signed development app builds. Individual feature documents record remaining live-validation limits.

## Priority and completion criteria

### P0 — Complete the playable xCloud loop

- [ ] **Controller integration.** Discover one physical controller through GameController; map buttons, sticks, triggers, D-pad, Menu/View and stick clicks. Connect input handshake and packet sending, handle backpressure, and release held inputs on focus loss/disconnect. Verify actual host response before enabling input by default. Add rumble separately after basic input is reliable. [Existing spec](../controller-input/spec.md), [protocol reference](../controller-input/reference.md).
- [ ] **Streaming reliability.** Investigate intermittent startup decode errors, network interruptions and recovery, sleep/wake, and safe session teardown/retry. Validate extended play, audio/video synchronization and window/fullscreen transitions. Keep startup failures separate from decode failures. [Known decode issue](../cloud-video/issues/01-intermittent-startup-decode-errors.md), [performance validation](../playback-performance/validation.md).

Recommended next step: controller integration when physical hardware is available. If it is unavailable, work on reliability and playback settings without claiming hardware acceptance.

### P1 — Playback quality and controls

- [ ] **Playback controls and settings.** Fullscreen-friendly controls, end-session action, audio preferences, diagnostics visibility and persistent user settings. Existing native fullscreen and mute/volume are a baseline, not the finished control experience.
- [ ] **Frame pacing.** Lowest Latency, Balanced and Smoothest modes; bounded adaptive queues; 30/60fps cadence and 60/120Hz display handling. Measure latency and smoothness rather than simply adding buffering. Balanced is the planned default.
- [ ] **Performance monitor.** Compact readable overlay, rolling graphs, network metrics, frame-time distributions and clearly separated queue/decode/GPU/presentation measurements. Do not label local stage timings as network or controller-to-photon latency. [Existing diagnostics](../stream-diagnostics/spec.md), [timing work](../playback-performance/spec.md).

### P2 — Expand capability and polish

- [ ] **Xbox Console Remote Play.** Console discovery/list, wake and session establishment; reuse the audio/video/input pipeline. Requires a real console for acceptance. xCloud remains the first implementation and testing priority.
- [ ] **MetalFX spatial upscale.** Optional spatial upscaling and sharpening, Retina output sizes, resize/display reconfiguration, visual comparison and GPU/latency measurements. This is not frame interpolation.
- [ ] **Library completeness.** Recently played, metadata/artwork caching, automatic refresh, game details and actionable entitlement errors. Add an Owned collection only with reliable purchase evidence; do not infer ownership from a subscription grant. [Entitlement boundaries](../game-library/entitlements.md).

### Before distribution

- [ ] **Security and packaging.** Formal signing and notarization, reproducible distribution build, and migration from the approved development credential file back to Keychain. Verify changed-build access and safe migration before removing the fallback file. Never broaden Keychain access to all applications. [Tracked credential work](../keychain-access/issues/01-restore-keychain.md).

### Later, not required for this macOS increment

- [ ] **iPhone/iPad.** Reuse the streaming core with platform-specific interface, lifecycle and input integration.
- Multi-controller support and experimental frame interpolation are future work, not current release requirements.
- Windows, Linux and PlayStation support are outside this project's v1 scope.

## Working rules

- Preserve the native hardware media pipeline while polishing the interface.
- Keep account entitlement, catalog membership and purchase ownership distinct.
- Record tests, live checks and outstanding hardware/manual acceptance separately.
- Before implementing a roadmap item, create or update its feature-local spec/issues under `.scratch/<feature>/`; use the repository triage status conventions for issues.
- Record the implementation commit and validation evidence here when completing an item. This roadmap does not authorize purchases, account changes, credential migration or unattended cloud sessions beyond the user's request.
