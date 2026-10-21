import { NextRequest } from 'next/server';
import { upstreamError } from '@/lib/api/context';
import { badRequest, invalidPull, jsonObject, pullParams, pullsWriteDone, requirePulls } from '@/lib/api/pulls';
import { githubToken } from '@/lib/integrations/githubApi';
import { requestReviewers, REVIEWERS_MAX, teamSlug } from '@/lib/integrations/github/actions';
import { isRequestableLogin } from '@/lib/githubLogin';

type Params = { params: Promise<{ owner: string; repo: string; number: string }> };

interface Split {
  users: string[];
  teams: string[];
}

/** Users as login, teams as `team:<slug>`; `null` when any entry is neither. */
function splitReviewers(value: unknown): Split | null {
  if (!Array.isArray(value) || value.length === 0 || value.length > REVIEWERS_MAX) return null;
  const split: Split = { users: [], teams: [] };
  for (const entry of value) {
    const slug = teamSlug(entry);
    if (slug !== null) split.teams.push(slug);
    else if (isRequestableLogin(entry)) split.users.push(entry);
    else return null;
  }
  return { users: [...new Set(split.users)], teams: [...new Set(split.teams)] };
}

export async function POST(request: NextRequest, { params }: Params) {
  const auth = await requirePulls();
  if (!auth.ok) return auth.response;
  const { owner, repo, number } = await params;
  const ref = pullParams(owner, repo, number);
  if (!ref) return invalidPull();

  const split = splitReviewers((await jsonObject(request))?.reviewers);
  if (!split) {
    return badRequest(`revisores inválidos — de 1 a ${REVIEWERS_MAX}, logins do GitHub ou team:<slug>`);
  }

  try {
    const requested = await requestReviewers(githubToken(auth.value.connection), ref, split.users, split.teams);
    return pullsWriteDone(auth.value.user.id, { requested });
  } catch (err) {
    return upstreamError(err);
  }
}
