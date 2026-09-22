# Restore Keychain Credential Storage Before Release

Status: needs-info

## Temporary Development Decision

The user explicitly requested file-backed refresh-token storage until suitable signing certificates are available. The default is FileCredentialStore, using an unencrypted owner-only file outside the repository. It never automatically reads or writes Keychain. Existing Keychain entries remain untouched; a new Microsoft device-code sign-in initializes the file store. Do not log, commit, or include token contents in diagnostics.

File permissions are not encryption and do not protect against other processes running as the same user, privileged processes, or backups. This is a local-development exception, not the release security design.

## Follow-up

1. Obtain suitable Apple-issued signing and verify stable Keychain access across changed builds.
2. Switch the default back to Keychain with an explicit, tested migration from the file.
3. Persist and read back the migrated token successfully before removing the file; obtain appropriate user approval for cleanup. Never delete the only working credential on migration failure.
4. Update Sign Out behavior, UI, documentation, and regression tests for both stores.
5. Verify restart, changed-build restoration, token rotation, and cancellation without repeated authorization prompts. Account sign-in must remain independent of signing-private-key prompts.

## Current Verification

File-store tests use synthetic tokens only. Real account persistence requires a fresh Microsoft login and restart validation. No existing login credential was deleted or exported by this change.

All 29 automated tests passed and the release app built and signed successfully. Live startup validation was blocked by `cgWindowNotFound`; this does not establish whether a screen saver is active. The running application was not forcibly terminated. Real file creation and automatic account restoration remain pending user sign-in in the new build.

### Completed Live File-Store Validation

After the screen saver was disabled, the new build launched with the local-file warning and no saved sign-in. The user completed Microsoft device-code authentication. The app verified xCloud access. Metadata-only inspection confirmed the Credentials directory is owned by the user with mode 0700, and microsoft-refresh-token is a regular file owned by the user with mode 0600. Token contents were not inspected or logged.

The application was then quit normally and relaunched. Within approximately two seconds it showed verified xCloud credentials with a renewed expiration, without requiring user intervention. This verifies real file-backed restoration across one full same-build restart. Changed-build restoration has not yet been separately exercised. The historical blocked checks above are superseded by this successful run.
