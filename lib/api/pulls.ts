import { NextResponse } from 'next/server';
import { requireUser, type ConnectionContext, type Guard } from '@/lib/api/context';
import { isValidRepo } from '@/lib/api/validation';
import { enabledModules, listConnections } from '@/lib/vault/connections';
import { invalidate } from '@/lib/refresher';
import { TEXT_MAX, type PullRef } from '@/lib/integrations/github/actions';

const NUMBER_MAX = 1_000_000_000;

/** The session and its own GitHub connection: writes always use the token of
 *  whoever is logged in, never another user's. */
export async function requirePulls(): Promise<Guard<ConnectionContext>> {
  const auth = await requireUser();
  if (!auth.ok) return auth;
  const connection = enabledModules(auth.value.id).includes('pulls')
    ? (listConnections(auth.value.id, 'pulls')[0] ?? null)
    : null;
  if (!connection) {
    return { ok: false, response: NextResponse.json({ error: 'GitHub não conectado' }, { status: 400 }) };
  }
  return { ok: true, value: { user: auth.value, connection } };
}

/** The route segments, validated: they go into a GitHub API path. */
export function pullParams(owner: unknown, name: unknown, number: unknown): PullRef | null {
  if (typeof owner !== 'string' || typeof name !== 'string') return null;
  if (!isValidRepo(`${owner}/${name}`)) return null;
  // "." and ".." pass the repo pattern but a URL parser would resolve them.
  if ([owner, name].some((segment) => /^\.+$/.test(segment))) return null;
  if (typeof number !== 'string' || !/^[1-9]\d{0,9}$/.test(number)) return null;
  const parsed = Number(number);
  if (parsed > NUMBER_MAX) return null;
  return { owner, repo: name, number: parsed };
}

export function invalidPull(): NextResponse {
  return NextResponse.json({ error: 'PR inválido — use dono/repositório e um número' }, { status: 400 });
}

export function badRequest(error: string): NextResponse {
  return NextResponse.json({ error }, { status: 400 });
}

export async function jsonObject(request: Request): Promise<Record<string, unknown> | null> {
  const payload: unknown = await request.json().catch(() => null);
  if (typeof payload !== 'object' || payload === null || Array.isArray(payload)) return null;
  return payload as Record<string, unknown>;
}

export function pullsWriteDone(userId: string, payload: Record<string, unknown> = {}): NextResponse {
  invalidate(userId);
  return NextResponse.json({ ok: true, ...payload });
}

export type TextField = { kind: 'text'; value: string } | { kind: 'empty' } | { kind: 'invalid' };

/** A free-text field, trimmed. Missing, null and blank are `empty`; a
 *  non-string or a text over the limit is `invalid`. */
export function textField(value: unknown): TextField {
  if (value === undefined || value === null) return { kind: 'empty' };
  if (typeof value !== 'string') return { kind: 'invalid' };
  const trimmed = value.trim();
  if (trimmed === '') return { kind: 'empty' };
  if (trimmed.length > TEXT_MAX) return { kind: 'invalid' };
  return { kind: 'text', value: trimmed };
}
