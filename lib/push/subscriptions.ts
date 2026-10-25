import { randomUUID } from 'node:crypto';
import { getDb } from '@/lib/db';
import { AccessError } from '@/lib/access/principal';
import * as schema from '@/lib/agents/schemas';

// The server POSTs to whatever endpoint a browser hands it, so only the push
// services of the major browsers are accepted: anything else would let a
// caller aim this server at an arbitrary URL.
const PUSH_HOSTS = ['fcm.googleapis.com', 'updates.push.services.mozilla.com', 'web.push.apple.com', 'notify.windows.com'];
const KEY = /^[A-Za-z0-9_-]+={0,2}$/;

export interface Subscription { id: string; endpoint: string; p256dh: string; auth: string }

export function pushEndpoint(value: unknown): string {
  if (typeof value !== 'string' || value.length > 1024) throw new AccessError(400, 'invalid_endpoint', 'Invalid push endpoint');
  let url: URL;
  try { url = new URL(value); } catch { throw new AccessError(400, 'invalid_endpoint', 'Invalid push endpoint'); }
  const host = url.hostname.toLowerCase();
  if (url.protocol !== 'https:' || url.username || url.password || url.port || !PUSH_HOSTS.some(allowed => host === allowed || host.endsWith('.' + allowed))) throw new AccessError(400, 'invalid_endpoint', 'Unsupported push service');
  return url.toString();
}

function key(value: unknown, name: string, min: number, max: number): string {
  if (typeof value !== 'string' || value.length < min || value.length > max || !KEY.test(value)) throw new AccessError(400, 'invalid_subscription', `Invalid ${name}`);
  return value;
}

export function saveSubscription(userId: string, input: unknown): { id: string } {
  const data = schema.object(input, ['endpoint', 'keys', 'expirationTime']);
  const endpoint = pushEndpoint(data.endpoint);
  const keys = schema.object(data.keys, ['p256dh', 'auth']);
  const p256dh = key(keys.p256dh, 'p256dh', 80, 100), auth = key(keys.auth, 'auth', 16, 32);
  const at = new Date().toISOString();
  // The same browser can be signed in as another user later: the endpoint follows whoever subscribed last.
  getDb().prepare(`INSERT INTO main.tb_push_subscription (uid_subscription,uid_user,txt_endpoint,txt_p256dh,txt_auth,tsz_insert,tsz_update) VALUES (?,?,?,?,?,?,?)
    ON CONFLICT(txt_endpoint) DO UPDATE SET uid_user=excluded.uid_user,txt_p256dh=excluded.txt_p256dh,txt_auth=excluded.txt_auth,tsz_update=excluded.tsz_update`).run(randomUUID(), userId, endpoint, p256dh, auth, at, at);
  const row = getDb().prepare(`SELECT uid_subscription AS id FROM main.tb_push_subscription WHERE txt_endpoint=?`).get(endpoint) as { id: string };
  return { id: row.id };
}

export function removeSubscription(userId: string, input: unknown): void {
  const data = schema.object(input, ['endpoint']);
  getDb().prepare(`DELETE FROM main.tb_push_subscription WHERE uid_user=? AND txt_endpoint=?`).run(userId, pushEndpoint(data.endpoint));
}

export function subscriptionsOf(userId: string): Subscription[] {
  return getDb().prepare(`SELECT uid_subscription AS id,txt_endpoint AS endpoint,txt_p256dh AS p256dh,txt_auth AS auth FROM main.tb_push_subscription WHERE uid_user=? ORDER BY tsz_insert LIMIT 20`).all(userId) as Subscription[];
}

export function forgetSubscription(id: string): void {
  getDb().prepare(`DELETE FROM main.tb_push_subscription WHERE uid_subscription=?`).run(id);
}
