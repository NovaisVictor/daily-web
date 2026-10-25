import { randomUUID } from 'node:crypto';
import { getDb } from '@/lib/db';
import { HOLD_LABELS } from '@/components/agents/contracts';
import type { AgentTask, Attention } from '@/lib/agents/model';

export interface PushPayload { title: string; body: string; url: string; tag: string }
export interface AttentionCheck { attention: Attention }

// An idle signal is held back so a short pause (the agent waiting a few seconds
// for a command) is re-checked before it becomes a notification.
export const INPUT_GRACE_MS = 30_000;

const NEEDS_YOU = ['decision', 'access', 'credential'];
const short = (value: string, max: number) => value.length > max ? value.slice(0, max - 1) + '…' : value;

// Runs inside the caller's transaction, so the event exists only if the change that caused it does.
function enqueue(userId: string, kind: 'finished' | 'blocked' | 'attention' | 'test', refs: { task?: string; session?: string }, payload: PushPayload | AttentionCheck, delayMs = 0): void {
  const now = Date.now();
  getDb().prepare(`INSERT INTO main.tb_push_outbox (uid_event,uid_user,typ_kind,ref_task,ref_session,jsn_payload,tsz_due,tsz_insert) VALUES (?,?,?,?,?,?,?,?)`)
    .run(randomUUID(), userId, kind, refs.task ?? null, refs.session ?? null, JSON.stringify(payload), new Date(now + delayMs).toISOString(), new Date(now).toISOString());
  const kick = (globalThis as { __pushKick?: () => void }).__pushKick;
  if (kick && delayMs === 0) setTimeout(kick, 0);
}

export function taskEvent(userId: string, before: AgentTask, after: AgentTask): void {
  const agent = after.assignment?.displayName ?? 'O agente';
  const url = `/agents/tasks/${encodeURIComponent(after.id)}`;
  if (after.parentTaskId === null && before.status !== after.status && (after.status === 'completed' || after.status === 'failed')) {
    const done = after.status === 'completed';
    enqueue(userId, 'finished', { task: after.id }, { title: short(`${done ? 'Concluída' : 'Falhou'}: ${after.title}`, 120), body: done ? `${agent} terminou a tarefa.` : `${agent} marcou a tarefa como falha.`, url, tag: `task-${after.id}` });
    return;
  }
  if (after.status === 'blocked' && after.hold && NEEDS_YOU.includes(after.hold.reason) && (before.status !== 'blocked' || before.hold?.reason !== after.hold.reason || before.hold?.note !== after.hold.note)) {
    const reason = HOLD_LABELS.blocked[after.hold.reason] ?? after.hold.reason;
    enqueue(userId, 'blocked', { task: after.id }, { title: short(`Precisa de você: ${after.title}`, 120), body: short(after.hold.note ? `${reason} — ${after.hold.note}` : `${reason}.`, 200), url, tag: `task-${after.id}` });
  }
}

export function attentionEvent(userId: string, sessionId: string, before: Attention | null, after: Attention | null): void {
  if (!after || (before && before.kind === after.kind)) return;
  enqueue(userId, 'attention', { session: sessionId }, { attention: after }, after.kind === 'input' ? INPUT_GRACE_MS : 0);
}

export function testEvent(userId: string): void {
  enqueue(userId, 'test', {}, { title: 'Avisos ativados', body: 'É assim que os agentes vão te avisar quando terminarem ou precisarem de você.', url: '/', tag: 'test' });
}
