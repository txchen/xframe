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
- Current implementation passes 144 tests; the latest signed-build evidence is recorded in [playback settings validation](../playback-settings/validation.md). Individual feature documents record remaining live-validation limits.

## Priority and completion criteria

### P0 — Complete the playable xCloud loop

- [x] **Basic controller integration — Xbox One Bluetooth.** Accepted by the user on 2026-09-22 after Palworld tests covering controls, focus release, reconnect, fullscreen and repeated-session input. PS4 / DualShock 4 and other controllers are **not tested**. Abrupt battery-removal release delay remains a [known limitation](../controller-input/issues/02-abrupt-power-loss-delay.md); rumble is a separate future increment. Input remains opt-in via View > Enable Controller Input. Delivered in the controller, streaming settings and pacing implementation commit (see Git history for this roadmap update). [Validation](../controller-input/validation.md), [spec](../controller-input/spec.md).
- [ ] **Streaming reliability — implemented; core live scenarios passed, extended acceptance pending.** Added bounded transport/video recovery, independent heartbeat retry, sleep/wake cleanup, safe game retry after confirmed deletion, visible recovery status, and schema-7 typed terminal diagnostics. 124 tests pass; implementation is included in the commit containing this status update. Short-outage same-session recovery, restored audio/controller, normal end, cleanup retry and startup cancellation are live-verified. Extended play/A/V and long-outage acceptance remain; sleep/wake acceptance was deferred by the user as low priority. The parameter-change reference-chain defect is reproduced and fixed; post-fix Forza reused one decoder across two format updates with zero errors. Historic Fortnite failures may have additional causes. Startup failures remain distinct from decoder errors. [Implementation and acceptance](../stream-reliability/validation.md), [spec](../stream-reliability/spec.md). [Known decode issue](../cloud-video/issues/01-intermittent-startup-decode-errors.md), [performance validation](../playback-performance/validation.md).

Keyboard fallback was added during P0 live acceptance: View > Enable Keyboard Input, can run alongside physical controller input with last-active-device takeover, focused-window capture and neutral handoff. Basic bidirectional switching passed live Forza acceptance; extended keyboard gameplay/focus cases remain under validation. [Spec](../keyboard-input/spec.md), [validation](../keyboard-input/validation.md).

### Latest acceptance status — 2026-09-22

| Area | Status | Evidence / remaining scope |
| --- | --- | --- |
| Controller + keyboard | Basic live acceptance passed | Both enabled; bidirectional takeover and real game response verified. Extended held-control/focus cases remain. |
| Library navigation hit targets | Fixed and live-verified | Games/Favorites entire row and padding are clickable, minimum 44 pt height. [Evidence](../game-library/issues/01-sidebar-hit-targets.md). |
| FPS HUD | Delivered and live-verified | Recent 2-second STREAM/OUT rates; SESSION averages retained in Detailed. Does not measure internal game FPS. |
| Short network interruption | Passed after a live-found fix | Same session recovered in 9.949 s from recovery entry; user confirmed audio and controller. |
| End / cleanup retry / startup cancellation | Passed | Normal close, failed-cleanup retry, explicit Retry, and cancellation during startup verified. |
| Decoder parameter changes | Reproduced defect fixed; Forza retest passed | Two compatible format updates, one VT configuration, zero decode errors in final run. |
| 30+ minute gameplay / A/V soak and long outage | Pending | Keep the reliability checkbox open; five video starts are not a sustained-play result. |
| Sleep / wake | Deferred by user | Low-priority physical acceptance; not a gate for this iteration. |

Latest full suite: **133 tests passed**; signed app build verified. Controller enable/disable preferences now persist across launches; focus ownership and held inputs do not. [Live evidence](../stream-reliability/live-validation-2026-09-22.md). The commit containing this status update includes the reliability, keyboard, rolling-FPS and sidebar hit-target changes.

**Current increment: [1080p → 4K MetalFX Spatial](../4k-post-processing/issues/01-spatial-upscaling.md) is implemented.** Original / Integer Scaling / MetalFX Spatial switch during playback and persist across launches. The signed build and 133 tests pass; all three reached 60 fps recent output in a matched M1/4K Palworld menu comparison. MetalFX increased GPU and observed presentation cost. The user reports substantially better MetalFX quality and sharp Integer Scaling text; mild MetalFX motion artifacts are accepted as a quality observation. Extended A/V and settings-controller acceptance remain; sharpening and alternate backends follow separately. [Validation](../4k-post-processing/spatial-validation.md). Continue reliability soak/long-outage acceptance as separately tracked work; beginning P1 does not mark P0 complete.

### P1 — Playback quality and controls

- [x] **Playback controls and settings — accepted 2026-09-22.** The in-picture right-click / controller View+Menu panel now includes scaling, HUD, persistent cloud-game volume/mute, fullscreen controls, and confirmed End Session. Panel/library/close/Command-W termination entry points share default-Cancel confirmation, persistent cleanup progress and controller-accessible failure/retry; local navigation survives media teardown. 141 tests and signed build pass, plus 12 focused checks after the final layout adjustment. The user tested the restarted build from implementation commit `627d54a` and explicitly accepted this increment. This is user-reported practical acceptance, not a claim of per-scenario live fault injection. [Spec](../playback-settings/spec.md), [validation](../playback-settings/validation.md). Controller enablement remains persistent and exclusively in View. HQ, language and pacing remain in Streaming Settings. Numeric custom bitrate is a separate follow-up, not a completion gate for this controls increment. HQ's higher negotiated quality remains unproven; see [streaming validation](../stream-settings/validation.md) and [Black Flag HQ issue](../stream-settings/issues/03-black-flag-hq-no-video.md).
- [ ] **Frame pacing — partially delivered.** Balanced (default) and Low latency (experimental) are implemented as persistent next-session settings, with active mode in detailed HUD and schema-6 diagnostics. Balanced retains two decoded frames; Low latency retains the newest waiting frame; both expire stale frames after 50 ms. The signed build and 97 tests pass. Live comparative latency/cadence acceptance, adaptive queues and 30/60fps / 60/120Hz coverage remain. Smoothest is deferred pending evidence that extra buffering helps; it is not required just to mirror Android labels. [Implementation and acceptance](../playback-performance/issues/03-frame-pacing-options.md). Measure latency and smoothness rather than simply adding buffering. The observed Palworld input/output gap was localized to the single-frame inbox; a bounded two-frame fix improved measured output to ~59.8 fps for ~60.1 fps input. The user confirmed noticeably smoother gameplay and fewer mild stutters. Longer-session/pacing-mode work remains; see [investigation](../playback-performance/pacing-investigation.md). [Tracked discrepancy](../playback-performance/issues/01-stream-output-frame-gap.md).
- [ ] **Performance monitor — partially delivered.** Compact/Detailed/Hidden overlays, recent 2-second input/output FPS, session averages, video Mbps, network metrics and stage distributions are implemented. Rolling graphs and broader presentation polish remain. Do not label local stage timings as network or controller-to-photon latency. [Existing diagnostics](../stream-diagnostics/spec.md), [timing work](../playback-performance/spec.md).

### P1 — 4K monitor/TV quality pipeline

Implementation reference: [Veyra-NRVideo source study](../4k-post-processing/veyra-nrvideo-research.md) (research complete, pinned 2026-09-22). Read this before implementing the four items below; upstream Windows/RTX results are not Apple Silicon validation.

- [ ] **1080p → 4K upscaling and sharpening — partially delivered.** MetalFX Spatial, Original bypass and fullscreen Integer Scaling are implemented and live-tested; [remaining acceptance and measurements](../4k-post-processing/spatial-validation.md). Off/Low/Medium/High extra sharpening is implemented, with immediate panel selection, persistence, and 144 passing tests; the user observed a visible effect and accepted sharpening on 2026-09-22 ([validation](../4k-post-processing/sharpening-validation.md)). Alternate backends remain pending. Promote the previous P2 MetalFX item to P1. Implement MetalFX Spatial first with original-scaling bypass and adjustable sharpening; evaluate FSR 1 EASU/RCAS via Metal as an alternative. FSR 2+ engine-integrated temporal methods cannot be assumed usable with decoded video alone. Validate text, compression artifacts, color, resize and actual GPU/display cost on M1/4K. Separate source/flow/NR/output extents and investigate detail-preserving residual composition where NR is enabled. [Plan and primary sources](../4k-post-processing/spec.md).
- [ ] **Video frame interpolation — including 30 → 60 and variable input FPS.** Promote from later experimentation to a first-class P1 capability. The user observed Palworld incoming FPS varying from about 40 in complex scenes to 60 in simple scenes; variable cadence and 60 → 40 → 60 transitions are required cases. Use source timestamps and target display times rather than a fixed doubling assumption. Optional client-side image/optical-flow interpolation, with content-cadence detection for 30 fps game images inside 60 fps streams, scene-cut handling, bounded look-ahead, artifact checks and safe fallback. Evaluate MetalFX and other video-only approaches against their required inputs. GTA VI is a motivating future acceptance scenario if available, not a claim about its release, cloud availability or FPS. Generated frames must be counted separately and do not make game input/simulation run at 60 fps. Use source-derived motion with explicit units/confidence; preserve true PTS and distinguish freshness skips from temporal resets. Account for pair look-ahead and source-frame coverage. [Plan](../4k-post-processing/spec.md).
- [ ] **DLSS 5 / neural rendering feasibility.** Explicit research milestone for OpenDLSS-NR/Vulkan and possible Metal/Apple Silicon implementations. Determine hardware/extension compatibility, model rights and availability, image-only motion/history reconstruction, fidelity and real-time cost. Track as neural visual enhancement, separately from super resolution and frame generation. No claim of official DLSS support or M1 4K feasibility until demonstrated. Study Veyra’s low-resolution NR residual composition, protection regions and temporal history as independently implementable design ideas; constant-depth guidance is not recovered scene geometry. [Evidence and gates](../4k-post-processing/spec.md).
- [ ] **Combined 4K TV post-processing profile.** User-selectable upscaling + interpolation + neural enhancement where supported, with individual bypasses and comparison presets. Benchmark pass ordering/resolution and aggregate latency, A/V sync, memory and sustained frame cadence; auto-fallback when processing exceeds budget. Start comparisons with SR → NR residual → FG plus a separate unenhanced-source motion branch, then compare NR-before-SR. Cap generation before expensive work; track frame-pair/settings identities and GPU resource retirement. Apply no upstream ordering universally without backend-specific evidence. Full combination is a target contingent on prototypes, not a promise that all-on is best or feasible on every Mac. [Acceptance](../4k-post-processing/spec.md).

### P2 — Expand capability and polish

- [ ] **Xbox Console Remote Play.** LAN-only implementation candidate covers account-separated xHome access, associated-console listing and discovery, explicit wake then connect, shared media/input and session cleanup, LAN ICE enforcement, and controller rumble. Automated checks pass; real Series X acceptance remains. See [spec](../xbox-console-remote-play/spec.md) and [validation](../xbox-console-remote-play/validation.md).
- [ ] **Library completeness.** Recently played, metadata/artwork caching, automatic refresh, game details and actionable entitlement errors. Add an Owned collection only with reliable purchase evidence; do not infer ownership from a subscription grant. [Entitlement boundaries](../game-library/entitlements.md).

### Before distribution

- [ ] **Security and packaging.** Formal signing and notarization, reproducible distribution build, and migration from the approved development credential file back to Keychain. Verify changed-build access and safe migration before removing the fallback file. Never broaden Keychain access to all applications. [Tracked credential work](../keychain-access/issues/01-restore-keychain.md).

### Later, not required for this macOS increment

- [ ] **iPhone/iPad.** Reuse the streaming core with platform-specific interface, lifecycle and input integration.
- Multi-controller support remains future work. Frame interpolation is now a P1 roadmap item above.
- Windows, Linux and PlayStation support are outside this project's v1 scope.

## Working rules

- Preserve the native hardware media pipeline while polishing the interface.
- Keep account entitlement, catalog membership and purchase ownership distinct.
- Record tests, live checks and outstanding hardware/manual acceptance separately.
- Before implementing a roadmap item, create or update its feature-local spec/issues under `.scratch/<feature>/`; use the repository triage status conventions for issues.
- Record the implementation commit and validation evidence here when completing an item. This roadmap does not authorize purchases, account changes, credential migration or unattended cloud sessions beyond the user's request.

### Latest native latency experiment — 2026-09-22

Retained 25 ms freshness catch-up within the two-frame queue and accurate actual-presentation accounting; rejected slower display-link/arrival-driven experiments. The subsequent controller-connected verification passed all three foreground HUD pacing gates (~0.22–0.44 skips/s, OUT ~59.6); the user reported the experience was much improved. Actual local display latency remains above the 25 ms mean experiment target. The selectable pacing build subsequently passed 97 tests; Low latency live acceptance and longer sessions remain pending. [Evidence and limitations](../playback-performance/latency-optimization-validation.md).

## Remaining scope after 4K priorities update

Checkbox count: **11 unfinished top-level items**: **10 macOS implementation/research items**, plus **1 deferred iPhone/iPad item**. Controls/settings is accepted. Four current items remain partially delivered (reliability, pacing, monitoring, upscaling). Upscaling was promoted rather than double-counted; interpolation, neural-rendering feasibility and the combined TV profile add three tracked outcomes. Neural-rendering research completion is not the same as a promised production DLSS feature.

Other-controller validation, abrupt power-loss detection delay, rumble and multi-controller support remain follow-ups rather than additional top-level checkbox items. Low latency live performance validation remains pending. Latest committed implementation baseline: `b77f40c`; planning commit: `57fd75f`. The subsequent implementation is recorded in the commit containing this status update, with 124 passing tests, signed-build verification and live evidence.
