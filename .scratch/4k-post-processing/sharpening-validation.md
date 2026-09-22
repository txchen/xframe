# Adjustable sharpening validation

Date: 2026-09-22

## Implementation

MetalFX Spatial now has Off / Low / Medium / High extra-sharpening presets in the in-picture panel. Default Off uses the existing composition pipeline unchanged. Selection applies immediately and persists under `XFrame.MetalFXSharpening`; choosing another scaling mode preserves it but does not apply it. The panel explains that sharpening only runs while MetalFX is effective, including when a selected MetalFX mode temporarily falls back.

The filter is XFrame post-processing, not a MetalFX descriptor setting. A symmetric four-neighbor luminance unsharp mask is fused into final composition, with strengths 0 / 0.25 / 0.5 / 0.85. Detail is limited to ±0.08 before strength multiplication; output is clamped to SDR range with original alpha. No extra intermediate texture, pass or frame buffering is introduced. Color processing and upscaler input/output formats are unchanged.

## Automated evidence

- Full suite: 144 tests pass (`.build/sharpening-tests.log`).
- Final focused suite: 3 sharpening tests pass (`.build/sharpening-focused.log`). Tests verify default/persisted selection, mouse/keyboard/synthetic-controller navigation, retained selection across scaling modes, actual GPU flat-field color preservation, zero-strength equivalence, monotonic soft-edge response and bounded per-channel changes.
- Offscreen 3840×2160 input/output final-composition cost on Apple M1, 20 measured frames after 3 warmups: Off mean 0.709 ms / p95 0.730 ms; High mean 1.051 ms / p95 1.127 ms. This isolated synthetic measurement excludes MetalFX itself, decode, actual display and gameplay. It is not an FPS or end-to-end latency acceptance claim.

## Build and native UI verification

- Signed release build and deep/strict signature verification passed (`.build/sharpening-build.log`).
- Restarted the app after observing that the previous cloud session had ended; no new cloud session was started.
- Native test-pattern UI: selected MetalFX, verified Off/Low/Medium/High controls, selected Low by mouse, Medium by keyboard, and High by mouse with visible selection/checkmark updates.
- Entered native 4K fullscreen; effective scaling reported 1920×1080 → 3840×2160 and the panel remained open. Selected High and restored Off, then closed the test-pattern window and returned to the library.
- Saved preference readback confirmed `off`. MetalFX Spatial is selected for the user's comparison. Actual physical-controller navigation and cloud-video visual quality were not claimed from these checks.

## User acceptance — 2026-09-22

The user reported “可以 可以看出一点效果的. 验收通过.” after testing the feature: the sharpening effect is visible and the increment is accepted. No preferred preset was specified, so the first-use default remains Off. This is practical user acceptance, not a per-scenario benchmark or proof of zero playback cost.

