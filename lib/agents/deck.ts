import { execFile } from 'node:child_process';
import { createHash } from 'node:crypto';
import { homedir, hostname } from 'node:os';
import path from 'node:path';
import { z } from 'zod';
import { AccessError } from '@/lib/access/principal';
import type { AgentSession, AgentTask, Live, LiveState, Provider } from './model';
import { sessionRefs } from './operations';

// Agent Deck runs the agents' terminals on this host and, over SSH, on the
// machines named in DAILY_WEB_AGENT_DECK_REMOTES (aliases from the service
// account's ~/.ssh/config). The reporting helper derives its session key from
// the machine's hostname and the deck id, so the server recomputes that key to
// reach the matching terminal without a new protocol. Reaching a terminal reads
// its screen and types into it, so it is only ever offered to the single user
// named in DAILY_WEB_AGENT_DECK_OWNER.

const LIST_TIMEOUT_MS = 2000;
const REMOTE_LIST_TIMEOUT_MS = 6000;
const COMMAND_TIMEOUT_MS = 8000;
const LIST_TTL_MS = 2000;
const REMOTE_RETRY_MS = 15_000;
const REMOTE_STALE_MS = 60_000;
export const MESSAGE_MAX = 4000;
const PANE_MAX = 48 * 1024;
const RESPONSE_MAX = 16 * 1024;

const deckStatuses = ['running', 'waiting', 'idle', 'error', 'stopped', 'starting'] as const;
const entrySchema = z.object({ id: z.string().regex(/^[A-Za-z0-9-]{1,80}$/), tool: z.string(), status: z.enum(deckStatuses), substate: z.string().nullish(), last_activity_at: z.string().nullish() });
const outputSchema = z.object({ success: z.literal(true), content: z.string(), timestamp: z.string().nullish() });
const sendSchema = z.object({ success: z.literal(true), send_id: z.string().min(1).max(80), state: z.string().max(40) });
const hostnameSchema = z.string().trim().regex(/^[A-Za-z0-9.-]{1,253}$/);
type Entry = z.infer<typeof entrySchema> & { machine: Machine };
interface Machine { target: string | null; hostname: string }

interface Listing { at: number; entries: Entry[]; failedAt: number; pending: Promise<Entry[]> | null }
const cache = globalThis as typeof globalThis & { __agentDeckListings?: Map<string, Listing>; __agentDeckHostnames?: Map<string, string> };
function listings(): Map<string, Listing> { return cache.__agentDeckListings ??= new Map(); }

function binary(): string { return process.env.AGENT_DECK_BIN || path.join(homedir(), '.local/bin/agent-deck'); }

export function remotes(): string[] {
  return (process.env.DAILY_WEB_AGENT_DECK_REMOTES ?? '').split(',').map(value => value.trim()).filter(value => /^[A-Za-z0-9][A-Za-z0-9._-]{0,62}$/.test(value));
}

const quote = (value: string) => `'${value.replace(/'/g, `'\\''`)}'`;
function run(target: string | null, args: string[], input?: string, timeout = COMMAND_TIMEOUT_MS): Promise<string> {
  // Remote arguments are fixed literals plus a validated deck id; free text only ever travels on stdin.
  const [file, argv] = target === null
    ? [binary(), args]
    : [process.env.AGENT_DECK_SSH_BIN || 'ssh', ['-T', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=4', '-o', 'ControlMaster=auto', '-o', 'ControlPath=~/.ssh/cm-daily-web-%C', '-o', 'ControlPersist=120', target, args[0] === 'hostname' ? 'hostname' : `"$HOME"/.local/bin/agent-deck ${args.map(quote).join(' ')}`]];
  return new Promise((resolve, reject) => {
    const child = execFile(/*turbopackIgnore: true*/ file, argv, { timeout, maxBuffer: 4 * 1024 * 1024, env: { ...process.env, TMUX: '', TMUX_PANE: '' } }, (error, stdout) => error ? reject(error) : resolve(stdout));
    child.stdin?.on('error', () => {});
    child.stdin?.end(input ?? '');
  });
}

export function deckEnabled(userId: string): boolean {
  const owner = process.env.DAILY_WEB_AGENT_DECK_OWNER?.trim();
  return Boolean(owner) && owner === userId;
}

export function sessionKey(provider: Provider, deckId: string, host = hostname()): string {
  return 'dw-' + createHash('sha256').update(`${provider}:${host}:deck:${deckId}`).digest('hex').slice(0, 32);
}

async function remoteHostname(target: string): Promise<string> {
  const known = (cache.__agentDeckHostnames ??= new Map());
  const cached = known.get(target);
  if (cached) return cached;
  const value = hostnameSchema.parse(await run(target, ['hostname'], undefined, REMOTE_LIST_TIMEOUT_MS));
  known.set(target, value);
  return value;
}

async function fetchListing(target: string | null): Promise<Entry[]> {
  const remote = target !== null;
  const [raw, host] = await Promise.all([
    run(target, ['list', '--json'], undefined, remote ? REMOTE_LIST_TIMEOUT_MS : LIST_TIMEOUT_MS),
    remote ? remoteHostname(target) : Promise.resolve(hostname()),
  ]);
  const parsed: unknown = JSON.parse(raw);
  if (!Array.isArray(parsed)) throw new Error('Agent Deck list is not an array');
  const machine = { target, hostname: host };
  return parsed.flatMap(item => {
    const entry = entrySchema.safeParse(item);
    if (!entry.success) { console.warn('[agent-deck] unrecognised session entry ignored'); return []; }
    return [{ ...entry.data, machine }];
  });
}

// The board must not wait for a sleeping laptop: with wait=false a remote
// listing is served from cache and refreshed in the background.
async function listing(target: string | null, wait: boolean): Promise<Entry[]> {
  const key = target ?? '';
  const now = Date.now();
  const state = listings().get(key) ?? { at: 0, entries: [], failedAt: 0, pending: null };
  listings().set(key, state);
  if (now - state.at < LIST_TTL_MS) return state.entries;
  if (!state.pending && (target === null || wait || now - state.failedAt >= REMOTE_RETRY_MS)) {
    state.pending = fetchListing(target)
      .then(entries => { state.at = Date.now(); state.entries = entries; return entries; })
      .catch(error => { state.failedAt = Date.now(); if (Date.now() - state.at > REMOTE_STALE_MS) state.entries = []; throw error; })
      .finally(() => { state.pending = null; });
    state.pending.catch(() => console.warn(`[agent-deck] ${target ?? 'local'} listing unavailable`));
  }
  // A slow listing under load keeps the last good one for a minute instead of
  // dropping every live state, which would bring back the false alerts.
  if (target === null || wait) return state.pending ? state.pending.catch(error => { if (Date.now() - state.at <= REMOTE_STALE_MS) return state.entries; throw error; }) : state.entries;
  return now - state.at <= REMOTE_STALE_MS ? state.entries : [];
}

async function entries(wait: boolean): Promise<{ list: Entry[]; complete: boolean }> {
  const results = await Promise.allSettled([null, ...remotes()].map(target => listing(target, wait)));
  if (results[0].status === 'rejected' && results.every(result => result.status === 'rejected')) throw results[0].reason;
  return { list: results.flatMap(result => result.status === 'fulfilled' ? result.value : []), complete: results.every(result => result.status === 'fulfilled') };
}

export function liveState(entry: Pick<Entry, 'status' | 'substate'>): LiveState {
  if (entry.status === 'stopped' || entry.status === 'error') return 'stopped';
  if (entry.status === 'running' || entry.status === 'starting') return 'working';
  if (entry.substate === 'running') return 'background';
  if (entry.substate === 'menu-open') return 'prompt';
  return 'idle';
}

export interface SessionRef { id: string; externalId: string; provider: Provider }

// 'unreachable' when the session was not found but some machine did not answer.
async function locate(ref: SessionRef): Promise<Entry | 'unreachable' | null> {
  const { list, complete } = await entries(true);
  return list.find(entry => sessionKey(ref.provider, entry.id, entry.machine.hostname) === ref.externalId) ?? (complete ? null : 'unreachable');
}

export async function liveFor(userId: string, refs: SessionRef[], wait = false): Promise<Map<string, Live>> {
  const result = new Map<string, Live>();
  if (!deckEnabled(userId) || refs.length === 0) return result;
  let all: Entry[];
  try { all = (await entries(wait)).list; } catch { console.warn('[agent-deck] session list unavailable'); return result; }
  const byKey = new Map<string, Entry>();
  for (const entry of all) for (const provider of ['claude', 'codex', 'gemini'] as const) byKey.set(sessionKey(provider, entry.id, entry.machine.hostname), entry);
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
  let entry: Entry | 'unreachable' | null;
  try { entry = await locate(ref); } catch { return { available: false, reason: 'unavailable' }; }
  if (entry === 'unreachable') return { available: false, reason: 'unavailable' };
  if (!entry) return { available: false, reason: 'not_local' };
  const live = { state: liveState(entry), since: entry.last_activity_at ?? null };
  const [pane, response] = await Promise.allSettled([run(entry.machine.target, ['session', 'output', '--pane', '--json', entry.id]), run(entry.machine.target, ['session', 'output', '--json', '--max-tokens', '4000', entry.id])]);
  const parse = (value: PromiseSettledResult<string>) => { if (value.status !== 'fulfilled') return null; try { const parsed = outputSchema.safeParse(JSON.parse(value.value)); return parsed.success ? parsed.data : null; } catch { return null; } };
  const screen = parse(pane), last = parse(response);
  if (!screen && !last) return { available: false, reason: 'unavailable' };
  return { available: true, live, pane: screen ? clean(screen.content, PANE_MAX) : '', response: last ? { content: clean(last.content, RESPONSE_MAX), at: last.timestamp ?? null } : null, capturedAt: new Date().toISOString() };
}

export async function sendMessage(userId: string, ref: SessionRef, text: string): Promise<{ ok: true; id: string; state: string }> {
  if (!deckEnabled(userId)) throw new AccessError(403, 'terminal_not_enabled', 'Terminal access is not enabled for this user');
  let entry: Entry | 'unreachable' | null;
  try { entry = await locate(ref); } catch { throw new AccessError(503, 'deck_unavailable', 'Agent Deck is unavailable'); }
  if (entry === 'unreachable') throw new AccessError(503, 'deck_unavailable', 'The machine running this session did not answer');
  if (!entry) throw new AccessError(404, 'terminal_not_local', 'This session does not run on a reachable Agent Deck');
  if (liveState(entry) === 'stopped') throw new AccessError(409, 'session_stopped', 'The agent session is not running');
  let output: string;
  try { output = await run(entry.machine.target, ['session', 'send', '--message-file', '-', '--queue', '--json', '--no-tag', entry.id], text); }
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
