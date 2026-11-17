import test from 'node:test';
import assert from 'node:assert/strict';
import { createJiti } from '/Users/hibiki/.pi/agent/install/releases/1.5.2/node_modules/jiti/lib/jiti.mjs';
const { authorizeCUA } = await createJiti(import.meta.url).import('./approval.ts');
const request = { message: 'Allow Finder?', _meta: { codex_approval_kind: 'mcp_tool_call', connector_id: 'computer-use', tool_name: 'get_app_state', tool_params: { app: 'com.apple.finder' }, riskLevel: 'low' } };

test('explicit approval preserves target and returns accept without permanent access', async () => {
  const result = await authorizeCUA(request, new AbortController().signal, { select: async (title, choices) => {
    assert.match(title, /com.apple.finder/);
    assert.deepEqual(choices, ['Allow this request', 'Decline']);
    return choices[0];
  } });
  assert.deepEqual(result, { action: 'accept', content: {} });
});
test('decline and dismissed dialog never grant permission', async () => {
  for (const choice of ['Decline', undefined, 'unexpected']) {
    const result = await authorizeCUA(request, new AbortController().signal, { select: async () => choice });
    assert.equal(result.action, choice === undefined ? 'cancel' : 'decline');
  }
});
test('aborted request does not open dialog', async () => {
  const controller = new AbortController(); controller.abort();
  assert.deepEqual(await authorizeCUA(request, controller.signal, { select: async () => { throw Error('must not open'); } }), { action: 'cancel' });
});
test('abort while approval is pending wins over late acceptance', async () => {
  const controller = new AbortController();
  const result = await authorizeCUA(request, controller.signal, { select: async () => { controller.abort(); return 'Allow this request'; } });
  assert.deepEqual(result, { action: 'cancel' });
});
test('unknown permission protocol fails closed', async () => {
  await assert.rejects(authorizeCUA({ message: 'unknown', _meta: {} }, new AbortController().signal, { select: async () => { throw Error('must not open'); } }), /Unsupported CUA/);
});
test('explicit workspace grant accepts repeated CUA requests without UI', async () => {
  const ui = { select: async () => { throw Error('must not prompt'); } };
  for (const tool_name of ['get_app_state', 'click', 'press_key']) {
    assert.deepEqual(await authorizeCUA({ ...request, _meta: { ...request._meta, tool_name } }, new AbortController().signal, ui, 'user-authorized-workspace'), { action: 'accept', content: {} });
  }
  const controller = new AbortController(); controller.abort();
  assert.deepEqual(await authorizeCUA(request, controller.signal, ui, 'user-authorized-workspace'), { action: 'cancel' });
  await assert.rejects(authorizeCUA({ message: 'other', _meta: {} }, new AbortController().signal, ui, 'user-authorized-workspace'), /Unsupported CUA/);
});
