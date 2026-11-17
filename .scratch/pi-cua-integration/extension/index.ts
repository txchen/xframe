import { readFile, writeFile } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';
import { Type } from '@earendil-works/pi-ai';
import type { ExtensionAPI, ExtensionToolContext } from '@earendil-works/pi-coding-agent';
import { McpClient, StdioTransport, toLlmContent } from '/Users/hibiki/.pi/agent/install/releases/1.5.2/node_modules/@earendil-works/pi-mcp/dist/index.js';
import { authorizeCUA } from './approval.ts';

const manifest = '/Users/hibiki/.codex/plugins/cache/openai-bundled/unified-computer-use/26.1027.51404/.mcp.json';

function object(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error('Expected an object');
  return Object.fromEntries(Object.entries(value));
}

async function transport() {
  const config = object(object(object(JSON.parse(await readFile(manifest, 'utf8'))).mcpServers).cua_repl);
  if (typeof config.command !== 'string' || !Array.isArray(config.args) || !config.args.every(x => typeof x === 'string')) {
    throw new Error('Invalid official CUA launch manifest');
  }
  const env: Record<string, string> = {};
  for (const key of ['PATH', 'HOME', 'TMPDIR', 'LANG']) {
    const value = process.env[key];
    if (value) env[key] = value;
  }
  for (const [key, value] of Object.entries(object(config.env))) {
    if (typeof value !== 'string') throw new Error(`Invalid CUA environment: ${key}`);
    env[key] = value;
  }
  env.CUA_REPL_ENABLED_SURFACES = 'computer';
  return new StdioTransport({ command: config.command, args: config.args, env, inheritEnv: false });
}

export default function cuaExtension(pi: ExtensionAPI) {
  const permittedWorkspaces = new Set([
    '/Users/hibiki/.paseo/worktrees/0d5k41il/original-display-latency',
  ]);
  if (!permittedWorkspaces.has(process.cwd())) return;
  let client: McpClient | undefined;
  let sessionId = randomUUID();
  let turnId = randomUUID();
  let active: { ctx: ExtensionToolContext; signal: AbortSignal | undefined } | undefined;
  let busy = false;

  async function approve(raw: unknown, request: { signal: AbortSignal }) {
    if (!active || request.signal.aborted || active.signal?.aborted) return { action: 'cancel' };
    const signal = active.signal ? AbortSignal.any([request.signal, active.signal]) : request.signal;
    // User explicitly authorized CUA without repeated prompts for this research workspace.
    return authorizeCUA(raw, signal, active.ctx.ui, 'user-authorized-workspace');
  }

  async function invoke(name: string, args: Record<string, unknown>, ctx: ExtensionToolContext, signal?: AbortSignal) {
    if (!client || client.connectionState !== 'connected') throw new Error('CUA disconnected; reload the extension before retrying');
    if (busy) throw new Error('CUA calls must be sequential');
    busy = true;
    active = { ctx, signal };
    try {
      const result = await client.callTool(name, args, { signal, timeoutMs: 180_000 });
      // Keep image blocks as images, not JSON/base64 text. Preserve raw metadata in details.
      if (result.isError) throw new Error(result.content.filter(c => c.type === 'text').map(c => c.text).join('\n'));
      return { content: toLlmContent(result), details: result };
    } finally {
      active = undefined;
      busy = false;
    }
  }

  pi.on('session_start', async (_event, ctx) => {
    const diagnostic = '/Users/hibiki/code/vibe/xframe/.scratch/pi-cua-integration/extension-status.json';
    await writeFile(diagnostic, JSON.stringify({ state: 'starting', cwd: ctx.cwd, at: new Date().toISOString() }));
    sessionId = ctx.sessionManager.getSessionId();
    client = new McpClient({ name: 'pi-cua', version: '0.1.0', capabilities: { elicitation: {} }, requestTimeoutMs: 180_000 });
    client.setRequestHandler('elicitation/create', approve);
    try {
      await client.connect(await transport());
      const tools = await client.listTools();
      const js = tools.find(t => t.name === 'js');
      const reset = tools.find(t => t.name === 'js_reset');
      if (!js || !reset) throw new Error('CUA server did not supply js/js_reset');
      const instructions = client.instructions ?? '';
      pi.registerTool({
        name: 'mcp__cua_repl__js', label: 'CUA',
        description: `${instructions}\n\n${js.description ?? ''}`,
        exposure: 'direct',
        parameters: Type.Object({ code: Type.String(), timeout_ms: Type.Optional(Type.Integer({ minimum: 1 })), title: Type.Optional(Type.String()) }),
        async execute(_id, params, signal, _update, toolCtx) { return invoke('js', params, toolCtx, signal); },
      });
      await writeFile(diagnostic, JSON.stringify({ state: 'connected', cwd: ctx.cwd, tools: ['mcp__cua_repl__js', 'mcp__cua_repl__js_reset'], at: new Date().toISOString() }));
      pi.registerTool({
        name: 'mcp__cua_repl__js_reset', label: 'Reset CUA',
        description: reset.description ?? 'Reset the persistent CUA session.', exposure: 'direct', parameters: Type.Object({}),
        async execute(_id, params, signal, _update, toolCtx) { return invoke('js_reset', params, toolCtx, signal); },
      });
    } catch (error) {
      await client.close();
      client = undefined;
      await writeFile(diagnostic, JSON.stringify({ state: 'failed', cwd: ctx.cwd, error: error instanceof Error ? error.message : String(error), at: new Date().toISOString() }));
      ctx.ui.notify(`CUA unavailable: ${error instanceof Error ? error.message : String(error)}`, 'error');
    }
  });

  pi.on('agent_start', async () => { turnId = randomUUID(); });
  pi.on('agent_settled', async (_event, ctx) => {
    if (client?.connectionState === 'connected' && !busy) {
      try {
        await client.callTool('turn_ended', { hook_event_name: 'Stop', session_id: sessionId, turn_id: turnId }, { timeoutMs: 10_000 });
      } catch (error) {
        ctx.ui.notify(`CUA cleanup failed: ${error instanceof Error ? error.message : String(error)}`, 'warning');
      }
    }
  });
  pi.on('session_shutdown', async () => {
    await client?.close();
    client = undefined;
  });
}
