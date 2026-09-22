# Investigate Intermittent Startup H.264 Bad-Data Errors

Status: needs-info

## Evidence and Remaining Gap

Earlier Fortnite runs produced 20, 49 and 60 recoverable VT bad-data errors before settling into continuous playback. In the 60-error run, all errors occurred after first decoded output, with no WebRTC decoder missingFrames hints. That hint alone is not packet-loss telemetry.

Three later WESTUS2 runs with expanded diagnostics did not reproduce the error, before any NAL preservation fix. Do not attribute those clean runs to a fix. A separate deterministic regression caught discarded SEI/AUD data and was fixed, but causality to the original failures remains unproven.

When failures recur, compare synchronous/asynchronous and IDR error counters, VT configuration count, and inbound-video RTP lost/NACK counters. The new UI provides this numeric evidence without recording media or credentials. A narrow timestamped event trace may be needed to identify ordering; aggregate counters alone cannot prove a causal sequence. Do not silently suppress bad-data errors or treat a clean short run as a stability guarantee.

## Progress

Implemented a bounded in-memory timeline retained after cleanup, visible under Last stream diagnostics. Added a real VT corruption/missing-data test, demonstrating dependent-frame error cascades and recovery at a later IDR. The decoder now skips known-dependent delta pictures after bad data until a recovery IDR; skips are counted separately. The first cause of the original live failures remains unconfirmed. A future failing live timeline, not a clean run or a synthetic corruption test alone, is needed to distinguish it.
