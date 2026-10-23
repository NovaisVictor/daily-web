import { jiraActions } from '@/lib/operations/jira';
import { NextRequest, NextResponse } from 'next/server';
import { requireUser } from '@/lib/api/context';
import { isJiraKey } from '@/lib/jiraKey';
import { jiraConnectionOf } from '@/lib/jiraPeople';

/** Põe a história sob um épico. */
export async function PUT(request: NextRequest, { params }: { params: Promise<{ key: string }> }) {
  const auth = await requireUser();
  if (!auth.ok) return auth.response;

  const [{key: raw}, body] = await Promise.all([params, request.json().catch(() => null)]);
  if (!isJiraKey(raw) || !isJiraKey(body?.epic)) {
    return NextResponse.json({ error: 'chave inválida' }, { status: 400 });
  }
  const key = raw.toUpperCase();
  const epic = String(body.epic).toUpperCase();

  const conn = jiraConnectionOf(auth.value.id);
  if (!conn) return NextResponse.json({ error: 'Jira não conectado' }, { status: 400 });

  try {
    await jiraActions.parent({userId: auth.value.id, connection: conn}, key, epic);
    return NextResponse.json({ ok: true });
  } catch (err) {
    return NextResponse.json({ error: err instanceof Error ? err.message : String(err) }, { status: 502 });
  }
}
