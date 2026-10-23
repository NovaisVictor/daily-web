import { NextRequest } from 'next/server';
import { pullOperationError, runPullOperation } from '@/app/api/pulls/shared';
import { badRequest, invalidPull, jsonObject, pullParams, pullsWriteDone, requirePulls } from '@/lib/api/pulls';
import { isCommitSha } from '@/lib/integrations/github/actions';

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
    const result = await runPullOperation(request,auth.value,'github_rerun',{...ref,headSha});
    return pullsWriteDone(auth.value.user.id, { rerun:result.rerun,failed:result.failed });
  } catch (err) {
    return pullOperationError(err,auth.value.user.id);
  }
}
