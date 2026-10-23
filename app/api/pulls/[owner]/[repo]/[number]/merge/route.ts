import { NextRequest } from 'next/server';
import { pullOperationError, runPullOperation } from '@/app/api/pulls/shared';
import { badRequest, invalidPull, jsonObject, pullParams, pullsWriteDone, requirePulls } from '@/lib/api/pulls';
import {
  isCommitSha,
  MERGE_METHODS,
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
    const result = await runPullOperation(request,auth.value,'github_merge',{...ref,method,headSha:payload.headSha});
    return pullsWriteDone(auth.value.user.id, { sha:result.sha });
  } catch (err) {
    return pullOperationError(err,auth.value.user.id);
  }
}
