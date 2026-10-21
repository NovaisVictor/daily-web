import { NextRequest, NextResponse } from 'next/server';
import { upstreamError } from '@/lib/api/context';
import { badRequest, invalidPull, jsonObject, pullParams, pullsWriteDone, requirePulls } from '@/lib/api/pulls';
import { githubToken } from '@/lib/integrations/githubApi';
import { isCommitSha, PullStateRefusal, rerunFailedRuns } from '@/lib/integrations/github/actions';

type Params = { params: Promise<{ owner: string; repo: string; number: string }> };

export async function POST(request: NextRequest, { params }: Params) {
  const auth = await requirePulls();
  if (!auth.ok) return auth.response;
  const { owner, repo, number } = await params;
  const ref = pullParams(owner, repo, number);
  if (!ref) return invalidPull();

  const headSha = (await jsonObject(request))?.headSha;
  if (!isCommitSha(headSha)) return badRequest('commit do PR inválido');

  try {
    const { rerun, failed } = await rerunFailedRuns(githubToken(auth.value.connection), ref, headSha);
    if (rerun === 0 && failed.length > 0) {
      return NextResponse.json({ error: failed[0].error, failed }, { status: 502 });
    }
    return pullsWriteDone(auth.value.user.id, { rerun, failed });
  } catch (err) {
    if (err instanceof PullStateRefusal) return NextResponse.json({ error: err.message }, { status: 409 });
    return upstreamError(err);
  }
}
