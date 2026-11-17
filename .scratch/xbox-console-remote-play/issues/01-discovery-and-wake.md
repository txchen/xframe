# Correct console discovery and bounded wake

Status: ready-for-human

SmartGlass discovery parses the console name at byte 14, but the primary packet schema places it at byte 12. Existing synthetic fixtures mirror the offset mistake.

The live app lists one Series X as ConnectedStandby. Wake Console remains at Sending wake command and the user confirms the console remains asleep. The exact timeout cause is not yet established.

Fix discovery using the reference schema, validate the standard wake response without requiring optional result, and bound the wake operation. Preserve separate Wake and Connect actions.

## Evidence

- https://github.com/OpenXbox/xbox-smartglass-core-python/blob/master/xbox/sg/packet/simple.py
- https://github.com/OpenXbox/xbox-webapi-python/blob/master/xbox/webapi/api/provider/smartglass/models.py
- Live XFrame UI and user confirmation on 2026-10-16.

## Resolution

Discovery fixed and verified with the actual Series X. Wake payload/response handling tested automatically; physical wake remains pending.

## Comments

- 2026-11-17 triage: status set to `ready-for-human`. Implementation is committed; remaining acceptance needs the physical console.
