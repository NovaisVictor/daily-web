import { jiraActions } from '@/lib/operations/jira';
import { NextRequest, NextResponse } from 'next/server';
import { upstreamError } from '@/lib/api/context';
import { invalidKey, issueKeyParam, requireJira, writeDone } from '@/lib/api/jira';
import { InvalidEdit, parseNewStory } from '@/lib/integrations/jira/edits';
import { SUMMARY_MAX } from '@/lib/jiraLimits';

type Params = { params: Promise<{ key: string }> };

export async function POST(request: NextRequest, { params }: Params) {
  const auth = await requireJira();
  if (!auth.ok) return auth.response;
  const key = issueKeyParam((await params).key);
  if (!key) return invalidKey();

  const story = parseNewStory(await request.json().catch(() => null));
  if (!story) {
    return NextResponse.json({ error: `resumo obrigatório, até ${SUMMARY_MAX} caracteres` }, { status: 400 });
  }

  let created: { key: string; url: string };
  try {
    created = await jiraActions.createStory({userId: auth.value.user.id, connection: auth.value.connection}, key, story);
  } catch (err) {
    if (err instanceof InvalidEdit) return NextResponse.json({ error: err.message }, { status: 400 });
    return upstreamError(err);
  }
  return writeDone(auth.value.user.id, created);
}
