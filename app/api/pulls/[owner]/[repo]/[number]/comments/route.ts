import { NextRequest } from 'next/server';
import { pullOperationError, runPullOperation } from '@/app/api/pulls/shared';
import { badRequest, invalidPull, jsonObject, pullParams, pullsWriteDone, requirePulls, textField } from '@/lib/api/pulls';
import { TEXT_MAX } from '@/lib/integrations/github/actions';

type Params = { params: Promise<{ owner: string; repo: string; number: string }> };

export async function POST(request: NextRequest, { params }: Params) {
  const auth = await requirePulls();
  if (!auth.ok) return auth.response;
  const { owner, repo, number } = await params;
  const ref = pullParams(owner, repo, number);
  if (!ref) return invalidPull();

  const body = textField((await jsonObject(request))?.body);
  if (body.kind !== 'text') return badRequest(`comentário vazio ou com mais de ${TEXT_MAX} caracteres`);

  try {
    const result = await runPullOperation(request,auth.value,'github_comment',{...ref,body:body.value});
    return pullsWriteDone(auth.value.user.id, { comment: {id:result.id,url:result.url} });
  } catch (err) {
    return pullOperationError(err,auth.value.user.id);
  }
}
