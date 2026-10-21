import { NextRequest, NextResponse } from 'next/server';
import { requireUser } from '@/lib/api/context';
import { jiraConnectionOf } from '@/lib/jiraPeople';
import { fetchOpenEpics, isJiraProjectKey } from '@/lib/integrations/jiraApi';

/** Os épicos abertos de um projeto, para escolher o pai de uma história. */
export async function GET(request: NextRequest) {
  const auth = await requireUser();
  if (!auth.ok) return auth.response;

  const project = new URL(request.url).searchParams.get('project')?.toUpperCase() ?? '';
  if (!isJiraProjectKey(project)) {
    return NextResponse.json({ error: 'projeto inválido' }, { status: 400 });
  }

  const conn = jiraConnectionOf(auth.value.id);
  if (!conn) return NextResponse.json({ error: 'Jira não conectado' }, { status: 400 });

  try {
    const epics = await fetchOpenEpics(conn, project);
    return NextResponse.json({ epics: epics.map(({ key, summary }) => ({ key, summary })) });
  } catch (err) {
    return NextResponse.json({ error: err instanceof Error ? err.message : String(err) }, { status: 502 });
  }
}
