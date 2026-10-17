# Diagnose Series X streaming interruption

Status: ready-for-agent

Two real LAN sessions displayed video and then stopped receiving frames. The user confirmed working sound and physical controller input before interruption. Existing logs show selected-path evidence becomes missing after the last frame, followed by the 15-second media watchdog. The initiating cause is unknown. Preserve LAN admission while adding privacy-safe diagnostics and reproduce before changing behavior.

Acceptance requires a sustained live session beyond both observed failure intervals, with the mechanism identified and any fix independently reviewed. See [live validation](../live-validation-2026-10-16.md).

## Confirmed mechanism

Instrumented session on 2026-10-16 revoked the gate at 21:43:42 because the selected candidate pair briefly reported `in-progress`. It returned to `succeeded` at 21:43:43. STUN counters and API heartbeat continued successfully, but the video watchdog ended the session at 21:43:57. The UI hiding callback calls `MetalRenderer.play(nil)`, which stops its previous `VideoSource`; `LiveVideo.stop()` is permanent. Restoring the same source cannot resume frame delivery. Temporary presentation revocation must not end the session-owned media source.

## Separate transport loss after lifetime repair

The fixed application streamed from 21:47:53 through approximately 21:52:06. Consent responses then stopped at 104 while requests continued past 343, followed by ICE disconnected and the frame watchdog. The macOS networkprivacy session refreshed its application UUID cache at 21:52:05; CoreSpotlight then rejected the ad-hoc app because a Developer ID app on the machine claims the same bundle ID. This is evidence for an application identity conflict hypothesis, not yet proof of the network-loss cause. A build using the already-established project Developer ID identity is under test.

## Resolution and scope

The presentation-lifetime defect is fixed in c4b9ed7. The new renderer regression failed before the change and all 175 tests pass afterward. A Developer ID signed run revoked LAN verification at 21:58:26, restored it at 21:58:27, and continued displaying live video beyond the old timeout, through at least 21:59:38 (about five minutes since connection). Keep the signing/cache relationship recorded as a hypothesis; this observation is not proof that every genuine ICE loss is fixed. The accepted diagnostic app remains running for continued testing.
