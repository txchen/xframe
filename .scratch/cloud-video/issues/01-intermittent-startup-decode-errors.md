# Investigate Intermittent Startup H.264 Bad-Data Errors

Status: needs-info

## Evidence and Remaining Gap

Earlier Fortnite runs produced 20, 49 and 60 recoverable VT bad-data errors before settling into continuous playback. In the 60-error run, all errors occurred after first decoded output, with no WebRTC decoder missingFrames hints. That hint alone is not packet-loss telemetry.

Three later WESTUS2 runs with expanded diagnostics did not reproduce the error, before any NAL preservation fix. Do not attribute those clean runs to a fix. A separate deterministic regression caught discarded SEI/AUD data and was fixed, but causality to the original failures remains unproven.

When failures recur, compare synchronous/asynchronous and IDR error counters, VT configuration count, and inbound-video RTP lost/NACK counters. The new UI provides this numeric evidence without recording media or credentials. A narrow timestamped event trace may be needed to identify ordering; aggregate counters alone cannot prove a causal sequence. Do not silently suppress bad-data errors or treat a clean short run as a stability guarantee.

## Progress

Implemented a bounded in-memory timeline retained after cleanup, visible under Last stream diagnostics. Added a real VT corruption/missing-data test, demonstrating dependent-frame error cascades and recovery at a later IDR. The decoder now skips known-dependent delta pictures after bad data until a recovery IDR; skips are counted separately. The first cause of the original live failures remains unconfirmed. A future failing live timeline, not a clean run or a synthetic corruption test alone, is needed to distinguish it.

## Live reproduction — 2026-09-22

Exports `.build/p0-live/02-forza-mode-switch.json` and `03-forza-input-handoff.json` now capture failures. In the latter, decoder configurations 3 and 4 at 104710 ms and 107064 ms were followed within 1–2 ms by asynchronous delta-picture badData, then keyframe requests and IDR submissions. Both reported lost=0, NACK=0. This localizes failures around configuration changes; it does not prove that network loss is impossible or identify the original cause. Four analogous errors occurred in the preceding mode-switch session.

## Reproduced decoder reset defect

`bash scripts/test.sh --filter decoderCompatibleParameterChangeKeepsReferenceFrames` initially failed with one badData and only 10 of 30 frames decoded (`.build/config-change-red.log`). A valid fixture received an SPS level update at delta frame 10. The old path unconditionally destroyed reference pictures on every SPS/PPS change.

The fix asks VideoToolbox whether the existing session accepts the new format; otherwise it rebuilds and requests/waits for IDR before submitting dependent pictures. On this Mac the level update requires a rebuild. The final test `decoderParameterChangePreservesOrRebuildsReferenceChain` verifies zero decode errors, explicit recovery skips and resumed output at the next IDR. This fixes the reproduced reference-chain defect; equivalence to all historic live badData remains unproven until post-fix live timelines are captured.

Apple API reference: https://developer.apple.com/documentation/videotoolbox/vtdecompressionsessioncanacceptformatdescription(_:formatdescription:)

Post-fix live Forza evidence: `06-forza-outage-recovered.json` contains two decoderFormatUpdated events at 124627 and 127958 ms, VT configuration count 1, zero badData. Previously the comparable loading sequence rebuilt configurations 3/4 and produced two badData events. Compatible reference-chain preservation is now demonstrated live. Historic Fortnite errors may include other causes; no claim that all decode failures are eliminated.
