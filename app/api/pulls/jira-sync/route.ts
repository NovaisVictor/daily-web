import { NextRequest, NextResponse } from 'next/server';
import { upstreamError } from '@/lib/api/context';
import { invalidKey, issueKeyParam, requireJira, writeDone } from '@/lib/api/jira';
import { applyTransition, fetchTransitions, TransitionUnavailable } from '@/lib/integrations/jira/transitions';
import { INTENT_LABEL, pickTransition, syncIntentOf } from '@/lib/pullJiraSync';

export async function GET(request: NextRequest) {
  const auth = await requireJira();
  if (!auth.ok) return auth.response;
  const params = request.nextUrl.searchParams;
  const key = issueKeyParam(params.get('key'));
  if (!key) return invalidKey();
  const intent = syncIntentOf(params.get('intent'));
  if (!intent) return NextResponse.json({ error: 'intenção inválida' }, { status: 400 });

  try {
    const transition = pickTransition(await fetchTransitions(auth.value.connection, key), intent);
    if (!transition) {
      return NextResponse.json(
        { error: `nenhuma transição para ${INTENT_LABEL[intent]} disponível — abrir no Jira` },
        { status: 404 },
      );
    }
    return NextResponse.json({ transition });
  } catch (err) {
    return upstreamError(err);
  }
}

function bodyOf(body: unknown): { key: string; transitionId: string } | null {
  if (typeof body !== 'object' || body === null) return null;
  const { key, transitionId } = body as { key?: unknown; transitionId?: unknown };
  const issue = issueKeyParam(key);
  if (!issue || typeof transitionId !== 'string' || !/^\d{1,10}$/.test(transitionId)) return null;
  return { key: issue, transitionId };
}

export async function POST(request: NextRequest) {
  const auth = await requireJira();
  if (!auth.ok) return auth.response;
  const body = bodyOf(await request.json().catch(() => null));
  if (!body) return NextResponse.json({ error: 'chave ou transição inválida' }, { status: 400 });

  try {
    await applyTransition(auth.value.connection, body.key, body.transitionId);
  } catch (err) {
    if (err instanceof TransitionUnavailable) {
      return NextResponse.json({ error: err.message }, { status: 409 });
    }
    return upstreamError(err);
  }
  return writeDone(auth.value.user.id);
}
