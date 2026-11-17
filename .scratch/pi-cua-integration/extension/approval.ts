import type { ExtensionToolContext } from '@earendil-works/pi-coding-agent';

function object(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error('Expected an object');
  return Object.fromEntries(Object.entries(value));
}

export async function authorizeCUA(raw: unknown, signal: AbortSignal, ui: Pick<ExtensionToolContext['ui'], 'select'>, policy: 'ask' | 'user-authorized-workspace' = 'ask') {
  if (signal.aborted) return { action: 'cancel' };
  const params = object(raw);
  const meta = object(params._meta ?? params.meta ?? {});
  if (meta.codex_approval_kind !== 'mcp_tool_call' || meta.connector_id !== 'computer-use' || typeof params.message !== 'string') {
    throw new Error('Unsupported CUA approval request; no permission granted');
  }
  if (policy === 'user-authorized-workspace') return { action: 'accept', content: {} };
  const choice = await ui.select(
    `${params.message}\n${JSON.stringify({ tool: meta.tool_name, target: meta.tool_params, risk: meta.riskLevel })}`,
    ['Allow this request', 'Decline'],
    { signal, timeout: 120_000 },
  );
  if (signal.aborted || choice === undefined) return { action: 'cancel' };
  if (choice !== 'Allow this request') return { action: 'decline' };
  return { action: 'accept', content: {} };
}
