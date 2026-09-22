# 007 First Light launch rejection

## Observed result

One user-authorized live retry in Automatic / WESTUS2 reproduced HTTP 400 at the cloud session creation endpoint. The service returned the machine-readable code `NoEntitlement`. No session address was returned, so no addressed cleanup request could be made. Do not claim confirmed absence of a remote allocation.

This identifies an entitlement rejection for this account/title request, before signaling or video decoding. It does not establish which purchase, subscription, edition, or service eligibility condition is missing. Catalog visibility is not a guarantee of launch eligibility. No further launch retry or account purchase was performed.

## Diagnostic change

Previously non-2xx responses discarded all service error detail. Session-creation failures now retain only a bounded ASCII alphabetic/underscore/hyphen code from the top-level `code` or nested `error.code`. Messages, response bodies, headers, tokens, and session identifiers are not emitted or persisted. Other HTTP behavior, including deletion handling, is unchanged.

## Validation

`bash scripts/test.sh` passed 60 tests before the live retry; the signed production bundle built successfully. The code-extraction test checks invalid JSON, non-string codes, URL/JWT-like values, oversized bodies, and exclusion of response messages. A fixture for the observed `NoEntitlement` code was added after reproduction.

The live failure is diagnosed, not fixed: improving the client cannot grant the missing service entitlement. Follow-up product work should distinguish catalog browsing from verified playability and present actionable known service errors.
