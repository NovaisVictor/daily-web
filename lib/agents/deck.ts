import { execFile } from 'node:child_process';
import { createHash } from 'node:crypto';
import { homedir, hostname } from 'node:os';
import path from 'node:path';
import { z } from 'zod';
import { AccessError } from '@/lib/access/principal';
import type { AgentSession, AgentTask, Live, LiveState, Provider } from './model';
import { sessionRefs } from './operations';

// Agent Deck runs the agents' terminals on the same host as this server. The
// reporting helper derives its session key from the deck id, so the server can
// recompute that key and reach the matching terminal without a new protocol.
// Reaching a terminal reads its screen and types into it, so it is only ever
// offered to the single user named in DAILY_WEB_AGENT_DECK_OWNER.

const LIST_TIMEOUT_MS = 2000;
const COMMAND_TIMEOUT_MS = 4000;
const LIST_TTL_MS = 2000;
export const MESSAGE_MAX = 4000;
const PANE_MAX = 48 * 1024;
const RESPONSE_MAX = 16 * 1024;

const deckStatuses = ['running', 'waiting', 'idle', 'error', 'stopped', 'starting'] as const;
const entrySchema = z.object({ id: z.string().regex(/^[A-Za-z0-9-]{1,80}$/), tool: z.string(), status: z.enum(deckStatuses), substate: z.string().nullish(), last_activity_at: z.string().nullish() });
const outputSchema = z.object({ success: z.literal(true), content: z.string(), timestamp: z.string().nullish() });
const sendSchema = z.object({ success: z.literal(true), send_id: z.string().min(1).max(80), state: z.string().max(40) });
type Entry = z.infer<typeof entrySchema>;

interface Cache { at: number; entries: Map<string, Entry> }
const cache = globalThis as typeof globalThis & { __agentDeckList?: Cache };

function binary(): string { return process.env.AGENT_DECK_BIN || path.join(homedir(), '.local/bin/agent-deck'); }

function run(args: string[], input?: string, timeout = COMMAND_TIMEOUT_MS): Promise<string> {
  return new Promise((resolve, reject) => {
    const child = execFile(/*turbopackIgnore: true*/ binary(), args, { timeout, maxBuffer: 4 * 1024 * 1024, env: { ...process.env, TMUX: '', TMUX_PANE: '' } }, (error, stdout) => error ? reject(error) : resolve(stdout));
    if (input !== undefined) child.stdin?.end(input);
  });
}

export function deckEnabled(userId: string): boolean {
  const owner = process.env.DAILY_WEB_AGENT_DECK_OWNER?.trim();
  return Boolean(owner) && owner === userId;
}

export function sessionKey(provider: Provider, deckId: string, host = hostname()): string {
  return 'dw-' + createHash('sha256').update(`${provider}:${host}:deck:${deckId}`).digest('hex').slice(0, 32);
}

async function entries(): Promise<Map<string, Entry>> {
  const now = Date.now();
  const cached = cache.__agentDeckList;
  if (cached && now - cached.at < LIST_TTL_MS) return cached.entries;
  const map = new Map<string, Entry>();
  const raw: unknown = JSON.parse(await run(['list', '--json'], undefined, LIST_TIMEOUT_MS));
  if (!Array.isArray(raw)) throw new Error('Agent Deck list is not an array');
  for (const item of raw) {
    const parsed = entrySchema.safeParse(item);
    if (!parsed.success) { console.warn('[agent-deck] unrecognised session entry ignored'); continue; }
    map.set(parsed.data.id, parsed.data);
  }
  cache.__agentDeckList = { at: now, entries: map };
  return map;
}

export function liveState(entry: Pick<Entry, 'status' | 'substate'>): LiveState {
  if (entry.status === 'stopped' || entry.status === 'error') return 'stopped';
  if (entry.status === 'running' || entry.status === 'starting') return 'working';
  if (entry.substate === 'running') return 'background';
  if (entry.substate === 'menu-open') return 'prompt';
  return 'idle';
}

export interface SessionRef { id: string; externalId: string; provider: Provider }

async function locate(ref: SessionRef): Promise<Entry | null> {
  for (const entry of (await entries()).values()) if (sessionKey(ref.provider, entry.id) === ref.externalId) return entry;
  return null;
}

export async function liveFor(userId: string, refs: SessionRef[]): Promise<Map<string, Live>> {
  const result = new Map<string, Live>();
  if (!deckEnabled(userId) || refs.length === 0) return result;
  let all: Map<string, Entry>;
  try { all = await entries(); } catch { console.warn('[agent-deck] session list unavailable'); return result; }
  const byKey = new Map<string, Entry>();
  for (const entry of all.values()) for (const provider of ['claude', 'codex', 'gemini'] as const) byKey.set(sessionKey(provider, entry.id), entry);
  for (const ref of refs) {
    const entry = byKey.get(ref.externalId);
    if (entry) result.set(ref.id, { state: liveState(entry), since: entry.last_activity_at ?? null });
  }
  return result;
}

const ANSI = /\x1b\[[0-?]*[ -/]*[@-~]|\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)|\x1b[@-Z\\-_]/g;
function clean(text: string, max: number): string {
  const plain = text.replace(ANSI, '').replace(/\r/g, '').replace(/\s+$/, '');
  return plain.length > max ? plain.slice(plain.length - max) : plain;
}

export interface Terminal { available: true; live: Live; pane: string; response: { content: string; at: string | null } | null; capturedAt: string }
export type TerminalView = Terminal | { available: false; reason: 'not_enabled' | 'not_local' | 'unavailable' };

export async function terminal(userId: string, ref: SessionRef): Promise<TerminalView> {
  if (!deckEnabled(userId)) return { available: false, reason: 'not_enabled' };
  let entry: Entry | null;
  try { entry = await locate(ref); } catch { return { available: false, reason: 'unavailable' }; }
  if (!entry) return { available: false, reason: 'not_local' };
  const live = { state: liveState(entry), since: entry.last_activity_at ?? null };
  const [pane, response] = await Promise.allSettled([run(['session', 'output', '--pane', '--json', entry.id]), run(['session', 'output', '--json', '--max-tokens', '4000', entry.id])]);
  const parse = (value: PromiseSettledResult<string>) => { if (value.status !== 'fulfilled') return null; try { const parsed = outputSchema.safeParse(JSON.parse(value.value)); return parsed.success ? parsed.data : null; } catch { return null; } };
  const screen = parse(pane), last = parse(response);
  if (!screen && !last) return { available: false, reason: 'unavailable' };
  return { available: true, live, pane: screen ? clean(screen.content, PANE_MAX) : '', response: last ? { content: clean(last.content, RESPONSE_MAX), at: last.timestamp ?? null } : null, capturedAt: new Date().toISOString() };
}

export async function sendMessage(userId: string, ref: SessionRef, text: string): Promise<{ ok: true; id: string; state: string }> {
  if (!deckEnabled(userId)) throw new AccessError(403, 'terminal_not_enabled', 'Terminal access is not enabled for this user');
  let entry: Entry | null;
  try { entry = await locate(ref); } catch { throw new AccessError(503, 'deck_unavailable', 'Agent Deck is unavailable'); }
  if (!entry) throw new AccessError(404, 'terminal_not_local', 'This session does not run on this server');
  if (liveState(entry) === 'stopped') throw new AccessError(409, 'session_stopped', 'The agent session is not running');
  let output: string;
  try { output = await run(['session', 'send', '--message-file', '-', '--queue', '--json', '--no-tag', entry.id], text); }
  catch (error) {
    // A timeout may have queued the message anyway; only a clean refusal is safe to retry.
    if ((error as { killed?: boolean }).killed) throw error;
    throw new AccessError(502, 'send_refused', 'Agent Deck refused the message');
  }
  const parsed = sendSchema.parse(JSON.parse(output));
  return { ok: true, id: parsed.send_id, state: parsed.state };
}

export async function attachLive<T extends { tasks: AgentTask[]; sessions: AgentSession[] }>(userId: string, view: T): Promise<T> {
  if (!deckEnabled(userId)) return view;
  const ids = [...view.tasks.flatMap(task => task.assignment ? [task.assignment.sessionId] : []), ...view.sessions.map(session => session.id)];
  const live = await liveFor(userId, sessionRefs(userId, ids));
  return { ...view, tasks: view.tasks.map(task => task.assignment ? { ...task, assignment: { ...task.assignment, live: live.get(task.assignment.sessionId) ?? null } } : task), sessions: view.sessions.map(session => ({ ...session, live: live.get(session.id) ?? null })) };
}
