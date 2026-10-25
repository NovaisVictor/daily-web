import webpush, { WebPushError } from 'web-push';
import { getDb } from '@/lib/db';
import { getSession, listTasks } from '@/lib/agents/operations';
import { deckEnabled, liveFor } from '@/lib/agents/deck';
import type { Attention } from '@/lib/agents/model';
import { forgetSubscription, subscriptionsOf } from './subscriptions';
import type { AttentionCheck, PushPayload } from './events';

const BATCH = 20;
const MAX_ATTEMPTS = 5;
const SEND_TIMEOUT_MS = 10_000;
const INTERVAL_MS = 5_000;
const PENDING_MAX_AGE_MS = 24 * 60 * 60 * 1000;
const RESOLVED_RETENTION_MS = 7 * 24 * 60 * 60 * 1000;
const OPEN = ['queued', 'working', 'waiting', 'blocked'];

interface Vapid { publicKey: string; privateKey: string; subject: string }
export function vapid(): Vapid | null {
  const publicKey = process.env.DAILY_WEB_VAPID_PUBLIC_KEY?.trim(), privateKey = process.env.DAILY_WEB_VAPID_PRIVATE_KEY?.trim();
  const subject = process.env.DAILY_WEB_VAPID_SUBJECT?.trim() || process.env.PUBLIC_ORIGIN?.trim();
  return publicKey && privateKey && subject ? { publicKey, privateKey, subject } : null;
}

interface Row { id: string; userId: string; kind: string; session: string | null; payload: string; attempts: number }
type Shared = typeof globalThis & { __pushDraining?: boolean; __pushKick?: () => void; __pushTimer?: ReturnType<typeof setInterval> };
const shared = globalThis as Shared;

function resolve(id: string, state: 'sent' | 'dropped' | 'failed'): void {
  getDb().prepare(`UPDATE main.tb_push_outbox SET typ_state=?,tsz_resolved=? WHERE uid_event=?`).run(state, new Date().toISOString(), id);
}

// An attention signal only becomes a notification if it still stands when it
// is due and the evidence agrees the agent is waiting for the user, using the
// same rules as the board's "waiting for you" badge.
async function attentionPayload(row: Row): Promise<PushPayload | null> {
  const stored = (JSON.parse(row.payload) as AttentionCheck).attention;
  let session;
  try { session = getSession(row.userId, row.session ?? ''); } catch { return null; }
  const current: Attention | null = session.attention;
  if (!current || current.kind !== stored.kind || current.since !== stored.since) return null;
  const open = listTasks(row.userId, { sessionId: session.id, limit: 100 }).items.filter(task => OPEN.includes(task.status));
  if (open.length === 0) return null;
  if (current.kind === 'input') {
    if (open.every(task => task.status === 'waiting')) return null;
    if (deckEnabled(row.userId)) {
      const live = (await liveFor(row.userId, [{ id: session.id, externalId: session.externalId, provider: session.agent.provider }], true)).get(session.id);
      if (live && live.state !== 'idle' && live.state !== 'prompt') return null;
    }
  }
  const task = open.find(item => item.parentTaskId === null) ?? open[0];
  const agent = session.agent.displayName;
  return current.kind === 'permission'
    ? { title: `Pedindo permissão: ${task.title}`.slice(0, 120), body: `${agent} está esperando você aprovar uma ação.`, url: `/agents/tasks/${encodeURIComponent(task.id)}`, tag: `session-${session.id}` }
    : { title: `Aguardando sua resposta: ${task.title}`.slice(0, 120), body: `${agent} parou e está esperando você.`, url: `/agents/tasks/${encodeURIComponent(task.id)}`, tag: `session-${session.id}` };
}

async function deliver(row: Row, keys: Vapid): Promise<void> {
  const payload = row.kind === 'attention' ? await attentionPayload(row) : JSON.parse(row.payload) as PushPayload;
  if (!payload) return resolve(row.id, 'dropped');
  const subscriptions = subscriptionsOf(row.userId);
  if (subscriptions.length === 0) return resolve(row.id, 'dropped');
  let delivered = 0, transient = 0;
  for (const subscription of subscriptions) {
    try {
      await webpush.sendNotification({ endpoint: subscription.endpoint, keys: { p256dh: subscription.p256dh, auth: subscription.auth } }, JSON.stringify(payload), { vapidDetails: keys, TTL: 3600, urgency: 'high', timeout: SEND_TIMEOUT_MS });
      delivered += 1;
    } catch (error) {
      if (error instanceof WebPushError && (error.statusCode === 404 || error.statusCode === 410)) forgetSubscription(subscription.id);
      else transient += 1;
    }
  }
  if (delivered > 0) return resolve(row.id, 'sent');
  if (transient === 0) return resolve(row.id, 'dropped');
  const attempts = row.attempts + 1;
  if (attempts >= MAX_ATTEMPTS) return resolve(row.id, 'failed');
  getDb().prepare(`UPDATE main.tb_push_outbox SET num_attempts=?,tsz_due=? WHERE uid_event=?`).run(attempts, new Date(Date.now() + 30_000 * 2 ** attempts).toISOString(), row.id);
}

export async function drainPush(): Promise<void> {
  if (shared.__pushDraining) return;
  shared.__pushDraining = true;
  try {
    const now = Date.now();
    getDb().prepare(`DELETE FROM main.tb_push_outbox WHERE typ_state<>'pending' AND tsz_resolved<?`).run(new Date(now - RESOLVED_RETENTION_MS).toISOString());
    getDb().prepare(`UPDATE main.tb_push_outbox SET typ_state='dropped',tsz_resolved=? WHERE typ_state='pending' AND tsz_due<?`).run(new Date(now).toISOString(), new Date(now - PENDING_MAX_AGE_MS).toISOString());
    const keys = vapid();
    const rows = getDb().prepare(`SELECT uid_event AS id,uid_user AS userId,typ_kind AS kind,ref_session AS session,jsn_payload AS payload,num_attempts AS attempts FROM main.tb_push_outbox WHERE typ_state='pending' AND tsz_due<=? ORDER BY tsz_due LIMIT ?`).all(new Date(now).toISOString(), BATCH) as Row[];
    for (const row of rows) {
      if (!keys) { resolve(row.id, 'dropped'); continue; }
      try { await deliver(row, keys); } catch { console.warn('[push] event could not be delivered'); resolve(row.id, 'failed'); }
    }
  } finally { shared.__pushDraining = false; }
}

export function startPushDispatcher(): void {
  shared.__pushKick = () => { void drainPush(); };
  if (shared.__pushTimer) return;
  shared.__pushTimer = setInterval(() => { void drainPush(); }, INTERVAL_MS);
  shared.__pushTimer.unref?.();
}
