# Pi CUA local extension

Installed as `~/.pi/agent/extensions/xframe-cua.ts`, linking to this directory's `index.ts`. Only the Original research worktree listed in `permittedWorkspaces` activate it. Other Pi workspaces register no tools and start no CUA process.

Uses the installed official CUA manifest and Pi 1.5.2 MCP client. Computer surface only. No parent-session identity/pipe credentials are copied. Each Pi session owns its persistent MCP process. Only `mcp__cua_repl__js` and `mcp__cua_repl__js_reset` are exposed; cleanup uses the hidden `turn_ended` tool at `agent_settled`.

The user explicitly authorized CUA without repeated approval prompts on 2026-11-16. The Original research workspace allowlist now applies that grant to valid computer-use requests without opening Pi's approval UI. Other workspaces remain disabled. Aborted and unsupported requests remain rejected. Revoke by changing the authorizeCUA policy to 'ask' and starting a fresh Pi session. Existing loaded sessions must be replaced to pick up this change.

## Verification status

- Official MCP discovery: passed.
- Fresh Pi session loading, connected tools and direct CUA invocation: passed (2026-11-16).
- `cua.getState()` reached the native CUA API in the test session; subsequent Finder access generated a real user approval request in Paseo.
- Five authorization tests passed: explicit acceptance, decline/dismissal, pre-cancel, late acceptance after abort, unsupported permission request.
- Finder access approved by the user. Persistent binding and menu click passed: a fresh AX tree confirmed View opened; its Cancel action closed it. Escape did not close the menu.
- Normal-window screenshot passed: Finder Recents returned a 2284x1454 image with toolbar and sidebar matching AX; the parent independently viewed the delivered image. Clicks opened a new window and the View menu, confirmed by fresh AX reads. Persistent bindings worked across calls.
- Remaining limitations: Finder Desktop captures were white; screenshots while its menu was open failed. Escape did not dismiss the menu, even after Raise and focus; AX Cancel did. Basic screenshot/click integration passed, but these menu/keyboard cases did not. Evidence: `../verification/result-2.md`, Round 2.
- Existing research agent has not been reloaded/replaced. New sessions in its workspace load the extension; a normal agent message containing `/reload` is not a real Pi slash command.

Startup diagnostics: `../extension-status.json`. Test agent `2df1b484-4079-45c8-8a3d-f376d7eb8e48`, workspace `wks_28e5dbed72193b22`.

Run tests with `node --test approval.test.mjs` from this directory. These tests use simulated approval responses and perform no GUI operations.

Rollback: remove only the installed `~/.pi/agent/extensions/xframe-cua.ts` symlink, then reload/restart the affected Pi session at a safe boundary. Do not terminate shared native CUA services or alter macOS permissions. The runtime/library paths are pinned to the versions inspected here; verify them after Pi or ChatGPT updates.

The temporary smoke project, workspace and two test agents were removed/archived after validation. Reports are retained in `../verification/`; the smoke directory and activation allowlist entry were removed.
