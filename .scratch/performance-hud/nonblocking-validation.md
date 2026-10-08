# HUD isolation / layout validation

## Automated checks

- `bash scripts/test.sh`: **167 tests passed**, including five new HUD tests. Full log: `.build/hud-isolation-tests.log`.
- `bash scripts/build-app.sh`: release build and signed app verification passed. Log: `.build/hud-isolation-build.log`. Output: `.build/XFrame.app`.
- `git diff --check`: clean.
- Visually inspected generated offscreen AppKit previews: `.build/hud-compact-preview.png` and `.build/hud-detailed-preview.png`. They show aligned columns, correct section hierarchy, graph and footer, with no clipping at their intrinsic sizes. These are deterministic fixtures, not live performance observations.

## New regressions

- A collector blocked on a worker cannot block main-actor test progress or independent media operations. Stopping it suppresses its late result; restarting delivers a fresh result.
- Concurrent timing writes/snapshots preserve count and valid distributions.
- History is limited to 30 seconds / 64 samples, rejects out-of-order timestamps and removes expired history without fabricating unavailable FPS.
- Unit labels and unavailable values remain explicit; detailed has more metrics, hidden has no rows.
- Compact/Detailed render successfully and remain click-through; Hidden hides the view.

## Remaining acceptance

No live stream was started and no existing app was restarted. Current running processes do not automatically use the rebuilt binary. Need real Hidden/Compact/Detailed paired frame-interval/skip-rate/latency comparison, UI menu/keyboard switching, narrow-window/fullscreen layout, and long-session acceptance. Synthetic blocked-collector tests establish task isolation, not guaranteed display deadlines. Rendering still runs on MainActor; the separate render-thread prototype remains future work. Do not claim zero diagnostic overhead or measured performance improvement from these checks alone.
