# UI polish validation

2026-09-21: the 49-test suite passed after the visual refinement (4.146 seconds). The final signed release build passed after the compact grid sizing and Automatic region-label adjustment. Playback/decoder implementation was not changed.

The app was restarted through native UI automation, restored the existing account without a password prompt, and loaded 2,671 real titles. The first dark layout exposed a window-width issue on the current display; the minimum width was reduced from 1,080 to 900 points, navigation tightened, and controls compacted. A second screenshot confirmed the entire window and footer were visible. Poster minimum width was then reduced to 150 points to fit four complete cards across the minimum-width catalog, retaining a 2:3 artwork area.

Final screenshot checks confirmed four complete poster cards at minimum width, the Forza three-result search, selected poster/play-button state and dark list layout. The list received an explicit selected-row background after inspection so its active title remains visible outside keyboard focus.

No cloud game was started, no account linkage performed and no system appearance/power setting changed. Dark appearance applies to the library window only. The performance review is a source audit, not CPU/GPU/latency benchmarking; see `stack-research.md` for verified facts, limitations and follow-up candidates.
