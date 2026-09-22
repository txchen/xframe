# Native library validation

Date: 2026-09-21. No application launch, window automation, authenticated cloud catalog fetch or game session was performed for this increment.

## Automated evidence

`bash scripts/check-headless.sh 3` passed 49 tests in each of three serial rounds (147 test executions), followed by the signed release build. Test durations were 4.119, 4.221 and 4.286 seconds. Logs are retained in ignored `.build/headless-checks/run.Z8qt1E/`.

New library coverage includes:

- Complete, non-overlapping page coverage for 101 titles; a 2,671-title catalog with a 79-title final page at page size 96.
- Case/diacritic-insensitive multi-term search composed with category and favorites filters.
- Natural ascending/descending ordering and stable title-ID ordering for identical display names.
- Empty results, negative/oversized page indices, unsupported page sizes and result sets shrinking below the requested page.
- Local favorites persistence using isolated test preference suites, with no writes to real favorite preferences.
- Clearing hidden selection on query changes and removing the last visible favorite; preserving favorites but clearing catalog/query on account/region reset.
- Optional product metadata hydration, duplicate title-ID removal, missing-product fallback, category deduplication and Microsoft HTTPS image URL validation.

Existing authentication, cleanup, private credential storage, receive-only audio, JSON diagnostic export and actual VideoToolbox hardware-decoder regression tests also passed. No microphone, controller or human listening is required for these tests.

## Reference and live-data scope

Research used the pinned XStreaming sources documented in `reference.md`. A background research task verified the public Fortnite product metadata shape with an unauthenticated Microsoft catalog request. That read-only metadata check does not validate the full real account catalog or runtime artwork loading in XFrame.

## Pending UI acceptance

The SwiftUI grid/list, loading/empty states, favorite buttons, category/search controls, pagination, resizing, keyboard focus and JSON save dialog compiled but were not visually inspected or clicked. The signed app bundle was built without restarting the running app, intentionally avoiding waking the display. On the next supervised run, reopen the updated app, load the real catalog, check the controls at minimum and larger window sizes, and verify selection/launch remains explicit. Controller support is still absent.

The shell and hardware tests continued successfully while the user left the display unattended. Physical panel power state was not independently verified; no system power setting was changed and no overnight-duration stability claim is made.
