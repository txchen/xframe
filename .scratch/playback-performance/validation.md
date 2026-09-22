# Unattended validation record

2026-09-21. No app launch, UI automation, microphone, controller or cloud session was used.

## Repeated suite

`bash scripts/check-headless.sh 10` passed 56 tests in each round (560 test executions), followed by signed release build. Logs: `.build/headless-checks/run.hzQEtX/`. This includes 120 full-queue cancellation cycles, successful source deallocation checks, clean decode/B-frame scheduling, corrupted/missing H.264 recovery, credential/session cleanup, query behavior and offline input packet tests. This is bounded regression repetition, not an overnight soak.

The 720-frame local fixture recorded successful hardware-decode callback counts of 720. Across the ten rounds, latest-256 mean was 3.262–3.362 ms and p95 was 3.871–3.908 ms. Other tests run concurrently inside a round, so these are loaded regression baselines, not an isolated decoder speed ranking or a before/after improvement claim.

## Resource observation

An isolated `bash scripts/test.sh --filter repeatedLocalCancellationReleasesSourceAndQueue` completed 12 cycles in 0.642 seconds. After each stopped source was deallocated, process RSS in KiB was:

`23440, 24592, 25632, 26704, 22608, 23472, 24304, 25152, 22624, 23456, 24304, 25104`

RSS fell during the sample rather than increasing monotonically. This verifies those source lifetimes and a short resource trend; it does not prove every framework allocation is leak-free.

## Boundaries

After adding isolated RSS reporting and multi-title keyboard/cache invalidation coverage, final verification passed 57 tests in each of three rounds (171 additional test executions) and a signed release build. Logs: `.build/headless-checks/run.aSG4eP/`. Whole-suite RSS is higher and changes while other video tests allocate concurrently; use the isolated sample above rather than attributing that process-wide growth to the cancellation loop.

- Unit checks verify bounded distributions, percentile calculation, missing/nonfinite input rejection, terminal freeze and pending-frame retry/idle-draw decisions.
- Real hardware fixtures verify decode timing collection without claiming presentation. GPU and presentation values remain n/a in these headless tests.
- Renderer callback timing and changed drawable-acquisition order compile, but visible Metal presentation/resize and actual GPU/presentation distributions still require a supervised runtime check.
- No lowering of render frequency, buffer-count tuning or compressed-byte rewrite was performed without measurements.

## Offscreen GPU execution

`metalImportsNV12AndConvertsVideoRangeOnTheGPU` runs the production `VideoTextures` import and the actual repository Metal shader against a synthetic IOSurface NV12 fixture, without a window or drawable. Both BT.601 and BT.709 cases passed. GPU readback verifies limited-range black/white and a non-neutral chroma patch (within one output code value). The two tiny 24 x 8 passes reported 0.064 and 0.073 ms GPU execution in the initial isolated run; these are correctness-test timings, not a 1080p streaming performance claim.

CPU pixel writes and readback, and synchronous GPU waiting, exist only in the test. Production decoded pixels still travel through the native surface/texture path. This closes the offscreen shader/import execution gap, not the pending visible drawable/presentation acceptance gap.

## Optimized configuration

`bash scripts/test.sh -c release` passed all 58 tests in 3.891 seconds after compilation. The successful 720-frame decode recorded latest-256 mean 2.502 ms and p95 2.583 ms. Build configuration and concurrent scheduling differ from the Debug baselines above; do not interpret this comparison as the gain from moving drawable acquisition.

## Final state

Renderer pending-frame replacement now increments skipped-frame counters, including when a drawable was unavailable; late callbacks after stop do not change them. An intermediate test build exposed a Swift Testing macro restriction on mutating methods inside `#expect`; the test now evaluates the mutation before asserting the result. No runtime failure was hidden.

Final `bash scripts/check-headless.sh 3` passed all 59 tests in each round (177 test executions) and the signed release build. Logs: `.build/headless-checks/run.MBhWLe/`. The application was not relaunched, so the running UI is intentionally unchanged until the next supervised restart.
