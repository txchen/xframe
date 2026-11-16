The library now has larger game titles and cards, Standard/Large sizing, a simplified sidebar, and inline quality, pacing and language settings. Audio controls stay in the player; microphone hints and the sidebar promotional text are removed.

Play opens the player immediately with a cancellable connection screen. The loading screen clears after the first real video frame completes GPU rendering, without showing a test pattern. Remote service allocation time still varies.

The benchmark now runs only selected workloads and resolutions, with Quick (15 measured samples) and Standard (55) modes. Missing selected FG and Small NR weights download automatically from the pinned v0.1.2 GitHub assets, with checksum verification and local caching. Manual imports and JSON export remain available. These tests do not enable live frame generation or NR.

Detailed HUD now includes GPU queue and Display wait P95 timings.

Validation: 209 tests passed, separate native Metal startup-window test passed, both model downloads verified, and selected VT/FG/NR quick runs executed on M1. Apple signing/notarization and public package verification are part of release delivery. Real Xbox startup, M5 and large-screen acceptance remain user checks.
