# Native Rendering Validation

Environment: Apple Silicon, macOS 27.0 (26A428), Swift 6.4, macOS 27 SDK.

## Verified

- Release compilation and application bundling with the SwiftPM native build engine.
- Local ad-hoc code signature verification and a macOS 27.0 minimum deployment target in the executable.
- Launching the native app and displaying the Metal-rendered static pattern with upright text, circular circles, and all four corner markers.
- A 960 × 540 point window reports a 1920 × 1080 pixel drawable.
- Native window zoom resizes the drawable to 3840 × 2036 pixels; the complete image remains centered with black side bars and correct proportions.
- Native full-screen entry reports a 3840 × 2160 pixel drawable. The settled, focused full-screen capture shows the complete pattern covering the display.
- Exiting full-screen restores the windowed drawable dimensions.
- Quitting through Command-Q exits the process.

## Validation Limits

- Direct border dragging through the UI automation did not resize the window. Resize behavior was exercised through native window zoom instead. A manually dragged tall window remains on the visual checklist.
- Moving between physical displays with different scale factors has not been verified. The implementation refreshes drawable dimensions on backing-property and screen changes.
- No live stream, decode performance, frame pacing, or enhanced upscaling claims are made for this static fixture.

## Build Note

The default Swift 6.4 `swiftbuild` engine failed to initialize with `Unknown error parsing property list` on this Command Line Tools installation. The build script explicitly uses the deprecated but working `native` engine. This workaround should be revisited when updating the toolchain.
