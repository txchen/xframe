# Cloud Region Selection

## Scope

Offer Automatic and the signed-in account's returned region names in Cloud Games. Automatic uses the service default, falling back to its first region. Manual selection must resolve an exact authorized region and a trusted Xbox endpoint; unknown names must fail rather than silently select another endpoint.

Keep the selection in memory for the current app run. Changing it clears the loaded catalog and selected game, requiring a fresh load with the new service. Disable changes during authentication, catalog loading, and owned sessions. Display the requested endpoint region without claiming that redirects or physical streaming placement are controlled.

Latency probes, saved preferences, geographic recommendations, region spoofing, and final server-location diagnostics are out of scope.

## Validation

All 27 tests passed, including automatic default selection, explicit selection, unknown-region rejection, and first-region fallback. The release app built and certificate signing completed successfully. Live UI validation could not proceed: computer use reported `cgWindowNotFound` for the running application through both its path and bundle identifier, and attempting to show Cloud Games had the same result. This is not evidence of a Keychain prompt. Manual selection and a real session from the chosen region remain unverified.

### Completed Live Follow-up

After the user dismissed the screen saver, UI access recovered. The old app was exited with no active session, and the new build was launched. The user reported a password prompt for the Microsoft sign-in Keychain item; repeated authorization after rebuild remains unresolved and is not a signing-private-key prompt.

Automatic resolved to WESTUS2 for this authorization. Selecting WESTUS loaded 2671 titles. Switching to WESTUS2 cleared the old catalog and disabled Start Session until a fresh load and selection. The WESTUS2 catalog also contained 2671 titles. Region selection was disabled during loading and while owning a session.

A manually selected WESTUS2 Fortnite session rendered 1920×1080 H.264 with hardware decoding, a 1/1 queue, average decode 49.8 FPS and presentation 48.8 FPS at the sampled observation. The startup accumulated 49 recoverable decode errors; this test does not establish that region choice improves decoder reliability or latency. No final physical server location was verified.

Command-0 stopped the test and the library confirmed Session ended. Region selection and Start Session were re-enabled, with WESTUS2 still selected. No active cloud session remains. This follow-up completes the previously blocked UI and selected-region session checks.
