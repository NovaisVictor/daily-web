import { NextRequest, NextResponse } from 'next/server';
import { requireUser } from '@/lib/api/context';
import { isJiraKey } from '@/lib/jiraKey';
import { jiraConnectionOf } from '@/lib/jiraPeople';
import { isCalendarDate, setStartDate, suggestStartDate } from '@/lib/integrations/jiraApi';
import { resolveJiraProblem } from '@/lib/refresher';

type Params = { params: Promise<{ key: string }> };

/** A data que o histórico sugere, para a tela mostrar antes de gravar. */
export async function GET(_request: NextRequest, { params }: Params) {
  const auth = await requireUser();
  if (!auth.ok) return auth.response;

  const { key: raw } = await params;
  if (!isJiraKey(raw)) return NextResponse.json({ error: 'chave inválida' }, { status: 400 });
  const key = raw.toUpperCase();

  const conn = jiraConnectionOf(auth.value.id);
  if (!conn) return NextResponse.json({ error: 'Jira não conectado' }, { status: 400 });

  try {
    return NextResponse.json({ date: await suggestStartDate(conn, key) });
  } catch (err) {
    return NextResponse.json({ error: err instanceof Error ? err.message : String(err) }, { status: 502 });
  }
}

export async function PUT(request: NextRequest, { params }: Params) {
  const auth = await requireUser();
  if (!auth.ok) return auth.response;

  const { key: raw } = await params;
  if (!isJiraKey(raw)) return NextResponse.json({ error: 'chave inválida' }, { status: 400 });
  const key = raw.toUpperCase();

  const body = await request.json().catch(() => null);
  if (!isCalendarDate(body?.date)) {
    return NextResponse.json({ error: 'data inválida — use AAAA-MM-DD' }, { status: 400 });
  }

  const conn = jiraConnectionOf(auth.value.id);
  if (!conn) return NextResponse.json({ error: 'Jira não conectado' }, { status: 400 });

  try {
    await setStartDate(conn, key, body.date);
    resolveJiraProblem(auth.value.id, key, ['story-in-progress-without-start', 'story-done-without-start']);
    return NextResponse.json({ ok: true });
  } catch (err) {
    return NextResponse.json({ error: err instanceof Error ? err.message : String(err) }, { status: 502 });
  }
}
