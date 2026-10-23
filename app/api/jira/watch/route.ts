import { AccessError } from '@/lib/access/principal';
import { jiraActions } from '@/lib/operations/jira';
import { NextRequest, NextResponse } from 'next/server';
import { requireUser } from '@/lib/api/context';
import { isJiraKey } from '@/lib/preferences';
import { refreshAll } from '@/lib/refresher';

/** Acrescenta uma issue à lista de acompanhamento. */
export async function POST(request: NextRequest) {
  const auth = await requireUser();
  if (!auth.ok) return auth.response;

  const body = await request.json().catch(() => null);
  if (!isJiraKey(body?.key)) {
    return NextResponse.json(
      { error: 'chave inválida — use o formato ABC-123' },
      { status: 400 },
    );
  }

  try {
    jiraActions.watch(auth.value.id, String(body.key).toUpperCase(), 'watch');
  } catch(error) {
    if(error instanceof AccessError) return NextResponse.json({error: error.message}, {status: error.status});
    throw error;
  }
  return NextResponse.json(await refreshAll(auth.value.id));
}

export async function DELETE(request: NextRequest) {
  const auth = await requireUser();
  if (!auth.ok) return auth.response;

  const body = await request.json().catch(() => null);
  if (!isJiraKey(body?.key)) {
    return NextResponse.json({ error: 'chave inválida' }, { status: 400 });
  }

  try {
    jiraActions.watch(auth.value.id, String(body.key).toUpperCase(), 'unwatch');
  } catch(error) {
    if(error instanceof AccessError) return NextResponse.json({error: error.message}, {status: error.status});
    throw error;
  }
  return NextResponse.json(await refreshAll(auth.value.id));
}
