# Connect a physical controller to cloud playback

Status: needs-info
Type: task

Implement the live increment in ../spec.md. Validate mapping, focus ownership, release safety, transport ordering/retries, bounded queues, disconnect/reconnect, and session teardown. Physical cloud host response is required before marking the roadmap complete or enabling by default.

## Comments

- 2026-09-22: User is connecting an Xbox One Bluetooth controller. Implementation started.
- 2026-09-22: Implementation and signed build completed; 69 tests pass. Physical Xbox Wireless Controller discovered and Palworld main menu reached. Awaiting supervised button/axis/focus/disconnect acceptance; see ../validation.md. Roadmap remains unchecked.
- 2026-09-22: User confirmed Palworld D-pad/left-stick navigation and A/B work normally. In-game and focus/disconnect checks remain in progress.
- Remaining human input: in-game controls, focus release and Bluetooth reconnect results. The active Palworld session is left running for supervised testing.

- 2026-09-22: User confirmed in-game movement/camera, LT/RT, shoulders, stick clicks, Menu/View and held-input focus loss all work without stuck input. Basic gameplay/focus acceptance passed. Remaining needs-info: Bluetooth disconnect/reconnect, full-screen transitions and repeated teardown.
- 2026-09-22: User confirmed reconnect without restarting, fullscreen input and repeated-session controls. Abrupt power-loss delay is tracked separately in 02-abrupt-power-loss-delay.md. The fullscreen session-window defect was fixed and verified through an actual Palworld end/relaunch cycle; all 74 tests pass.
- 2026-09-22: User accepted basic controller functionality. Verified device coverage is Xbox One Bluetooth only; PS4 / DualShock 4 and all other models are untested. Basic Xbox One integration is marked complete in the roadmap; abrupt power-loss delay remains a separate known limitation.
