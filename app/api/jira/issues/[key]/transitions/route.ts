import { NextRequest, NextResponse } from 'next/server';
import { upstreamError } from '@/lib/api/context';
import { invalidKey, issueKeyParam, requireJira, writeDone } from '@/lib/api/jira';
import { applyTransition, fetchTransitions, TransitionUnavailable } from '@/lib/integrations/jira/transitions';

type Params = { params: Promise<{ key: string }> };

export async function GET(_request: NextRequest, { params }: Params) {
  const auth = await requireJira();
  if (!auth.ok) return auth.response;
  const key = issueKeyParam((await params).key);
  if (!key) return invalidKey();

  try {
    return NextResponse.json({ transitions: await fetchTransitions(auth.value.connection, key) });
  } catch (err) {
    return upstreamError(err);
  }
}

function transitionIdOf(body: unknown): string | null {
  if (typeof body !== 'object' || body === null) return null;
  const { transitionId } = body as { transitionId?: unknown };
  return typeof transitionId === 'string' && /^\d{1,10}$/.test(transitionId) ? transitionId : null;
}

export async function POST(request: NextRequest, { params }: Params) {
  const auth = await requireJira();
  if (!auth.ok) return auth.response;
  const key = issueKeyParam((await params).key);
  if (!key) return invalidKey();

  const transitionId = transitionIdOf(await request.json().catch(() => null));
  if (!transitionId) return NextResponse.json({ error: 'transição inválida' }, { status: 400 });

  try {
    await applyTransition(auth.value.connection, key, transitionId);
  } catch (err) {
    if (err instanceof TransitionUnavailable) {
      return NextResponse.json({ error: err.message }, { status: 409 });
    }
    return upstreamError(err);
  }
  return writeDone(auth.value.user.id);
}
