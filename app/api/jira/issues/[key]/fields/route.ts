import { NextRequest, NextResponse } from 'next/server';
import { upstreamError } from '@/lib/api/context';
import { invalidKey, issueKeyParam, requireJira, writeDone } from '@/lib/api/jira';
import { applyEdit, fetchPriorityOptions, InvalidEdit, parseEditChange } from '@/lib/integrations/jira/edits';

type Params = { params: Promise<{ key: string }> };

export async function GET(request: NextRequest, { params }: Params) {
  const auth = await requireJira();
  if (!auth.ok) return auth.response;
  const key = issueKeyParam((await params).key);
  if (!key) return invalidKey();
  if (request.nextUrl.searchParams.get('options') !== 'priority') {
    return NextResponse.json({ error: 'opções inválidas — use options=priority' }, { status: 400 });
  }

  try {
    return NextResponse.json(await fetchPriorityOptions(auth.value.connection, key));
  } catch (err) {
    return upstreamError(err);
  }
}

export async function PUT(request: NextRequest, { params }: Params) {
  const auth = await requireJira();
  if (!auth.ok) return auth.response;
  const key = issueKeyParam((await params).key);
  if (!key) return invalidKey();

  const edit = parseEditChange(await request.json().catch(() => null));
  if (!edit) return NextResponse.json({ error: 'alteração inválida' }, { status: 400 });

  try {
    await applyEdit(auth.value.connection, key, edit);
  } catch (err) {
    if (err instanceof InvalidEdit) return NextResponse.json({ error: err.message }, { status: 400 });
    return upstreamError(err);
  }
  return writeDone(auth.value.user.id);
}
