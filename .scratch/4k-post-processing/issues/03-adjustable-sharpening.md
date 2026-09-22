# Adjustable MetalFX sharpening

Completion: accepted by the user on 2026-09-22
Implementation: complete

## Scope

User requested adjustable sharpening to compare levels after discussion of the current MetalFX Spatial configuration.

- Add Off / Low / Medium / High to in-picture settings when MetalFX Spatial is selected. Default Off preserves the current output.
- Apply instantly with mouse, keyboard and existing controller navigation; persist the choice across launches and scaling-mode changes.
- Apply an additional restrained spatial sharpening filter only to effective MetalFX output, after upscaling. Original, Integer Scaling and MetalFX fallback remain unchanged.
- Fuse filtering into final composition, avoiding another texture or queued frame. Preserve SDR color, alpha, Aspect Fit and black bars. These presets are XFrame post-processing, not MetalFX API quality levels.
- Verify GPU output on flat colors and soft edges, preset ordering, Off equivalence, navigation and persistence; record hardware cost separately from actual gameplay acceptance.

## Acceptance

Automated checks and a signed build are required. User comparison of visual quality and live playback cost remains the final preference/acceptance step; do not claim added source detail or improved frame rate.

## Evidence

See [validation](../sharpening-validation.md) for GPU correctness and cost measurements.

## Comments

2026-09-22: The user reported a visible sharpening effect and explicitly passed acceptance. No preferred strength was specified.
