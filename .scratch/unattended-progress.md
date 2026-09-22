# Unattended progress and next supervised checks

Completed without UI automation, cloud sessions, microphone capture, controller hardware or power-setting changes:

1. Bounded local playback timing distributions and stream report schema 2; skip idle drawable acquisition while retaining pending frames and counting replacements correctly.
2. Real VideoToolbox fixture regressions, repeated cancellation/source deallocation and isolated RSS observation. Real offscreen Metal NV12 import and BT.601/709 shader output verification.
3. Cached catalog projections, page-local keyboard-selection model and explicit card artwork reload action.
4. Immutable normalized controller snapshots and a pure binary encoder matching pinned XStreaming golden bytes. Live sending and GameController discovery remain disabled.

Final verification: 59 tests passed in three rounds and signed release build. The prior 58-test optimized suite also passed before the final skipped-frame counter regression was added. Detailed evidence and boundaries: `playback-performance/validation.md`, `game-library/unattended-validation.md`, `controller-input/spec.md`.

## Next supervised checks

- Relaunch the updated app; validate video presentation, resize redraw and timing counters. Offscreen GPU success does not establish compositor/display timing.
- Check keyboard focus/arrow navigation and a real artwork failure/retry. Neither action should start a game.
- Connect the physical controller and implement/verify the GameController adapter, one-time Y conversion, neutral release on focus loss/disconnect, input handshake/backpressure and cleanup before enabling live reports. Check rumble separately; do not copy the reference parser's bounds bug.
- Keep real A/V synchronization and controller-to-photon latency as separate acceptance items. No measured networking or input-latency claim is made from local timing distributions.

The app bundle is built but was not relaunched while the user was away. No push or remote publication was performed.
