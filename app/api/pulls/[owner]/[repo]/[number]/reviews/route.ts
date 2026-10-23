import { NextRequest } from 'next/server';
import { pullOperationError, runPullOperation } from '@/app/api/pulls/shared';
import { badRequest, invalidPull, jsonObject, pullParams, pullsWriteDone, requirePulls, textField } from '@/lib/api/pulls';
import { REVIEW_EVENTS, TEXT_MAX, type ReviewEvent } from '@/lib/integrations/github/actions';

type Params = { params: Promise<{ owner: string; repo: string; number: string }> };

export async function POST(request: NextRequest, { params }: Params) {
  const auth = await requirePulls();
  if (!auth.ok) return auth.response;
  const { owner, repo, number } = await params;
  const ref = pullParams(owner, repo, number);
  if (!ref) return invalidPull();

  const payload = await jsonObject(request);
  const event = payload?.event;
  if (!REVIEW_EVENTS.includes(event as ReviewEvent)) {
    return badRequest('revisão inválida — use APPROVE ou REQUEST_CHANGES');
  }
  const body = textField(payload?.body);
  if (body.kind === 'invalid') return badRequest(`comentário inválido ou com mais de ${TEXT_MAX} caracteres`);
  if (event === 'REQUEST_CHANGES' && body.kind === 'empty') {
    return badRequest('pedir mudanças exige um comentário');
  }

  try {
    const result = await runPullOperation(request,auth.value,'github_review',{...ref,event,body:body.kind==='text'?body.value:null});
    return pullsWriteDone(auth.value.user.id, { review: {id:result.id,state:result.state} });
  } catch (err) {
    return pullOperationError(err,auth.value.user.id);
  }
}
