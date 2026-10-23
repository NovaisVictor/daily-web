import { jiraActions } from '@/lib/operations/jira';
import { NextRequest, NextResponse } from 'next/server';
import { upstreamError } from '@/lib/api/context';
import { invalidKey, issueKeyParam, requireJira, writeDone } from '@/lib/api/jira';
import { commentText } from '@/lib/integrations/jira/comments';
import { COMMENT_MAX } from '@/lib/jiraLimits';

type Params = { params: Promise<{ key: string }> };

function bodyOf(payload: unknown): string | null {
  if (typeof payload !== 'object' || payload === null || Array.isArray(payload)) return null;
  return commentText((payload as { body?: unknown }).body);
}

export async function POST(request: NextRequest, { params }: Params) {
  const auth = await requireJira();
  if (!auth.ok) return auth.response;
  const key = issueKeyParam((await params).key);
  if (!key) return invalidKey();

  const text = bodyOf(await request.json().catch(() => null));
  if (!text) {
    return NextResponse.json(
      { error: `comentário vazio ou com mais de ${COMMENT_MAX} caracteres` },
      { status: 400 },
    );
  }

  try {
    const comment = await jiraActions.comment({userId: auth.value.user.id, connection: auth.value.connection}, key, text);
    return writeDone(auth.value.user.id, { comment });
  } catch (err) {
    return upstreamError(err);
  }
}
