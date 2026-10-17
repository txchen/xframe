# Investigate variant-specific local network send failure

Status: needs-info

During live verification on 2026-10-16, `.build/XFrame-LAN.app` reported discovery sent=0, received=0, parsed=0, errno=65. macOS Local Network settings showed its switch enabled. The separate `.build/XFrame-LAN-Diagnostic.app` with the same designated signing requirement sent six packets, received six replies, matched the associated Series X, and streamed its dashboard successfully.

The cause is unresolved. No account mismatch was found, no network permission setting was changed, and successful streaming is established only for the documented artifact. Avoid overwriting or restarting the user's current session to investigate this.

## Evidence

See [live validation](../live-validation-2026-10-16.md) and local sanitized log `.audit/lan-console/live-network.log`.
