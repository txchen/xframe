# Cloud Catalog and Session Slice

## Goal

Browse the signed-in account's cloud titles, search by English title, select a game, create a cloud session, observe startup, and explicitly end it. No audio, video, controller input, or console remote play is included.

## Scope

- Use the default region returned by authenticated xCloud login (first region only as a fallback).
- Fetch `/v2/titles`, then hydrate only those product IDs through Microsoft's public Game Pass catalog. Never send a bearer credential to that public catalog. Do not merge third-party lists or imply ownership based on public metadata. The title endpoint may not represent the complete service catalog, and launch remains the final eligibility check.
- Allow one session at a time. POST `/v5/sessions/cloud/play`, preserve the returned session address, poll state, and retrieve configuration after `Provisioned`.
- Show queued, provisioning, ready, failed, and cleanup states. `ReadyToConnect` exchanges the saved Microsoft refresh credential for a console-transfer token and submits it to `/connect`; it is not treated as provisioned. Refresh-token rotation is persisted before submitting the transfer token. Unknown future states fail explicitly and trigger cleanup.
- Ending during creation records intent and waits for the returned address before DELETE. Ending a ready session cancels the local timer but executes cleanup outside the canceled task.
- Failed cleanup retains ownership and permits retry. Do not permit another start, account replacement/sign-out, or normal app termination while a known session remains owned.
- Automatically end ready, non-streaming test sessions after 60 seconds. Stop waiting for startup after 10 minutes and attempt cleanup.
- Reset catalog state when account credentials change. Keep secrets and session URLs out of UI diagnostics and logs.

## Boundaries

HTTPS Xbox Live service/session addresses only; no credential-bearing redirects. Client device fields describe an Apple Mac, not a spoofed platform or location. Protocol compatibility environment identifiers follow the reference web client. No automatic creation retries: an interrupted POST can allocate a session without returning its address. Report that uncertainty instead of claiming cleanup. Crash/force-quit recovery and automatic expired-token renewal during a session remain deferred; this increment is for supervised short session tests.

## Reference

[XStreaming `src/xCloud/index.ts`](https://github.com/Geocld/XStreaming/blob/383e19d324f2d3029d1c304752f4d38a9360bb95/src/xCloud/index.ts), pinned to commit `383e19d324f2d3029d1c304752f4d38a9360bb95`. Its MIT attribution is retained in `THIRD_PARTY_NOTICES.md` and the app bundle.

## Acceptance

Automated: catalog header contract/no bearer leakage, safe session URL validation, queued-to-ready progression, cancellation during creation, duplicate-start exclusion, cleanup retry, unsupported-state cleanup, and account catalog reset.

Live: load real titles, search/select a game, create a session, observe ready/configuration success, end it with a successful server response. Mock tests alone do not satisfy live acceptance.
