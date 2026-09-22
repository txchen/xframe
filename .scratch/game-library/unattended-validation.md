# Unattended library follow-up

Derived pages and categories are now cached in the observable library model and rebuilt on catalog/query/favorite changes instead of on every view read. Tests verify that 100 page/category/selection reads, selection movement, audio changes and artwork retry revisions do not trigger re-filtering/sorting. Page and search changes still invalidate correctly and clear stale selection.

Catalog arrow commands move selection in stable page order without starting a game. The model handles absent selection, empty results and page boundaries. The grid card context menu provides an explicit Reload Artwork action by restarting its AsyncImage identity; there is no automatic retry loop. Artwork revision state is discarded with the catalog. This does not claim a custom image cache or server-cache bypass.

Pure model/invalidation checks pass in the headless suite. Native arrow-key focus behavior and actual failed-image retry need supervised UI acceptance; neither was simulated with a hidden cloud session or a claim of visual verification.

Final verification: 57 tests passed in each of three serial rounds plus release build (`.build/headless-checks/run.aSG4eP/`). A 30-title test covers moving across a page, clamping at its end, page changes, narrowed search and empty results without any session launch.
