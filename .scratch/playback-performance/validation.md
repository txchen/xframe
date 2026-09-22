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
