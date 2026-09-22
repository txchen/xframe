# Controller input validation — 2026-09-22

## Accepted device coverage

User acceptance on 2026-09-22: basic controller functionality is working.

| Controller | Test status |
| --- | --- |
| Xbox One, Bluetooth | Tested and accepted in Palworld: basic controls, focus release, reconnect, fullscreen and repeated-session input |
| PlayStation 4 / DualShock 4 | Not tested |
| Other controller models | Not tested |

Do not extend Xbox One results to other models. Abrupt battery-removal release delay remains a known limitation; rumble is not implemented. Implementation is in the current working tree and has not been committed.

## Automated and build evidence

- `bash scripts/test.sh`: 69 tests passed, including five new scheduler/adapter checks and the four existing packet checks. Log: `.build/controller-tests.log`.
- New checks exercise rejected-send retries and committed sequence numbers, short press/release order, focus-loss neutral priority, neutral rearming, bounded overflow, analog coalescing and trigger edges, and native GameController synthetic-profile button/trigger/Y mapping.
- The first synthetic-profile test attempted to set D-pad direction buttons independently; Apple's synthetic profile derives those buttons from the D-pad axes. Corrected the test to set the axes; all directions passed. No physical-device claim is based on this synthetic profile.
- `bash scripts/build-app.sh`: release build and development signing/strict signature verification passed. Log: `.build/controller-build.log`.
- `git diff --check` passed.

## Supervised hardware acceptance

The user reports the Xbox One Bluetooth controller is connected and selected Palworld for testing. Launched the signed development build, enabled View > Enable Controller Input, found Palworld under Playable games, and started its cloud session.

Confirmed in the running app: `Xbox Wireless Controller` discovery, input readiness and increasing sent-packet sequence. Palworld reached its main menu with hardware-decoded 1920×1080 H.264 video; no decode errors were observed in this startup sample. This establishes discovery and transport activity, not button acceptance.

The user confirmed normal Palworld main-menu response to D-pad/left-stick navigation and A enter/B back. This is actual physical-controller-to-cloud-host acceptance for those controls.

The user subsequently confirmed normal in-game movement, right-stick camera control, LT/RT, shoulder buttons, stick clicks and Menu/View. Holding movement while switching away, releasing controls, and returning did not leave movement stuck. These results are user-observed physical Xbox One Bluetooth / Palworld acceptance, separate from the automated checks. Basic controls and focus-loss release have passed.

Bluetooth reconnect, full-screen transitions and repeated-session input subsequently passed, as recorded below. Local send success alone is not host acknowledgement. Rumble remains out of scope.

## References

- Pinned XStreaming `Control.ts` was re-read from revision `383e19d324f2d3029d1c304752f4d38a9360bb95`; reset/add index zero uses the reference 500 ms delay.
- Apple's GameController SDK headers and [extended gamepad documentation](https://developer.apple.com/documentation/gamecontroller/gcextendedgamepad) informed mapping and synthetic-profile tests. Background input monitoring stays at the macOS default (off); explicit playback-window ownership further restricts sending.

## Follow-up hardware feedback

The user confirmed fullscreen enter/exit preserves controller operation and that reconnecting after battery removal restores controls without restarting the game. Abrupt battery removal while moving left the character moving for approximately 2–3 seconds before stopping. This is recorded as observed delay, not a claim of immediate release or a proven Bluetooth-stack timeout. The current app detects loss by checking GameController's device list each input tick; layer-by-layer timing still needs a correlated hardware trace.

Repeated cloud sessions retained working controls. The user found a separate playback-window lifecycle problem when ending a fullscreen session from the library; tracked in `../unified-account/issues/01-fullscreen-session-restart.md`.

A coordinated read-only disconnect probe captured last non-neutral callback at 10.805 s, OS disconnect + neutral at 15.853 s, enumeration removal at 15.861 s and reconnect at 25.716 s. The battery-removal instant was not timestamped; the 5.048 s gap is not exact power-loss latency. See `issues/02-abrupt-power-loss-delay.md`. The probe was stopped after capturing the complete cycle.

Playback lifecycle fix verification: all 74 tests and signed build pass; Palworld fullscreen → library End Session → Session ended → relaunch produced normal windowed playback. Remaining boundary: precise abrupt-power-loss latency is not guaranteed. Rumble remains unimplemented.
