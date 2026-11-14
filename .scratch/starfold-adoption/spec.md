# Starfold adoption

- [x] Frame: implement token refresh, release barrier, signaling robustness and polling, optional adaptive pacing. Preserve LAN verification, cleanup acknowledgement and actual presentation metrics. Defer conditional product expansions (PiP, multi-account, HDR, custom audio).
- [x] Fan out: isolated worktrees for authentication and input/pacing; signaling in primary checkout.
- [x] Aggregate: review patches, integrate and run tests/build.
- [x] Report: concrete results and real-device gaps.

## Implementation decisions

- Authentication retries only explicit 401 once. 403 and ambiguous transport/server failures are not replayed. Account refresh coalesces concurrent requests and checks generation before persisting or applying results.
- Physical controller controls held through settings/focus transitions must individually release. The neutral arming sample tolerates a small analog rest zone and sends neutral.
- Signaling accepts object/string response envelopes, surfaces fixed failure advice, never arbitrary host response text. Polling uses a monotonic 30-second admission deadline with 100/250/500 ms intervals; an in-flight HTTP request remains subject to its own URLSession timeout.
- Adaptive smoothing is opt-in, receiver-relative RTP scheduling, at most four queued frames and 4–40 ms target buffering. Actual presentation measurements retain their existing meaning. No claimed latency improvement without real-device A/B.

## Device acceptance remaining

- Hold a face button/stick through opening and closing playback settings and switching window focus; ensure only a fresh post-release action reaches the game.
- Play a LAN session with existing Balanced default and verify controls, rumble and cleanup.
- Compare Balanced and Adaptive smoothing on the same scene/network conditions; inspect frame intervals and interaction responsiveness, not only average FPS.
- Verify real service token expiration recovery. Offline HTTP simulations establish request/state behavior only.

## Validation

- Full merged suite: `bash scripts/test.sh` — 203 tests passed. Log: `/tmp/xframe-adoption-full-tests.log`.
- `git diff --check` passed.
- Implementations are original adaptations of the research findings; no Starfold source copied.
- Final signaling hardening: 5 targeted tests passed after mapping malformed outer JSON to a fixed error.
- Release app built and `codesign --verify --deep --strict` passed: `.build/starfold-adoption/XFrame.app`. Build log: `/tmp/xframe-adoption-build.log`. No installation, launch or real-device acceptance performed.
