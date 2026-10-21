import { NextRequest, NextResponse } from 'next/server';
import { upstreamError } from '@/lib/api/context';
import { invalidKey, issueKeyParam, requireJira } from '@/lib/api/jira';
import { fetchTransitions } from '@/lib/integrations/jira/transitions';
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
