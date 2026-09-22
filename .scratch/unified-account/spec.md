# Unified account and library window

## Scope

Use one library shell for account onboarding and catalog browsing. Keep authentication and library models separate, retain the existing device-code authorization flow, and do not change credential persistence or the native video pipeline.

## Behavior

- Launch and Dock reopen show the library shell, not an account window.
- Without verified cloud access, the shell displays sign-in, restoration progress, cancellation, and retry errors in place.
- With verified access, display the library and a sidebar profile entry with the gamertag.
- Profile and Shift-Command-A open an account sheet with access checking and sign-out. Done or Escape dismisses it.
- Access changes dismiss the sheet and route back to the appropriate main content.
- Session ownership and catalog-loading guards continue to block account mutations.
- Development storage and region details are collapsed. No profile-image endpoint is added; use a native profile symbol.
- The native video window remains independent.

## Validation

Automated authentication coverage asserts routing state before/during restoration, after successful authorization, after downstream failure, and after sign-out. Live validation must not sign out the user's account or interrupt an active game.

### Results

- All 59 tests passed; signed production build succeeded, including the final compact-layout adjustment.
- Live restart restored saved sign-in directly into the library shell without an account window.
- Sidebar profile and Shift-Command-A both opened the embedded account sheet; Escape dismissed it.
- Check Access Again completed successfully and returned to the library in the same window.
- The user's previous session was already ended before restart. No live sign-out or new game launch was performed; sign-out routing remains covered by the authentication test.
