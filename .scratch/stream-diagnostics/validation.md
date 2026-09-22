# Headless verification

2026-09-21: `bash scripts/check-headless.sh 3` passed all 41 tests in each of three serial rounds (123 test executions), followed by the signed release build. Logs: `.build/headless-checks/run.j4EKCl/`. No application launch, UI automation, cloud session or power-setting change was involved. This is a short regression repetition, not an overnight soak.

Coverage includes explicit JSON key allowlist, exclusion of arbitrary sensitive error text, absent/nonfinite metrics, latest-128 event limit, immutable terminal duration/counters, retained decoder failure outcome and file round-trip. Export is opt-in through Cloud Games after local stream teardown. The native save dialog has not been visually exercised; display-off UI acceptance is deliberately deferred.

Shell execution continued normally after the user's display-sleep request. Power assertions initially showed a pending display-off delay; the machine's display driver did not expose a readable current power state. Therefore physical display-off state was not independently confirmed, and no UI command was used to wake it.
