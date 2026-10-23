import { statuses as TASK_STATUSES } from '@/lib/agents/model';
import type { AgentTask, AgentSession, Assignment, Activity, Page, TaskStatus } from '@/lib/agents/model';
export { TASK_STATUSES };
export type { AgentTask, AgentSession, Assignment, Activity, Page, TaskStatus };
export const STATUS_LABELS: Record<TaskStatus, string> = {
  queued: 'Na fila', working: 'Em andamento', blocked: 'Bloqueadas',
  completed: 'Concluídas', failed: 'Falharam', cancelled: 'Canceladas',
};
export interface Snapshot { tasks: Page<AgentTask>; sessions: Page<AgentSession> }
export interface TaskDetail { task: AgentTask; activity: Page<Activity>; subtasks: Page<AgentTask> }

function object(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error('Resposta inválida do servidor.');
  return value as Record<string, unknown>;
}
function string(value: unknown): string {
  if (typeof value !== 'string') throw new Error('Resposta inválida do servidor.');
  return value;
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
    assignment = { sessionId: string(a.sessionId), agentId: string(a.agentId), provider: member(a.provider, ['claude', 'codex', 'gemini']), displayName: string(a.displayName), freshness: member(a.freshness, ['fresh', 'stale', 'disconnected']) };
  }
  if (!Number.isInteger(data.version)) throw new Error('Versão inválida na resposta.');
  let source: AgentTask['source'] = null;
  if (data.source != null) {
    const s = object(data.source);
    source = { provider: member(s.provider, ['personal', 'jira', 'github']), resource: string(s.resource), ...(s.connectionId == null ? {} : { connectionId: string(s.connectionId) }) };
  }
  return { id: string(data.id), parentTaskId, externalId: string(data.externalId), title: string(data.title), description: string(data.description), status: member(data.status, TASK_STATUSES), assignment, source, version: data.version as number, createdAt: timestamp(data.createdAt), lastActivityAt: timestamp(data.lastActivityAt) };
}
export function parseSnapshot(value: unknown): Snapshot {
  const data = object(value);
  return { tasks: page(data.tasks, task), sessions: page(data.sessions, value => {
    const s = object(value);
    const a = object(s.agent);
    const agent = { id: string(a.id), externalId: string(a.externalId), provider: member(a.provider, ['claude', 'codex', 'gemini'] as const), displayName: string(a.displayName), createdAt: timestamp(a.createdAt), lastActivityAt: timestamp(a.lastActivityAt) };
    if (!Number.isInteger(s.version)) throw new Error('Versão inválida na resposta.');
    return { id: string(s.id), externalId: string(s.externalId), agentId: string(s.agentId), version: s.version as number, startedAt: timestamp(s.startedAt), lastActivityAt: timestamp(s.lastActivityAt), agent, freshness: member(s.freshness, ['fresh', 'stale', 'disconnected'] as const) };
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
