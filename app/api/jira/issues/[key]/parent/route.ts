import { NextRequest, NextResponse } from 'next/server';
import { requireUser } from '@/lib/api/context';
import { isJiraKey } from '@/lib/jiraKey';
import { jiraConnectionOf } from '@/lib/jiraPeople';
import { setEpic } from '@/lib/integrations/jiraApi';
import { resolveJiraProblem } from '@/lib/refresher';

/** Põe a história sob um épico. */
export async function PUT(request: NextRequest, { params }: { params: Promise<{ key: string }> }) {
  const auth = await requireUser();
  if (!auth.ok) return auth.response;

  const { key: raw } = await params;
  const body = await request.json().catch(() => null);
  if (!isJiraKey(raw) || !isJiraKey(body?.epic)) {
    return NextResponse.json({ error: 'chave inválida' }, { status: 400 });
  }
  const key = raw.toUpperCase();
  const epic = String(body.epic).toUpperCase();

  const conn = jiraConnectionOf(auth.value.id);
  if (!conn) return NextResponse.json({ error: 'Jira não conectado' }, { status: 400 });

  try {
    await setEpic(conn, key, epic);
    resolveJiraProblem(auth.value.id, key, ['story-without-epic']);
    // O épico ganhou a história que faltava a ele.
    resolveJiraProblem(auth.value.id, epic, ['epic-without-stories']);
    return NextResponse.json({ ok: true });
  } catch (err) {
    return NextResponse.json({ error: err instanceof Error ? err.message : String(err) }, { status: 502 });
  }
}
