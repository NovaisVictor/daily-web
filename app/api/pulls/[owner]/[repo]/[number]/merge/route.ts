import { NextRequest, NextResponse } from 'next/server';
import { upstreamError } from '@/lib/api/context';
import { badRequest, invalidPull, jsonObject, pullParams, pullsWriteDone, requirePulls } from '@/lib/api/pulls';
import { githubToken } from '@/lib/integrations/githubApi';
import {
  isCommitSha,
  MERGE_METHODS,
  mergePull,
  PullStateRefusal,
  type MergeMethod,
} from '@/lib/integrations/github/actions';

type Params = { params: Promise<{ owner: string; repo: string; number: string }> };

export async function POST(request: NextRequest, { params }: Params) {
  const auth = await requirePulls();
  if (!auth.ok) return auth.response;
  const { owner, repo, number } = await params;
  const ref = pullParams(owner, repo, number);
  if (!ref) return invalidPull();

  const payload = await jsonObject(request);
  const method = payload?.method;
  if (!MERGE_METHODS.includes(method as MergeMethod)) {
    return badRequest('método de merge inválido — use merge, squash ou rebase');
  }
  if (!isCommitSha(payload?.headSha)) return badRequest('commit do PR inválido');

  try {
    const sha = await mergePull(githubToken(auth.value.connection), ref, method as MergeMethod, payload.headSha);
    return pullsWriteDone(auth.value.user.id, { sha });
  } catch (err) {
    if (err instanceof PullStateRefusal) return NextResponse.json({ error: err.message }, { status: 409 });
    return upstreamError(err);
  }
}
