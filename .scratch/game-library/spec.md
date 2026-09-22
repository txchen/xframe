# Native cloud game library

## Scope

Replace the preview title list with a native, resizable library. Use XStreaming as a source reference, not a React or entitlement implementation to copy. Keep all repository/UI text English.

- Adaptive poster cards and compact list modes. Optional Microsoft public catalog poster/tile, categories and publisher metadata; local placeholders when artwork is missing or fails.
- Case- and diacritic-insensitive multi-word title search; metadata-backed category filter; local favorites filter; natural A-Z/Z-A sort with stable title-ID tie-breaker.
- Bounded client-side pages of 24, 48 or 96 games, previous/next navigation, current page and exact result range. The authenticated catalog is still fetched in full; do not present this as server-side pagination.
- Reset page and selection when search/filter/sort/page size changes. Clamp pages after data/favorite changes. Starting a title requires explicit visible selection. Same-named editions retain separate identities.
- Device-local favorites store title IDs only in UserDefaults. Favorites survive app restarts and account/region changes but never add titles outside the current authenticated catalog or imply ownership/subscription eligibility.
- Explicit initial, loading, empty-results and error/retry states. Preserve region/session ownership constraints, mute/volume, End Session and diagnostic export.
- Public metadata/image requests never carry the streaming bearer token. Initial artwork URLs must be HTTPS on the verified Microsoft image CDN; missing metadata is optional. No extra account authorization or cloud session is needed to test query logic.

## Exclusions

No invented Game Pass/owned/free-to-play labels, release-date sort without dates, account linking, store purchases, controller implementation, artwork scraping, or auto-starting sessions. Favorites are not cloud synced. Catalog metadata failure handling retains the existing whole-load retry behavior; offline browsing is not implemented.

## Verification

Unit/integration checks cover exact page coverage, empty/invalid/page-shrink bounds, filter composition, natural/stable sorting, realistic catalog size, selection invalidation, local favorites persistence and optional metadata hydration/URL validation. Run the full suite repeatedly and build the signed release app without UI automation. Visual layout, save dialog and real library interaction remain explicitly unverified while the display is left asleep.
