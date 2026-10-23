import { jiraActions } from '@/lib/operations/jira';
import { NextRequest, NextResponse } from 'next/server';
import { requireUser } from '@/lib/api/context';
import { jiraConnectionOf } from '@/lib/jiraPeople';

export async function GET(request: NextRequest) {
  const auth = await requireUser();
  if (!auth.ok) return auth.response;

  const url = new URL(request.url);
  let q = url.searchParams.get('q') || '';
  q = q.trim();
  
  if (q.length < 2) {
    return NextResponse.json({ people: [] });
  }
  
  q = q.slice(0, 100);

  const conn = jiraConnectionOf(auth.value.id);
  if (!conn) {
    return NextResponse.json({ error: 'Jira não conectado' }, { status: 400 });
  }

  try {
    const people = await jiraActions.searchPeople(conn, q);
    return NextResponse.json({ people });
  } catch (err) {
    return NextResponse.json(
      { error: err instanceof Error ? err.message : String(err) },
      { status: 502 }
    );
  }
}
