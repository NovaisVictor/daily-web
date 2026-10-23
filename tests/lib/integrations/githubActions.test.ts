import { afterEach, describe, expect, it, vi } from 'vitest';
import runsFixture from '../../fixtures/github/actions-runs.json';
import {
  addComment,
  mergePull,
  PullStateRefusal,
  requestReviewers,
  rerunFailedRuns,
  submitReview,
  type PullRef,
} from '@/lib/integrations/github/actions';

const REF: PullRef = { owner: 'acme', repo: 'repo-4', number: 42 };
const SHA = '9fd7b84776d6e7cd1a3d25dd3b933e084d4045b4';
const OTHER_SHA = '1111111111111111111111111111111111111111';

function reply(status: number, body?: unknown) {
  return new Response(body === undefined ? null : JSON.stringify(body), { status });
}

function stubFetch(...responses: Response[]) {
  const fetchMock = vi.fn();
  for (const r of responses) fetchMock.mockResolvedValueOnce(r);
  vi.stubGlobal('fetch', fetchMock);
  return fetchMock;
}

function call(fetchMock: ReturnType<typeof vi.fn>, index: number) {
  const [url, init] = fetchMock.mock.calls[index];
  return { url, method: init.method, body: init.body === undefined ? undefined : JSON.parse(init.body) };
}

function runsOf(repo: keyof typeof runsFixture) {
  const { total_count, workflow_runs } = runsFixture[repo];
  return { total_count, workflow_runs };
}

function openPull(over: Record<string, unknown> = {}) {
  return { number: 42, state: 'open', draft: false, user:{login:'author'}, mergeable: true, head: { sha: SHA, ref: 'feature/x' }, ...over };
}

afterEach(() => {
  vi.unstubAllGlobals();
});

describe('submitReview', () => {
  it('posts the event and the comment to the pull reviews endpoint', async () => {
    const fetchMock = stubFetch(reply(200, { id: 7, state: 'APPROVED' }));
    await submitReview('t', REF, 'APPROVE', 'lgtm');
    expect(call(fetchMock, 0)).toEqual({
      url: 'https://api.github.com/repos/acme/repo-4/pulls/42/reviews',
      method: 'POST',
      body: { event: 'APPROVE', body: 'lgtm' },
    });
  });

  it('omits the body when there is no comment', async () => {
    const fetchMock = stubFetch(reply(200, { id: 7, state: 'APPROVED' }));
    await submitReview('t', REF, 'APPROVE', null);
    expect(call(fetchMock, 0).body).toEqual({ event: 'APPROVE' });
  });

  it('returns the review id and state', async () => {
    stubFetch(reply(200, { id: 7, state: 'CHANGES_REQUESTED' }));
    expect(await submitReview('t', REF, 'REQUEST_CHANGES', 'fix')).toEqual({ id: 7, state: 'CHANGES_REQUESTED' });
  });

  it('fails visibly on a review state it does not know', async () => {
    stubFetch(reply(200, { id: 7, state: 'PENDING' }));
    await expect(submitReview('t', REF, 'APPROVE', null)).rejects.toThrow(/estado desconhecido "PENDING"/);
  });

  it("surfaces GitHub's message when it refuses", async () => {
    stubFetch(reply(422, { message: 'Unprocessable Entity', errors: ['Can not approve your own pull request'] }));
    await expect(submitReview('t', REF, 'APPROVE', null)).rejects.toThrow(
      'GitHub respondeu 422: Unprocessable Entity: Can not approve your own pull request',
    );
  });
});

describe('addComment', () => {
  it('posts to the issue comments endpoint, which also serves pull requests', async () => {
    const fetchMock = stubFetch(reply(201, { id: 9, html_url: 'https://github.com/acme/repo-4/pull/42#c9' }));
    await addComment('t', REF, 'oi');
    expect(call(fetchMock, 0)).toEqual({
      url: 'https://api.github.com/repos/acme/repo-4/issues/42/comments',
      method: 'POST',
      body: { body: 'oi' },
    });
  });

  it('fails visibly without the comment url', async () => {
    stubFetch(reply(201, { id: 9 }));
    await expect(addComment('t', REF, 'oi')).rejects.toThrow(/html_url ausente/);
  });
});

describe('requestReviewers', () => {
  it('sends users and teams apart and returns who is requested after it', async () => {
    const fetchMock = stubFetch(
      reply(201, { requested_reviewers: [{ login: 'user-1' }], requested_teams: [{ slug: 'team-1' }] }),
    );
    expect(await requestReviewers('t', REF, ['user-1'], ['team-1'])).toEqual(['user-1', 'team:team-1']);
    expect(call(fetchMock, 0)).toEqual({
      url: 'https://api.github.com/repos/acme/repo-4/pulls/42/requested_reviewers',
      method: 'POST',
      body: { reviewers: ['user-1'], team_reviewers: ['team-1'] },
    });
  });

  it('fails visibly when the reviewer lists are missing', async () => {
    stubFetch(reply(201, { number: 42 }));
    await expect(requestReviewers('t', REF, ['user-1'], [])).rejects.toThrow(/lista de revisores ausente/);
  });
});

describe('mergePull', () => {
  it('re-reads the pull request before merging', async () => {
    const fetchMock = stubFetch(reply(200, openPull()), reply(200, { sha: OTHER_SHA, merged: true, message: 'ok' }));
    await mergePull('t', REF, 'squash', SHA);
    expect(call(fetchMock, 0)).toEqual({
      url: 'https://api.github.com/repos/acme/repo-4/pulls/42',
      method: 'GET',
      body: undefined,
    });
  });

  it('merges pinned to the sha the user saw, with the chosen method', async () => {
    const fetchMock = stubFetch(reply(200, openPull()), reply(200, { sha: OTHER_SHA, merged: true, message: 'ok' }));
    expect(await mergePull('t', REF, 'rebase', SHA)).toBe(OTHER_SHA);
    expect(call(fetchMock, 1)).toEqual({
      url: 'https://api.github.com/repos/acme/repo-4/pulls/42/merge',
      method: 'PUT',
      body: { merge_method: 'rebase', sha: SHA },
    });
  });

  it.each([
    ['closed', { state: 'closed' }, /não está mais aberto/],
    ['moved head', { head: { sha: OTHER_SHA } }, /commits novos/],
    ['not computed', { mergeable: null }, /ainda está calculando/],
    ['not mergeable', { mergeable: false }, /não pode entrar/],
  ])('refuses without merging when the pull request is %s', async (_name, over, message) => {
    const fetchMock = stubFetch(reply(200, openPull(over)));
    const attempt = mergePull('t', REF, 'squash', SHA);
    await expect(attempt).rejects.toBeInstanceOf(PullStateRefusal);
    await expect(attempt).rejects.toThrow(message);
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it('fails visibly on a pull state it does not know', async () => {
    stubFetch(reply(200, openPull({ state: 'merged' })));
    await expect(mergePull('t', REF, 'squash', SHA)).rejects.toThrow(/estado desconhecido "merged"/);
  });

  it("surfaces GitHub's message when the merge is refused", async () => {
    stubFetch(reply(200, openPull()), reply(405, { message: 'Pull Request is not mergeable' }));
    await expect(mergePull('t', REF, 'squash', SHA)).rejects.toThrow('GitHub respondeu 405: Pull Request is not mergeable');
  });
});

describe('rerunFailedRuns', () => {
  const PULL = () => reply(200, openPull());

  it('re-reads the pull request before anything else', async () => {
    const fetchMock = stubFetch(PULL(), reply(200, runsOf('acme/repo-1')));
    await rerunFailedRuns('t', REF, SHA);
    expect(call(fetchMock, 0)).toMatchObject({ url: 'https://api.github.com/repos/acme/repo-4/pulls/42', method: 'GET' });
  });

  it('refuses without listing runs when the head moved since the user looked', async () => {
    const fetchMock = stubFetch(reply(200, openPull({ head: { sha: OTHER_SHA } })));
    await expect(rerunFailedRuns('t', REF, SHA)).rejects.toBeInstanceOf(PullStateRefusal);
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it('lists the Actions runs of the head commit', async () => {
    const fetchMock = stubFetch(PULL(), reply(200, runsOf('acme/repo-1')));
    await rerunFailedRuns('t', REF, SHA);
    expect(call(fetchMock, 1).url).toBe(
      `https://api.github.com/repos/acme/repo-4/actions/runs?head_sha=${SHA}&per_page=20`,
    );
  });

  it('re-runs the failed jobs of each failed run', async () => {
    const runs = runsOf('acme/repo-4');
    const fetchMock = stubFetch(PULL(), reply(200, runs), ...runs.workflow_runs.map(() => reply(201, {})));
    expect(await rerunFailedRuns('t', REF, SHA)).toEqual({ rerun: 5, failed: [] });
    expect(call(fetchMock, 2)).toEqual({
      url: `https://api.github.com/repos/acme/repo-4/actions/runs/${runs.workflow_runs[0].id}/rerun-failed-jobs`,
      method: 'POST',
      body: undefined,
    });
  });

  it('reports each run GitHub refused and keeps the ones it accepted', async () => {
    const runs = runsOf('acme/repo-4');
    stubFetch(
      PULL(),
      reply(200, { ...runs, workflow_runs: runs.workflow_runs.slice(0, 2) }),
      reply(422, { message: 'nope' }),
      reply(201, {}),
    );
    expect(await rerunFailedRuns('t', REF, SHA)).toEqual({
      rerun: 1,
      failed: [{ id: runs.workflow_runs[0].id, error: 'GitHub respondeu 422: nope' }],
    });
  });

  it('re-runs at most five runs', async () => {
    const runs = runsOf('acme/repo-4');
    const extra = { ...runs.workflow_runs[0], id: 1, conclusion: 'timed_out' };
    const fetchMock = stubFetch(
      PULL(),
      reply(200, { ...runs, workflow_runs: [...runs.workflow_runs, extra] }),
      ...Array.from({ length: 6 }, () => reply(201, {})),
    );
    expect((await rerunFailedRuns('t', REF, SHA)).rerun).toBe(5);
    expect(fetchMock).toHaveBeenCalledTimes(7);
  });

  it('returns 0 when no Actions run failed on the commit', async () => {
    const fetchMock = stubFetch(PULL(), reply(200, runsOf('acme/repo-1')));
    expect(await rerunFailedRuns('t', REF, SHA)).toEqual({ rerun: 0, failed: [] });
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  it('skips runs still in progress', async () => {
    const runs = runsOf('acme/repo-4');
    stubFetch(PULL(), reply(200, { ...runs, workflow_runs: [{ ...runs.workflow_runs[0], conclusion: null }] }));
    expect((await rerunFailedRuns('t', REF, SHA)).rerun).toBe(0);
  });

  it.each(['cancelled', 'startup_failure', 'action_required'])('re-runs a run that ended %s', async (conclusion) => {
    const runs = runsOf('acme/repo-4');
    stubFetch(PULL(), reply(200, { ...runs, workflow_runs: [{ ...runs.workflow_runs[0], conclusion }] }), reply(201, {}));
    expect((await rerunFailedRuns('t', REF, SHA)).rerun).toBe(1);
  });

  it('fails visibly on a run conclusion it does not know', async () => {
    const runs = runsOf('acme/repo-4');
    stubFetch(PULL(), reply(200, { ...runs, workflow_runs: [{ ...runs.workflow_runs[0], conclusion: 'exploded' }] }));
    await expect(rerunFailedRuns('t', REF, SHA)).rejects.toThrow(/conclusão desconhecida "exploded"/);
  });
});
