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
- Live single-controller integration is implemented behind View > Enable Controller Input; Palworld controls and focus-loss release have passed user-observed physical acceptance. Rumble remains deferred.
- Current implementation passes 97 tests and the signed development app builds. Individual feature documents record remaining live-validation limits.

## Priority and completion criteria

### P0 — Complete the playable xCloud loop

- [x] **Basic controller integration — Xbox One Bluetooth.** Accepted by the user on 2026-09-22 after Palworld tests covering controls, focus release, reconnect, fullscreen and repeated-session input. PS4 / DualShock 4 and other controllers are **not tested**. Abrupt battery-removal release delay remains a [known limitation](../controller-input/issues/02-abrupt-power-loss-delay.md); rumble is a separate future increment. Input remains opt-in via View > Enable Controller Input. Delivered in the controller, streaming settings and pacing implementation commit (see Git history for this roadmap update). [Validation](../controller-input/validation.md), [spec](../controller-input/spec.md).
- [ ] **Streaming reliability.** Investigate intermittent startup decode errors, network interruptions and recovery, sleep/wake, and safe session teardown/retry. Validate extended play, audio/video synchronization and window/fullscreen transitions. Keep startup failures separate from decode failures. [Known decode issue](../cloud-video/issues/01-intermittent-startup-decode-errors.md), [performance validation](../playback-performance/validation.md).

Recommended next step: streaming reliability and playback settings; retain abrupt controller power-loss latency as an explicit limitation. Basic physical controller gameplay and focus-loss release are verified; rumble is a separate increment.

### P1 — Playback quality and controls

- [ ] **Playback controls and settings.** Fullscreen-friendly controls, end-session action, audio preferences, diagnostics visibility and persistent user settings. Native fullscreen, mute/volume and the Compact/Detailed/Hidden HUD are implemented; the HUD adds measured video Mbps, Command-Shift-D and a local View+Menu chord. See [HUD acceptance](../performance-hud/validation.md). Persistent HQ and game-language settings are implemented under Streaming Settings; Palworld Simplified Chinese and persistence are verified. HQ connects but higher negotiated quality is not yet demonstrated; see [validation](../stream-settings/validation.md). Numeric custom bitrate remains pending. See [source research](../stream-settings/xstream-research.md).
- [ ] **Frame pacing — partially delivered.** Balanced (default) and Low latency (experimental) are implemented as persistent next-session settings, with active mode in detailed HUD and schema-6 diagnostics. Balanced retains two decoded frames; Low latency retains the newest waiting frame; both expire stale frames after 50 ms. The signed build and 97 tests pass. Live comparative latency/cadence acceptance, adaptive queues and 30/60fps / 60/120Hz coverage remain. Smoothest is deferred pending evidence that extra buffering helps; it is not required just to mirror Android labels. [Implementation and acceptance](../playback-performance/issues/03-frame-pacing-options.md). Measure latency and smoothness rather than simply adding buffering. The observed Palworld input/output gap was localized to the single-frame inbox; a bounded two-frame fix improved measured output to ~59.8 fps for ~60.1 fps input. The user confirmed noticeably smoother gameplay and fewer mild stutters. Longer-session/pacing-mode work remains; see [investigation](../playback-performance/pacing-investigation.md). [Tracked discrepancy](../playback-performance/issues/01-stream-output-frame-gap.md).
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

### Latest native latency experiment — 2026-09-22

Retained 25 ms freshness catch-up within the two-frame queue and accurate actual-presentation accounting; rejected slower display-link/arrival-driven experiments. The subsequent controller-connected verification passed all three foreground HUD pacing gates (~0.22–0.44 skips/s, OUT ~59.6); the user reported the experience was much improved. Actual local display latency remains above the 25 ms mean experiment target. The selectable pacing build subsequently passed 97 tests; Low latency live acceptance and longer sessions remain pending. [Evidence and limitations](../playback-performance/latency-optimization-validation.md).

## Remaining scope at this commit

Checkbox count: **9 unfinished top-level items**. **8 belong to the current macOS roadmap**, plus **1 deferred iPhone/iPad item**. A checkbox denotes the entire epic, so partially delivered work is not counted as unimplemented from scratch.

- Partially delivered current work (4): streaming reliability; playback controls/settings; frame pacing; performance monitor.
- Remaining capability/distribution work (4): Console Remote Play; MetalFX spatial upscale; library completeness additions; security and packaging (notarization, reproducible distribution and Keychain migration).
- Deferred platform work (1): iPhone/iPad.

Other-controller validation, abrupt power-loss detection delay, rumble and multi-controller support remain explicit follow-ups rather than additional top-level checkbox items. Low latency UI/live performance validation is pending; this commit does not claim experimental mode reduces measured latency.
