import { NextRequest } from 'next/server';
import { upstreamError } from '@/lib/api/context';
import { badRequest, invalidPull, jsonObject, pullParams, pullsWriteDone, requirePulls, textField } from '@/lib/api/pulls';
import { githubToken } from '@/lib/integrations/githubApi';
import { addComment, TEXT_MAX } from '@/lib/integrations/github/actions';

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
    const comment = await addComment(githubToken(auth.value.connection), ref, body.value);
    return pullsWriteDone(auth.value.user.id, { comment });
  } catch (err) {
    return upstreamError(err);
  }
}
