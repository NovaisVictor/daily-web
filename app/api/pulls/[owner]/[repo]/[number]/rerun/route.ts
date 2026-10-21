import { NextRequest } from 'next/server';
import { upstreamError } from '@/lib/api/context';
import { badRequest, invalidPull, jsonObject, pullParams, pullsWriteDone, requirePulls } from '@/lib/api/pulls';
import { githubToken } from '@/lib/integrations/githubApi';
import { isCommitSha, rerunFailedRuns } from '@/lib/integrations/github/actions';

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
    const rerun = await rerunFailedRuns(githubToken(auth.value.connection), ref, headSha);
    return pullsWriteDone(auth.value.user.id, { rerun });
  } catch (err) {
    return upstreamError(err);
  }
}
