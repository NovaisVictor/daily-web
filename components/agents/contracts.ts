import { activityWindows, attentionKinds, holdReasons, liveStates, statuses as TASK_STATUSES, type Attention, type HeldStatus, type Hold, type HoldReason, type Live, type LiveState } from '@/lib/agents/model';
import type { AgentTask, AgentSession, Assignment, Activity, Page, SubtaskProgress, TaskStatus } from '@/lib/agents/model';
export type { Hold, HeldStatus, Live, LiveState } from '@/lib/agents/model';
export { TASK_STATUSES };
export type { AgentTask, AgentSession, Assignment, Activity, Page, SubtaskProgress, TaskStatus };
export const STATUS_LABELS: Record<TaskStatus, string> = {
  queued: 'Na fila', working: 'Em andamento', waiting: 'Aguardando processo', blocked: 'Bloqueadas',
  completed: 'Concluídas', failed: 'Falharam', cancelled: 'Canceladas',
};
export const STATUS_TONES: Record<TaskStatus, string> = {
  queued: 'bg-neutral-tint text-ink-mid', working: 'bg-info-tint text-info', waiting: 'bg-chart-4/12 text-chart-4', blocked: 'bg-warning-tint text-warning',
  completed: 'bg-success-tint text-success', failed: 'bg-danger-tint text-danger', cancelled: 'bg-neutral-tint text-ink-dim',
};
export const HOLD_LABELS: Record<HeldStatus, Record<string, string>> = {
  waiting: { pull_request: 'Revisão de PR', build: 'CI/Build', deploy: 'Deploy', external: 'Processo externo', other: 'Outro' },
  blocked: { decision: 'Decisão do usuário', access: 'Permissão/acesso', credential: 'Credencial', dependency: 'Dependência', environment: 'Erro de ambiente', other: 'Outro' },
} satisfies { [S in HeldStatus]: Record<HoldReason<S>, string> };
export function holdLabel(status: TaskStatus, hold: Hold): string { return HOLD_LABELS[status as HeldStatus]?.[hold.reason] ?? hold.reason; }
export type NeedsYouKind = Attention['kind'] | 'menu' | 'decision' | 'access' | 'credential';
export const NEEDS_YOU_LABELS: Record<NeedsYouKind, string> = {
  permission: 'Pedindo sua permissão', input: 'Aguardando sua resposta', menu: 'Esperando sua escolha no terminal', decision: 'Precisa da sua decisão', access: 'Precisa de acesso', credential: 'Precisa de credencial',
};
export const LIVE_LABELS: Record<LiveState, string> = {
  working: 'Executando agora', background: 'Rodando em segundo plano', prompt: 'Menu aberto no terminal', idle: 'Parado no prompt', stopped: 'Sessão encerrada',
};
export const LIVE_TONES: Record<LiveState, string> = {
  working: 'bg-info', background: 'bg-chart-4', prompt: 'bg-danger', idle: 'bg-ink-dim', stopped: 'bg-neutral-tint',
};
const OPEN_STATUSES: readonly TaskStatus[] = ['queued', 'working', 'waiting', 'blocked'];
const BUSY: readonly LiveState[] = ['working', 'background', 'stopped'];
// The hooks raise "input" whenever a turn ends, including turns that end to
// wait for a build running in the background. The terminal's live state and
// the agent's own "waiting" status are stronger evidence than that signal.
export function needsYou(task: AgentTask): { kind: NeedsYouKind; since: string } | null {
  if (!OPEN_STATUSES.includes(task.status)) return null;
  const live = task.assignment?.live ?? null;
  if (live?.state === 'working') return null;
  if (task.status === 'blocked' && task.hold && (task.hold.reason === 'decision' || task.hold.reason === 'access' || task.hold.reason === 'credential')) return { kind: task.hold.reason, since: task.lastActivityAt };
  if (live?.state === 'prompt') return { kind: task.assignment?.attention?.kind === 'permission' ? 'permission' : 'menu', since: task.assignment?.attention?.since ?? live.since ?? task.lastActivityAt };
  const attention = task.assignment?.attention;
  if (!attention) return null;
  if (live && BUSY.includes(live.state)) return null;
  if (attention.kind === 'input' && task.status === 'waiting') return null;
  return attention;
}
export const ACTIVITY_WINDOWS = activityWindows;
export const DEFAULT_ACTIVITY_WINDOW = 3;
export function activityWindow(value: string | null): number {
  const days = Number(value);
  return (activityWindows as readonly number[]).includes(days) ? days : DEFAULT_ACTIVITY_WINDOW;
}
export function waitedFor(since: string, now = Date.now()): string {
  const minutes = Math.max(0, Math.floor((now - Date.parse(since)) / 60000));
  return minutes < 1 ? 'agora' : minutes < 60 ? `há ${minutes} min` : `há ${Math.floor(minutes / 60)} h`;
}
export interface Snapshot { tasks: Page<AgentTask>; sessions: Page<AgentSession>; subtaskProgress: Record<string, SubtaskProgress> }
export interface TaskDetail { task: AgentTask; activity: Page<Activity>; subtasks: Page<AgentTask> }

function object(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error('Resposta inválida do servidor.');
  return value as Record<string, unknown>;
}
function string(value: unknown): string {
  if (typeof value !== 'string') throw new Error('Resposta inválida do servidor.');
  return value;
}
function attention(value: unknown): Attention | null {
  if (value == null) return null;
  const a = object(value);
  return { kind: member(a.kind, attentionKinds), since: timestamp(a.since) };
}
function live(value: unknown): Live | null {
  if (value == null) return null;
  const l = object(value);
  return { state: member(l.state, liveStates), since: l.since == null ? null : timestamp(l.since) };
}
function timestamp(value: unknown): string {
  const result = string(value);
  if (!Number.isFinite(Date.parse(result))) throw new Error('Data inválida na resposta.');
  return result;
}
function member<T extends string>(value: unknown, allowed: readonly T[]): T {
  if (!allowed.includes(value as T)) throw new Error('Valor não reconhecido na resposta do servidor.');
  return value as T;
}
function page<T>(value: unknown, parse: (item: unknown) => T): Page<T> {
  const data = object(value);
  if (!Array.isArray(data.items) || data.complete !== true) throw new Error('Página inválida na resposta.');
  return { items: data.items.map(parse), nextCursor: data.nextCursor == null ? null : string(data.nextCursor), complete: true };
}
function task(value: unknown): AgentTask {
  const data = object(value);
  const parentTaskId=data.parentTaskId==null?null:string(data.parentTaskId);
  if(parentTaskId!==null&&(!parentTaskId||parentTaskId===data.id))throw new Error('Hierarquia inválida na resposta do servidor.');
  let assignment: Assignment | null = null;
  if (data.assignment != null) {
    const a = object(data.assignment);
    assignment = { sessionId: string(a.sessionId), agentId: string(a.agentId), provider: member(a.provider, ['claude', 'codex', 'gemini']), displayName: string(a.displayName), freshness: member(a.freshness, ['fresh', 'stale', 'disconnected']), attention: attention(a.attention), live: live(a.live) };
  }
  if (!Number.isInteger(data.version)) throw new Error('Versão inválida na resposta.');
  let source: AgentTask['source'] = null;
  if (data.source != null) {
    const s = object(data.source);
    source = { provider: member(s.provider, ['personal', 'jira', 'github']), resource: string(s.resource), ...(s.connectionId == null ? {} : { connectionId: string(s.connectionId) }) };
  }
  const status = member(data.status, TASK_STATUSES);
  let hold: Hold | null = null;
  if (data.hold != null) {
    const h = object(data.hold);
    if (!(status in holdReasons)) throw new Error('Motivo inválido na resposta do servidor.');
    hold = { reason: member(h.reason, holdReasons[status as HeldStatus]), note: h.note == null ? null : string(h.note) };
  }
  return { id: string(data.id), parentTaskId, externalId: string(data.externalId), title: string(data.title), description: string(data.description), status, hold, assignment, source, version: data.version as number, createdAt: timestamp(data.createdAt), lastActivityAt: timestamp(data.lastActivityAt) };
}
export function parseSnapshot(value: unknown): Snapshot {
  const data = object(value);
  const tasks = page(data.tasks, task);
  const subtaskProgress: Record<string, SubtaskProgress> = {};
  for (const [parentId, value] of Object.entries(data.subtaskProgress === undefined ? {} : object(data.subtaskProgress))) {
    const p = object(value);
    if (!Number.isInteger(p.total) || !Number.isInteger(p.completed) || (p.completed as number) < 0 || (p.completed as number) > (p.total as number) || !Array.isArray(p.active)) throw new Error('Progresso inválido na resposta do servidor.');
    if (!tasks.items.some(item => item.id === parentId && item.parentTaskId === null)) throw new Error('Hierarquia inválida na resposta do servidor.');
    subtaskProgress[parentId] = { total: p.total as number, completed: p.completed as number, active: p.active.map(item => { const a = object(item); return { id: string(a.id), title: string(a.title), status: member(a.status, TASK_STATUSES) }; }) };
  }
  return { tasks, subtaskProgress, sessions: page(data.sessions, value => {
    const s = object(value);
    const a = object(s.agent);
    const agent = { id: string(a.id), externalId: string(a.externalId), provider: member(a.provider, ['claude', 'codex', 'gemini'] as const), displayName: string(a.displayName), createdAt: timestamp(a.createdAt), lastActivityAt: timestamp(a.lastActivityAt) };
    if (!Number.isInteger(s.version)) throw new Error('Versão inválida na resposta.');
    return { id: string(s.id), externalId: string(s.externalId), agentId: string(s.agentId), version: s.version as number, startedAt: timestamp(s.startedAt), lastActivityAt: timestamp(s.lastActivityAt), agent, freshness: member(s.freshness, ['fresh', 'stale', 'disconnected'] as const), attention: attention(s.attention), live: live(s.live) };
  }) };
}
export function parseTaskDetail(value: unknown): TaskDetail {
  const data = object(value);
  const current=task(data.task);
  const subtasks:Page<AgentTask>=data.subtasks===undefined?{items:[],nextCursor:null,complete:true}:page(data.subtasks,task);
  if(subtasks.items.some(child=>child.parentTaskId!==current.id)||current.parentTaskId!==null&&subtasks.items.length)throw new Error('Hierarquia inválida na resposta do servidor.');
  return { task: current, subtasks, activity: page(data.activity, value => {
    const a = object(value);
    return { id: string(a.id), taskId: string(a.taskId), kind: member(a.kind, ['progress', 'transition', 'created', 'updated'] as const), summary: string(a.summary), receivedAt: timestamp(a.receivedAt), occurredAt: a.occurredAt == null ? null : timestamp(a.occurredAt) };
  }) };
}
const timeFormatter = new Intl.DateTimeFormat('pt-BR', { dateStyle: 'short', timeStyle: 'short' });
export function formatTime(value: string): string {
  return timeFormatter.format(new Date(value));
}
export type TerminalView =
  | { available: true; live: Live; pane: string; response: { content: string; at: string | null } | null; capturedAt: string }
  | { available: false; reason: 'not_enabled' | 'not_local' | 'unavailable' };
export function parseTerminal(value: unknown): TerminalView {
  const data = object(value);
  if (data.available === false) return { available: false, reason: member(data.reason, ['not_enabled', 'not_local', 'unavailable'] as const) };
  if (data.available !== true) throw new Error('Resposta inválida do servidor.');
  const state = live(data.live);
  if (!state) throw new Error('Resposta inválida do servidor.');
  let response: { content: string; at: string | null } | null = null;
  if (data.response != null) { const r = object(data.response); response = { content: string(r.content), at: r.at == null ? null : timestamp(r.at) }; }
  return { available: true, live: state, pane: string(data.pane), response, capturedAt: timestamp(data.capturedAt) };
}
