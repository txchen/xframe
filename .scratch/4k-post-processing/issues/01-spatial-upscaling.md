# Optional 1080p to 4K MetalFX Spatial scaling

Status: needs-info
Type: task
Implementation: complete
Acceptance: representative gameplay quality and physical A/V/controller confirmation pending

## Purpose

Deliver the first independently testable increment of the agreed [4K plan](../spec.md): improve 1080p cloud video presentation on the user's 4K display while preserving the working playback baseline.

## Scope

- Read the [Veyra source study](../veyra-nrvideo-research.md) before implementation; verify MetalFX support on the actual M1 and current SDK.
- Add an optional MetalFX Spatial path and an explicit original-scaling bypass. Keep the original path as default until comparison supports changing it; unsupported devices retain normal playback.
- Preserve NV12 color conversion, video range/color, Aspect Fit, Retina backing dimensions, resizing and fullscreen. Bound resource lifetime and allocation across size/settings changes.
- Expose three user-facing scaling modes: Original, Integer Scaling, and MetalFX Spatial.
- Record scaler GPU cost and actual presentation latency separately from decode/network metrics. Compare fixed content with enhancement on/off.

## Agreed design decisions

- When MetalFX is unsupported or enhancement initialization fails, fall back to original scaling, retain the user's preference, and show the effective mode and fallback reason in the HUD without an interrupting dialog.
- Use one shared scaling-mode preference for cloud video, local video, and the static test pattern, allowing repeatable comparisons with fixed local content.
- Persist the selected scaling mode across application restarts, with Original as the first-launch default. Temporary bypass does not clear the selected preference. Show the effective mode and bypass reason in the HUD.
- For MetalFX Spatial, output extent follows the Aspect Fit picture area in actual backing pixels, excluding black bars. A 3840×2160 fullscreen picture targets 3840×2160; smaller windows use a smaller target. When the picture area is no larger than the source, use original scaling; automatically resume MetalFX when upscaling is needed again. Do not always upscale to a fixed 4K intermediate before fitting the window.
- For Integer Scaling, the initial acceptance case is a 1920×1080 source displayed fullscreen at 3840×2160 using 2× nearest-neighbor scaling. In windowed mode, temporarily use Original Aspect Fit; automatically restore 2× nearest-neighbor when returning to that fullscreen configuration. If fullscreen dimensions do not allow an exact uniform integer enlargement of the fitted picture, use Original Aspect Fit instead of forcing a smaller integer-sized picture with extra borders. Determine eligibility from actual source and backing pixels, not the monitor's marketed resolution.

## Acceptance

- Signed build and relevant tests pass; original mode retains current behavior.
- On M1 with 4K output, compare text, menus, foliage, fast pans and compressed content against original scaling; record artifacts and subjective result rather than assuming improvement.
- Compare sustained input/output cadence, frame skips, GPU mean/p95, presentation timing and memory under matched conditions. Do not claim 4K60 feasibility until measured.
- Resizing, fullscreen and repeated on/off changes do not leak surfaces or corrupt frames; audio and input remain functional.
- Verify Integer Scaling produces aligned 2×2 pixel replication for the 1080p-to-4K case, bypasses in windowed mode, and resumes on fullscreen re-entry without changing the persisted selection. Compare all three modes on identical content.
- If the backend is unsupported or cost/quality is unacceptable, document that result and keep bypass available.

## Boundaries

Adjustable sharpening and FSR alternatives follow after the scaler baseline. Frame interpolation, neural rendering and combined profiles are separate tasks. P0 soak/long-outage acceptance remains open and is not silently waived by starting this work.

## Comments

- 2026-09-22: User gameplay feedback: MetalFX substantially improves perceived quality; Integer Scaling is sharp, especially text. Slight motion ghosting appears only with MetalFX in the user's same-scene comparison. User subsequently accepted this as a perceived spatial-scaling tradeoff, rather than a bug; retain the [quality observation](02-motion-ghosting.md) without blocking acceptance on it.

- 2026-09-22: During grill-with-docs, the user selected output sizing that follows the actual picture area (option A). Remaining design questions are being resolved before implementation.
- 2026-09-22: The user selected a persistent enhancement preference (option A), initially off, with automatic resumption after a temporary size-based bypass.
- 2026-09-22: The user selected all three existing picture sources (option A): cloud video, local video, and static test pattern.
- 2026-09-22: The user selected automatic fallback with a HUD reason and no dialog (option A). The user also proposed integer scaling; its inclusion and behavior outside exact integer-sized output remain under discussion.
- 2026-09-22: The user identified 1080p at fullscreen 4K as the main integer-scaling use case, with pixel-art games as another potential comparison case. Whether to retain strict integer scaling or temporarily use original Aspect Fit outside fullscreen is still to be decided; no visual-quality improvement is assumed.
- 2026-09-22: The user confirmed option A for Integer Scaling: temporarily use Original Aspect Fit in a window and automatically restore 2× nearest-neighbor for 1080p on fullscreen 4K. This resolves the preceding open question and expands the selector to three modes.

- 2026-09-22: User confirmed the full design and authorized implementation. Delivered all three modes with live switching, persistence, explicit bypass status, GPU scaler-span timing and schema-8 diagnostics. 128 tests, signed build, Metal API validation and a 249-second Palworld session passed their documented checks. Representative fast-motion/subjective quality and physical A/V/controller acceptance remain open; see [validation](../spatial-validation.md).
