# Full-row Games and Favorites hit targets

Status: ready-for-human
Type: task

## Problem and change

User reported small click targets. On the signed app, clicking the blank right-hand area of Favorites at screenshot coordinate (100, 151) left the Games selection unchanged; invoking Favorites itself switched successfully. This isolates the interaction region from query/filter logic.

Make both collection labels full width, at least 44 pt high, and apply a rectangular content shape inside the plain Button label after sizing/padding. No filtering logic changes.

## Validation

Signed build and signature verification passed (`.build/sidebar-hit-target-build.log`). On the rebuilt app, the original failing coordinate (100, 151) selected Favorites. Games right-side blank area (100, 117) selected Games. Lower blank edges (100, 167) and (100, 129) also switched Favorites/Games respectively. These were real coordinate clicks, not accessibility button invocation. Layout-only change: no redundant unit test added.
