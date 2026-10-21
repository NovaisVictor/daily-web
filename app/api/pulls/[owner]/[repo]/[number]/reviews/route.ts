import { NextRequest } from 'next/server';
import { upstreamError } from '@/lib/api/context';
import { badRequest, invalidPull, jsonObject, pullParams, pullsWriteDone, requirePulls, textField } from '@/lib/api/pulls';
import { githubToken } from '@/lib/integrations/githubApi';
import { REVIEW_EVENTS, submitReview, TEXT_MAX, type ReviewEvent } from '@/lib/integrations/github/actions';

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
    const review = await submitReview(
      githubToken(auth.value.connection),
      ref,
      event as ReviewEvent,
      body.kind === 'text' ? body.value : null,
    );
    return pullsWriteDone(auth.value.user.id, { review });
  } catch (err) {
    return upstreamError(err);
  }
}
