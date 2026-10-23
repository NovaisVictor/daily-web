// @vitest-environment node
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { randomBytes, randomUUID } from 'node:crypto';
import type { McpServer } from '@modelcontextprotocol/server';
import type { z } from 'zod';
import { createUser } from '@/lib/auth/users';
import type { Principal } from '@/lib/access/principal';
import { registerAgentTools } from '@/lib/mcp/tools/agents';
import { registerIntegrationTools } from '@/lib/mcp/tools/integrations';
import type { Agent, AgentSession, AgentTask } from '@/lib/agents/model';
import { listTasks, listSessions } from '@/lib/agents/operations';

vi.mock('@/lib/mcp/auth', () => ({ revalidatePrincipal: vi.fn() }));

interface Reply {
  isError?: boolean;
  structuredContent?: { result: unknown };
  content: { type: string; text: string }[];
}
interface Registration {
  name: string;
  mode: 'read' | 'write';
  schema: z.ZodObject;
  call: (input: Record<string, unknown>) => Promise<Reply>;
}
const contract = readFileSync(path.resolve('specs/001-agent-workspace/contracts/mcp-capabilities.md'), 'utf8');
const inventory = [...contract.matchAll(/^\| `([a-z_]+)` \| `([a-z]+:[a-z]+)` \| (read|write) \|/gm)]
  .map(match => ({ name: match[1], scope: match[2], mode: match[3] as 'read' | 'write' }));
const scopes = [...new Set(inventory.map(item => item.scope))];
let dir: string;
let owner: Principal;
let other: Principal;

function registered(principal: Principal): Map<string, Registration> {
  const tools = new Map<string, Registration>();
  const server = { registerTool: (name: string, config: { inputSchema: z.ZodObject; annotations: { readOnlyHint: boolean } }, call: Registration['call']) => {
    if (tools.has(name)) throw new Error(`Duplicate tool registration: ${name}`);
    tools.set(name, { name, schema: config.inputSchema, mode: config.annotations.readOnlyHint ? 'read' : 'write', call });
  } } as unknown as McpServer;
  registerAgentTools(server, principal);
  registerIntegrationTools(server, principal);
  return tools;
}
const mutation = () => ({ operationId: randomUUID(), requestedAt: new Date().toISOString() });
async function result<T>(tools: Map<string, Registration>, name: string, input: Record<string, unknown>): Promise<T> {
  const tool = tools.get(name);
  expect(tool, name).toBeDefined();
  const reply = await tool!.call(input);
  expect(reply.isError, name).not.toBe(true);
  return reply.structuredContent!.result as T;
}

beforeEach(async () => {
  dir = mkdtempSync(path.join(tmpdir(), 'daily-mcp-parity-'));
  vi.stubEnv('DAILY_WEB_DB_PATH', path.join(dir, 'test.db'));
  const a = await createUser('parity-owner', randomBytes(32).toString('hex'));
  const b = await createUser('parity-other', randomBytes(32).toString('hex'));
  owner = { userId: a.id, scopes, kind: 'oauth' };
  other = { userId: b.id, scopes, kind: 'oauth' };
});
afterEach(() => { vi.restoreAllMocks(); vi.unstubAllEnvs(); rmSync(dir, { recursive: true, force: true }); });

describe('maintained MCP capability inventory', () => {
  it('requires every registered capability and its mutation annotation to match the reviewed inventory', () => {
    const tools = registered(owner);
    expect(inventory.length).toBeGreaterThan(0);
    expect(new Set(inventory.map(item => item.name)).size).toBe(inventory.length);
    expect([...tools.keys()].sort()).toEqual(inventory.map(item => item.name).sort());
    for (const entry of inventory) expect(tools.get(entry.name)!.mode, entry.name).toBe(entry.mode);
  });

  it('advertises exactly the consented surface for each individual scope, including no tools without consent', () => {
    expect(registered({ ...owner, scopes: [] }).size).toBe(0);
    for (const scope of scopes) {
      expect([...registered({ ...owner, scopes: [scope] }).keys()].sort(), scope)
        .toEqual(inventory.filter(item => item.scope === scope).map(item => item.name).sort());
    }
  });

  it('rejects unknown input before making external calls or creating agent state for every tool', async () => {
    const network = vi.spyOn(globalThis, 'fetch').mockRejectedValue(new Error('Unexpected external call'));
    for (const tool of registered(owner).values()) {
      const reply = await tool.call({ unexpectedInput: 'must never be accepted' });
      expect(reply.isError, tool.name).toBe(true);
      expect(reply.structuredContent, tool.name).toBeUndefined();
    }
    expect(network).not.toHaveBeenCalled();
    expect(listTasks(owner.userId).items).toHaveLength(0);
    expect(listSessions(owner.userId).items).toHaveLength(0);
  });

  it('rechecks capability permission inside every registered callback before parsing or side effects', async () => {
    const narrowed = { ...owner };
    const tools = registered(narrowed);
    narrowed.scopes = [];
    const network = vi.spyOn(globalThis, 'fetch').mockRejectedValue(new Error('Unexpected external call'));
    for (const tool of tools.values()) {
      const reply = await tool.call({});
      expect(reply.isError, tool.name).toBe(true);
      expect(JSON.parse(reply.content[0].text).code, tool.name).toBe('insufficient_scope');
    }
    expect(network).not.toHaveBeenCalled();
  });

  it('executes the complete agent tool lifecycle through shared persistence, versioning and owner isolation', async () => {
    const tools = registered(owner);
    const agent = await result<Agent>(tools, 'agents_register', { input: { externalId: 'agent', provider: 'codex', displayName: 'Parity Codex' }, ...mutation() });
    const session = await result<AgentSession>(tools, 'agents_sessions_create', { agentId: agent.id, externalId: 'session', ...mutation() });
    expect(await result(tools, 'agents_sessions_list', {})).toMatchObject({ items: [{ id: session.id }] });
    expect(await result(tools, 'agents_sessions_get', { id: session.id })).toMatchObject({ agentId: agent.id });
    expect(await result(tools, 'agents_sessions_heartbeat', { id: session.id, ...mutation() })).toMatchObject({ id: session.id });
    const task = await result<AgentTask>(tools, 'agents_tasks_create', { input: { externalId: 'work', title: 'Ship safely', assignment: { sessionId: session.id } }, ...mutation() });
    expect(await result(tools, 'agents_tasks_list', { sessionId: session.id })).toMatchObject({ items: [{ id: task.id }] });
    expect(await result(tools, 'agents_tasks_get', { id: task.id })).toMatchObject({ title: 'Ship safely' });
    const updated = await result<AgentTask>(tools, 'agents_tasks_update', { id: task.id, input: { expectedVersion: task.version, title: 'Ship with evidence' }, ...mutation() });
    const working = await result<AgentTask>(tools, 'agents_tasks_transition', { id: task.id, status: 'working', expectedVersion: updated.version, ...mutation() });
    const activity = { id: task.id, input: { kind: 'progress', summary: 'Validated' }, ...mutation() };
    await result(tools, 'agents_tasks_activity', activity);
    await result(tools, 'agents_tasks_activity', activity);
    expect(await result(tools, 'agents_tasks_list_activity', { id: task.id })).toMatchObject({ items: expect.arrayContaining([expect.objectContaining({ summary: 'Validated' })]) });
    expect(await result(tools, 'agents_tasks_get', { id: task.id })).toMatchObject({ version: working.version });
    const foreign = await registered(other).get('agents_tasks_get')!.call({ id: task.id });
    expect(foreign.isError).toBe(true);
    expect(JSON.parse(foreign.content[0].text).code).toBe('not_found');
    const deletion = { id: task.id, ...mutation() };
    await result(tools, 'agents_tasks_delete', deletion);
    await result(tools, 'agents_tasks_delete', deletion);
    expect(listTasks(owner.userId).items).toHaveLength(0);
  });
});
