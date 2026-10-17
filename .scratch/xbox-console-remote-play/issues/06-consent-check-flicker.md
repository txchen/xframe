# Prevent presentation flicker during selected-pair consent checks

Status: ready-for-agent

The user reports a roughly one-second waiting screen during play, followed by recovery, with audible audio remaining continuous. Live logs at 22:00:46, 22:02:04 and 22:07:50 show exactly one statistics interval of gate revocation. The last transition contains a complete selected LAN pair in `in-progress` with one outstanding request, and the next sample is `succeeded`. ICE does not disconnect. The route classifier currently treats every non-succeeded selected-pair state as missing evidence.

Accept in-progress selected-pair evidence only after the same endpoint completeness, UDP, private-address, non-relay and current subnet checks. Missing evidence and forbidden routes must still revoke immediately. Preserve the active user session while building a separate candidate.

## Primary implementation evidence

WebRTC `Connection::Ping` sets `state_ = IceCandidatePairState::IN_PROGRESS` after sending a probe. An outstanding check is therefore not evidence that the selected route or its endpoints disappeared. See [WebRTC connection.cc](https://webrtc.googlesource.com/src/+/4918ae25f8196623fcfd2e6ca45f5ca08ef66a73/p2p/base/connection.cc).

## Implementation and automated verification

Regression commit 43247aa failed before the fix (three tests, nine expected issues). Commit 398d9dd allows only `succeeded` and `in-progress` for the selected pair, preserving all endpoint and subnet checks. All 178 tests passed. Independent review found no bypass or fail-closed regression. The Developer ID signed candidate `.build/lan-consent-candidate/XFrame.app` built and passed strict signature verification; the active playing session is not restarted. Physical acceptance of this specific flicker repair remains pending until switching builds.
