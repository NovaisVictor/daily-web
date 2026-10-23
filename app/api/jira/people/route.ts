import { AccessError } from '@/lib/access/principal';
import { jiraActions } from '@/lib/operations/jira';
import { NextRequest, NextResponse } from 'next/server';
import { requireUser } from '@/lib/api/context';
import { isJiraAccountId } from '@/lib/preferences';
import { jiraConnectionOf } from '@/lib/jiraPeople';

export async function POST(request: NextRequest) {
  const auth = await requireUser();
  if (!auth.ok) return auth.response;

  const body = await request.json().catch(() => null);
  const accountId = body?.accountId;
  if (!isJiraAccountId(accountId)) {
    return NextResponse.json({ error: 'conta do Jira inválida' }, { status: 400 });
  }

  const conn = jiraConnectionOf(auth.value.id);
  if (!conn) {
    return NextResponse.json({ error: 'Jira não conectado' }, { status: 400 });
  }

  try {
    const people = await jiraActions.followPerson({userId: auth.value.id, connection: conn}, accountId);
    return NextResponse.json({people});
  } catch (err) {
    return NextResponse.json({error: err instanceof Error ? err.message : String(err)}, {status: err instanceof AccessError ? err.status : 502});
  }
}

export async function DELETE(request: NextRequest) {
  const auth = await requireUser();
  if (!auth.ok) return auth.response;

  const body = await request.json().catch(() => null);
  const accountId = body?.accountId;
  if (!isJiraAccountId(accountId)) {
    return NextResponse.json({ error: 'conta do Jira inválida' }, { status: 400 });
  }

  return NextResponse.json({people: jiraActions.setPerson(auth.value.id, accountId, null)});
}
