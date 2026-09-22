# Playback window visibility

The native renderer may initialize at launch, but its window must remain hidden while browsing. No decode/render stack replacement is required.

- Cloud video attachment reveals the renderer; detachment hides it and brings back the library, including any pending cleanup or retry status.
- Opening/replaying a local file or explicitly requesting the test pattern reveals the renderer.
- The local-file picker belongs to the library window, so canceling does not expose an idle renderer.
- Closing local playback stops decoding, clears the renderer source, and returns to the library.
- Closing cloud playback retains the existing asynchronous session cleanup guards.

Keep the previous account-window integration changes intact.

## Validation

- All 59 tests passed; signed production build succeeded.
- Live startup opened the library; Command-0 explicitly revealed the test pattern. Closing that window returned to the library.
- The file picker opened as a sheet from the library; canceling returned to browsing without revealing the renderer.
- Reloaded the catalog successfully. No cloud game was launched in this validation pass; live cloud teardown and fullscreen transitions remain unverified for this change.
