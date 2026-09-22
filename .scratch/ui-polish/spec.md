# Cloud library visual refinement

## Direction

Use a restrained dark library surface so colorful game artwork leads the hierarchy. A persistent collection sidebar separates navigation from search/filter controls. Larger 2:3 posters replace letterboxed thumbnail panels. Reserve a pale lime accent for active navigation, selection and the primary play action; secondary controls use neutral tones. Maintain native controls, accessible names, explicit disabled launch state and existing session ownership rules.

The library window opts into dark appearance without changing macOS appearance or the native video renderer. Keep the AppKit window/MTKView playback surface and SwiftUI library. No speculative decoder rewrite or claimed performance gain is part of this visual change. See `stack-research.md` for the code audit and primary-source findings.

## Verification

Run existing logic/media regressions and release build. Inspect the real authenticated catalog, search results, grid/list layouts, collection selection, disabled/enabled play state and window sizing without starting a game. Preserve game IDs, favorites storage, pagination, region handling and audio controls. Record visual evidence separately from runtime performance measurements.
