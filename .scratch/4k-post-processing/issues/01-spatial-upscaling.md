# Optional 1080p to 4K MetalFX Spatial scaling

Status: ready-for-agent
Type: task

## Purpose

Deliver the first independently testable increment of the agreed [4K plan](../spec.md): improve 1080p cloud video presentation on the user's 4K display while preserving the working playback baseline.

## Scope

- Read the [Veyra source study](../veyra-nrvideo-research.md) before implementation; verify MetalFX support on the actual M1 and current SDK.
- Add an optional MetalFX Spatial path and an explicit original-scaling bypass. Keep the original path as default until comparison supports changing it; unsupported devices retain normal playback.
- Preserve NV12 color conversion, video range/color, Aspect Fit, Retina backing dimensions, resizing and fullscreen. Bound resource lifetime and allocation across size/settings changes.
- Expose only a simple user-facing original/enhanced choice for this increment.
- Record scaler GPU cost and actual presentation latency separately from decode/network metrics. Compare fixed content with enhancement on/off.

## Acceptance

- Signed build and relevant tests pass; original mode retains current behavior.
- On M1 with 4K output, compare text, menus, foliage, fast pans and compressed content against original scaling; record artifacts and subjective result rather than assuming improvement.
- Compare sustained input/output cadence, frame skips, GPU mean/p95, presentation timing and memory under matched conditions. Do not claim 4K60 feasibility until measured.
- Resizing, fullscreen and repeated on/off changes do not leak surfaces or corrupt frames; audio and input remain functional.
- If the backend is unsupported or cost/quality is unacceptable, document that result and keep bypass available.

## Boundaries

Adjustable sharpening and FSR alternatives follow after the scaler baseline. Frame interpolation, neural rendering and combined profiles are separate tasks. P0 soak/long-outage acceptance remains open and is not silently waived by starting this work.
