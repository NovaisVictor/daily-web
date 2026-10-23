import { jiraActions } from '@/lib/operations/jira';
import { NextRequest, NextResponse } from 'next/server';
import { requireUser } from '@/lib/api/context';
import { isJiraAccountId, jiraFollowedPeople } from '@/lib/preferences';
import { jiraConnectionOf } from '@/lib/jiraPeople';

export async function GET(request: NextRequest, { params }: { params: Promise<{ accountId: string }> }) {
  const auth = await requireUser();
  if (!auth.ok) return auth.response;

  const { accountId } = await params;

  if (!isJiraAccountId(accountId)) {
    return NextResponse.json({ error: 'conta do Jira inválida' }, { status: 400 });
  }

  const followed = jiraFollowedPeople(auth.value.id);
  if (!followed.some((p) => p.accountId === accountId)) {
    return NextResponse.json({ error: 'pessoa não acompanhada' }, { status: 404 });
  }

  const conn = jiraConnectionOf(auth.value.id);
  if (!conn) {
    return NextResponse.json({ error: 'Jira não conectado' }, { status: 400 });
  }

  try {
    const view = await jiraActions.personView(conn, accountId);
    return NextResponse.json(view);
  } catch (err) {
    return NextResponse.json(
      { error: err instanceof Error ? err.message : String(err) },
      { status: 502 }
    );
  }
}
