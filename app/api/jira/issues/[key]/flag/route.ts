import { jiraActions } from '@/lib/operations/jira';
import { NextRequest, NextResponse } from 'next/server';
import { upstreamError } from '@/lib/api/context';
import { invalidKey, issueKeyParam, requireJira, writeDone } from '@/lib/api/jira';
import { FlagCommentFailed, type FlagChange } from '@/lib/integrations/jira/flag';
import { FLAG_REASON_MAX } from '@/lib/jiraLimits';

type Params = { params: Promise<{ key: string }> };

type Parsed = { ok: true; change: FlagChange } | { ok: false; error: string };

function text(value: unknown): string | null {
  if (typeof value !== 'string') return null;
  const trimmed = value.trim();
  return trimmed.length > 0 && trimmed.length <= FLAG_REASON_MAX ? trimmed : null;
}

function parseChange(body: unknown): Parsed {
  if (typeof body !== 'object' || body === null || Array.isArray(body)) return { ok: false, error: 'corpo inválido' };
  const { action, reason, note } = body as Record<string, unknown>;
  if (action === 'flag') {
    const valid = text(reason);
    if (!valid) return { ok: false, error: `o motivo é obrigatório (até ${FLAG_REASON_MAX} caracteres)` };
    return { ok: true, change: { action, reason: valid } };
  }
  if (action === 'unflag') {
    if (note === undefined || (typeof note === 'string' && note.trim() === '')) {
      return { ok: true, change: { action, note: null } };
    }
    const valid = text(note);
    if (!valid) return { ok: false, error: `observação inválida (texto de até ${FLAG_REASON_MAX} caracteres)` };
    return { ok: true, change: { action, note: valid } };
  }
  return { ok: false, error: 'action deve ser flag ou unflag' };
}

export async function POST(request: NextRequest, { params }: Params) {
  const guard = await requireJira();
  if (!guard.ok) return guard.response;
  const key = issueKeyParam((await params).key);
  if (!key) return invalidKey();

  const parsed = parseChange(await request.json().catch(() => null));
  if (!parsed.ok) return NextResponse.json({ error: parsed.error }, { status: 400 });

  try {
    await jiraActions.flag({userId: guard.value.user.id, connection: guard.value.connection}, key, parsed.change);
  } catch (err) {
    if (err instanceof FlagCommentFailed) return writeDone(guard.value.user.id, { warning: err.message });
    return upstreamError(err);
  }
  return writeDone(guard.value.user.id);
}
