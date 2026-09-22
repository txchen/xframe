# Account-aware cloud library

## Requirements and implementation

Default to titles the authenticated service marks `hasEntitlement: true`. Keep false and absent values distinct, expose the full catalog with explicit unavailable/unknown labels, and block launches of denied or unverified titles in both UI and model. Do not infer eligibility from Game Pass membership, free pricing, title names, publisher names, or favorites.

The existing `/v2/titles` response supplies `details.hasEntitlement`, `programs`, and `isFreeInStore`; these were previously discarded. Preserve them alongside metadata hydration. Filters compose with search, category, favorites, sorting, and paging. Reset to Playable games on account/region reset. Refresh reloads evidence. A live `NoEntitlement` response invalidates that title's cached grant and selection.

Game Pass classification currently recognizes the documented `GPULTIMATE` catalog program. Future program identifiers are not guessed. Entitlement still controls visibility, so an unfamiliar program cannot hide a confirmed playable game from the default list.

## Ownership boundary

Account access is not proof of a permanent purchase. Confirmed playable purchased cloud games are included, but a dedicated Owned label/filter is deliberately not fabricated. Grant-source integration remains follow-up work. The default list covers authenticated cloud titles, not every purchased console game.

## Reference

XStreaming documents account entitlement fields in its cloud title response:
https://github.com/Geocld/XStreaming/blob/383e19d324f2d3029d1c304752f4d38a9360bb95/docs/2.Web.md

Use the service fields, not the reference UI's keyword/fallback ownership heuristics.

## Validation

- `bash scripts/test.sh`: 63 tests passed.
- Signed production build succeeded.
- Fixtures verify true/false/missing evidence through the real catalog decoder, default filtering, classification intersections, and no create request for denied/unknown games even from All cloud games.
- Live restore selected Automatic / WESTUS; loaded 2,673 titles and showed 611 confirmed playable titles by default, with Game Pass labels.
- Further live search/filter interaction was interrupted by user window activity; no game was launched and no claim is made that every filter was UI-tested.
- Earlier 007 launch returned `NoEntitlement`; no hardcoded title exception is used.
