# Native Rendering First Slice

Scope: Approved by the user on 2026-09-20.

## Objective

Open a native macOS window that correctly displays a generated static test pattern through Metal. This is the first small increment toward the streaming client's native video presentation pipeline.

## Confirmed Scope

- Support and validate Apple Silicon Macs for this first slice.
- Require macOS 27 or later. Earlier macOS releases are outside the supported scope because they are not available for validation.
- Display a static test pattern with a grid, circles, color patches, and edge markers.
- Generate the test pattern at a fixed source resolution of 1920 × 1080 pixels and display it as a Metal texture.
- Keep the source dimensions fixed when resizing the window; scale its presentation to fit the drawable.
- Preserve the complete image and its aspect ratio using Aspect Fit.
- Fill unused display space with black bars.
- Preserve correct proportions and visibility when resizing the window.
- Use backing pixel dimensions for Retina rendering.
- Support freely resizing the window and entering or leaving native macOS full-screen mode.
- Update drawable dimensions when moving the window between displays with different backing scales.

## Acceptance Criteria

- Opening the application displays the test pattern in a native macOS window.
- Circles remain circular and the grid remains undistorted as the window changes shape.
- All source edge markers remain visible.
- Unused space is black.
- Rendering uses the drawable's backing pixel dimensions rather than treating logical points as pixels.
- The source texture remains 1920 × 1080 pixels across window sizes.
- Entering and leaving native full-screen mode preserves Aspect Fit and the complete test pattern.
- Moving between displays updates the backing pixel dimensions and preserves correct presentation. Physical multi-display validation requires an available external display; report it as unverified if unavailable.

## Deferred Work

- Intel Mac support and validation.
- Compatibility with macOS releases earlier than 27.
- Animated test content and video decoding.
- Microsoft/Xbox authentication and live streaming connections.
- MetalFX upscaling and assessment of enhanced image quality when enlarging the 1080p source.

## Implementation Gate

The user confirmed the complete first-slice scope and authorized implementation on 2026-09-20.
