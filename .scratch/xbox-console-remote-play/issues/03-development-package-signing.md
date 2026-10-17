# Build development app with the system Bash

Status: ready-for-agent

The LAN test build compiled but packaging failed at `scripts/build-app.sh:37` with `signing_options[@]: unbound variable`. macOS Bash 3.2 treats an empty array expansion as unset under `set -u`.

Use guarded array expansion so development signing passes zero optional arguments while Developer ID signing preserves its flags. Verify with the actual app build and strict signature check.

## Resolution

Fixed and verified by a successful release app build and strict signature verification.
