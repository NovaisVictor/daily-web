import { afterEach, describe, expect, it, vi } from 'vitest';
import reposCapture from '@/tests/fixtures/github/graphql-repos.json';
import reviewCapture from '@/tests/fixtures/github/graphql-review-requests.json';
import myPrsCapture from '@/tests/fixtures/github/graphql-my-prs.json';
import {
  ciFromState,
  failedChecksOf,
  fetchMyPulls,
  fetchPulls,
  fetchReviewRequests,
  githubErrorDetail,
  githubRequest,
  mergeFromState,
  parseIssueNode,
  parsePullNode,
  parseReposData,
  parseSearchData,
  pendingReviewersOf,
  reviewFromDecision,
} from '@/lib/integrations/githubApi';
import type { Connection } from '@/lib/vault/connections';
import type { PullRequestItem } from '@/lib/types';

const TRACKED = Array.from({ length: 8 }, (_, i) => `acme/repo-${i + 1}`);

/** The capture stripped node ids; the query asks for them, so put them back. */
function withIds<T>(value: T): T {
  const copy = structuredClone(value) as unknown;
  const visit = (node: unknown): void => {
    if (Array.isArray(node)) node.forEach(visit);
    else if (typeof node === 'object' && node !== null) {
      const record = node as Record<string, unknown>;
      if (typeof record.number === 'number' && typeof record.url === 'string' && !('id' in record)) {
        record.id = `node:${record.url}`;
      }
      Object.values(record).forEach(visit);
    }
  };
  visit(copy);
  return copy as T;
}

function dataOf(capture: unknown): Record<string, unknown> {
  return (withIds(capture) as { data: Record<string, unknown> }).data;
}

function reposData() {
  return dataOf(reposCapture);
}

function find(items: PullRequestItem[], repo: string, number: number): PullRequestItem {
  const item = items.find((i) => i.repo === repo && i.number === number);
  if (!item) throw new Error(`${repo}#${number} not parsed`);
  return item;
}

function conn(repos = TRACKED.join(', ')): Connection {
  return { id: 'c1', module: 'pulls', label: 'GitHub', values: { token: 'ghp_token', repos } } as unknown as Connection;
}

function reply(body: unknown, headers: Record<string, string> = {}, status = 200) {
  return new Response(body === undefined ? null : JSON.stringify(body), { status, headers });
}

function stubFetch(...responses: Response[]) {
  const mock = vi.fn();
  responses.forEach((r) => mock.mockResolvedValueOnce(r));
  vi.stubGlobal('fetch', mock);
  return mock;
}

afterEach(() => vi.unstubAllGlobals());

describe('ciFromState', () => {
  it.each([
    ['SUCCESS', 'passing'],
    ['FAILURE', 'failing'],
    ['ERROR', 'failing'],
    ['PENDING', 'running'],
    ['EXPECTED', 'running'],
  ])('maps %s to %s', (state, ci) => {
    expect(ciFromState(state)).toBe(ci);
  });

  it('maps a commit without checks to none', () => {
    expect(ciFromState(null)).toBe('none');
  });

  it('maps a state GitHub adds later to unknown instead of throwing', () => {
    expect(ciFromState('SOMETHING_NEW')).toBe('unknown');
  });
});

describe('reviewFromDecision', () => {
  it.each([
    ['APPROVED', 'approved'],
    ['CHANGES_REQUESTED', 'changes-requested'],
    ['REVIEW_REQUIRED', 'pending'],
  ])('maps %s to %s', (decision, review) => {
    expect(reviewFromDecision(decision)).toBe(review);
  });

  it('maps a repo without required review to none', () => {
    expect(reviewFromDecision(null)).toBe('none');
  });

  it('maps an unknown decision to unknown', () => {
    expect(reviewFromDecision('SOMETHING_NEW')).toBe('unknown');
  });
});

describe('mergeFromState', () => {
  it.each([
    ['CONFLICTING', 'DIRTY', 'conflict'],
    ['MERGEABLE', 'CLEAN', 'clean'],
    ['MERGEABLE', 'BLOCKED', 'blocked'],
    ['MERGEABLE', 'BEHIND', 'blocked'],
    ['MERGEABLE', 'UNSTABLE', 'blocked'],
    ['MERGEABLE', 'HAS_HOOKS', 'blocked'],
    ['MERGEABLE', 'DRAFT', 'blocked'],
    ['MERGEABLE', 'DIRTY', 'conflict'],
  ])('maps %s + %s to %s', (mergeable, state, merge) => {
    expect(mergeFromState(mergeable, state)).toBe(merge);
  });

  // 12 of 16 captured PRs came back UNKNOWN/UNKNOWN: GitHub had not computed it yet.
  it('treats not-yet-computed mergeability as unknown, never as conflict', () => {
    expect(mergeFromState('UNKNOWN', 'UNKNOWN')).toBe('unknown');
  });

  it('maps unknown values to unknown', () => {
    expect(mergeFromState('SOMETHING_NEW', 'CLEAN')).toBe('unknown');
    expect(mergeFromState('MERGEABLE', 'SOMETHING_NEW')).toBe('unknown');
    expect(mergeFromState(null, null)).toBe('unknown');
  });
});

describe('failedChecksOf', () => {
  const run = (name: string, conclusion: string | null) => ({
    __typename: 'CheckRun',
    name,
    conclusion,
    status: 'COMPLETED',
    detailsUrl: `https://ci/${name}`,
  });

  it('counts failed and timed-out check runs only', () => {
    const failed = failedChecksOf([
      run('a', 'FAILURE'),
      run('b', 'TIMED_OUT'),
      run('c', 'CANCELLED'),
      run('d', 'SKIPPED'),
      run('e', 'SUCCESS'),
      run('f', null),
    ]);
    expect(failed.map((c) => c.name)).toEqual(['a', 'b']);
  });

  it('counts failed and errored status contexts, keeping a null url', () => {
    const failed = failedChecksOf([
      { __typename: 'StatusContext', context: 'ci/x', state: 'ERROR', targetUrl: null },
      { __typename: 'StatusContext', context: 'ci/y', state: 'FAILURE', targetUrl: 'https://y' },
      { __typename: 'StatusContext', context: 'ci/z', state: 'SUCCESS', targetUrl: null },
    ]);
    expect(failed).toEqual([
      { name: 'ci/x', url: null },
      { name: 'ci/y', url: 'https://y' },
    ]);
  });

  it('keeps at most five', () => {
    const failed = failedChecksOf(Array.from({ length: 8 }, (_, i) => run(`c${i}`, 'FAILURE')));
    expect(failed).toHaveLength(5);
  });
});

describe('pendingReviewersOf', () => {
  it('lists users by login and teams as team:<slug>, skipping deleted reviewers', () => {
    expect(
      pendingReviewersOf([
        { requestedReviewer: { __typename: 'User', login: 'user-1' } },
        { requestedReviewer: { __typename: 'Team', slug: 'team-1' } },
        { requestedReviewer: null },
      ]),
    ).toEqual(['user-1', 'team:team-1']);
  });
});

describe('parseReposData against the captured repos query', () => {
  it('loads every open PR and issue of the eight tracked repos', () => {
    const parsed = parseReposData(reposData(), TRACKED, []);
    expect(parsed.errors).toEqual([]);
    expect(parsed.items.filter((i) => i.isPullRequest)).toHaveLength(16);
    expect(parsed.items.filter((i) => !i.isPullRequest)).toHaveLength(3);
  });

  it('reports the default branch of each repo with its CI', () => {
    const { defaultBranches } = parseReposData(reposData(), TRACKED, []);
    expect(defaultBranches).toHaveLength(8);
    expect(defaultBranches.find((b) => b.repo === 'acme/repo-4')).toEqual({ repo: 'acme/repo-4', branch: 'main', ci: 'failing' });
    expect(defaultBranches.filter((b) => b.ci === 'passing')).toHaveLength(7);
  });

  it('derives CI, failed checks, review, merge, size and refs of a PR', () => {
    const pr = find(parseReposData(reposData(), TRACKED, []).items, 'acme/repo-5', 92);
    expect(pr).toMatchObject({
      id: 'node:https://github.com/acme/repo-5/pull/92',
      author: 'user-1',
      createdAt: '2026-09-17T20:12:45Z',
      ci: 'failing',
      review: 'pending',
      merge: 'unknown',
      size: { additions: 719, deletions: 0, files: 1 },
      headRef: 'feature/branch-2',
      baseRef: 'main',
      headSha: '9fd7b84776d6e7cd1a3d25dd3b933e084d4045b4',
    });
    expect(pr.failedChecks.map((c) => c.name)).toEqual(['check-1', 'scan']);
  });

  it('marks the PRs that ask for the viewer review and the one the viewer opened', () => {
    const { items } = parseReposData(reposData(), TRACKED, []);
    expect(items.filter((i) => i.awaitingYou).map((i) => i.number).sort((a, b) => a - b)).toEqual([63, 277, 291, 293]);
    expect(items.filter((i) => i.mine).map((i) => `${i.repo}#${i.number}`)).toEqual(['acme/repo-7#1372']);
  });

  it('lists pending reviewers with teams prefixed', () => {
    const pr = find(parseReposData(reposData(), TRACKED, []).items, 'acme/repo-6', 291);
    expect(pr.pendingReviewers).toEqual(['team:team-1', 'viewer', 'user-1']);
  });

  it('gives issues the not-applicable value of every PR-only field', () => {
    const issue = find(parseReposData(reposData(), TRACKED, []).items, 'acme/repo-5', 95);
    expect(issue).toMatchObject({
      isPullRequest: false,
      draft: false,
      awaitingYou: false,
      ci: 'none',
      failedChecks: [],
      review: 'none',
      pendingReviewers: [],
      merge: 'none',
      size: null,
      headRef: null,
      baseRef: null,
      headSha: null,
      createdAt: '2026-09-18T21:55:39Z',
    });
  });

  it('notes a repo whose open PRs do not fit in one page', () => {
    const data = reposData();
    (data.repo5 as { pullRequests: { totalCount: number } }).pullRequests.totalCount = 80;
    expect(parseReposData(data, TRACKED, []).truncated).toEqual([
      { repo: 'acme/repo-6', kind: 'pulls', shown: 11, total: 80 },
    ]);
  });

  it('keeps loading the other repos when one alias is NOT_FOUND', () => {
    const data = { ...reposData(), repo3: null };
    const parsed = parseReposData(data, TRACKED, [
      { type: 'NOT_FOUND', path: ['repo3'], message: "Could not resolve to a Repository with the name 'acme/repo-4'." },
    ]);
    expect(parsed.errors).toEqual(["acme/repo-4: Could not resolve to a Repository with the name 'acme/repo-4'."]);
    expect(parsed.defaultBranches.map((b) => b.repo)).not.toContain('acme/repo-4');
    expect(parsed.items.filter((i) => i.isPullRequest)).toHaveLength(16);
  });

  it('fails one repo with an unexpected shape without failing the others', () => {
    const data = reposData();
    delete (data.repo4 as Record<string, unknown>).pullRequests;
    const parsed = parseReposData(data, TRACKED, []);
    expect(parsed.errors).toEqual(['acme/repo-5: resposta inesperada do GitHub em acme/repo-5: pullRequests ausente']);
    expect(parsed.items.some((i) => i.repo === 'acme/repo-6')).toBe(true);
  });
});

describe('parsePullNode', () => {
  const node = () => (reposData().repo2 as { pullRequests: { nodes: Record<string, unknown>[] } }).pullRequests.nodes[0];

  it('keeps an empty author when the account was deleted', () => {
    expect(parsePullNode({ ...node(), author: null }, 'acme/repo-3', 'viewer').author).toBe('');
  });

  it('fails visibly when the node id is missing', () => {
    const { id: _id, ...rest } = node();
    expect(() => parsePullNode(rest, 'acme/repo-3', 'viewer')).toThrow(
      'resposta inesperada do GitHub em acme/repo-3#63: id ausente',
    );
  });

  it('maps an unknown enum to unknown without throwing', () => {
    const pr = parsePullNode({ ...node(), reviewDecision: 'NEW', mergeable: 'NEW' }, 'acme/repo-3', 'viewer');
    expect([pr.review, pr.merge]).toEqual(['unknown', 'unknown']);
  });
});

describe('parseIssueNode', () => {
  it('marks an issue the viewer opened as mine', () => {
    const issue = parseIssueNode(
      { id: 'I_1', number: 1, title: 't', url: 'u', createdAt: 'c', updatedAt: 'u', author: { login: 'viewer' } },
      'acme/repo-1',
      'viewer',
    );
    expect(issue.mine).toBe(true);
  });
});

describe('parseSearchData against the captured searches', () => {
  it('reads every review request, including repos outside the tracked list', () => {
    const { items, total } = parseSearchData(dataOf(reviewCapture));
    expect(total).toBe(21);
    expect(items).toHaveLength(21);
    expect(items.some((i) => !TRACKED.includes(i.repo))).toBe(true);
  });

  it('reads a PR with no checks at all as ci none', () => {
    const { items } = parseSearchData(dataOf(myPrsCapture));
    expect(find(items, 'acme/repo-13', 1).ci).toBe('none');
  });

  it('only produces known domain values from the capture', () => {
    const all = [
      ...parseReposData(reposData(), TRACKED, []).items,
      ...parseSearchData(dataOf(reviewCapture)).items,
      ...parseSearchData(dataOf(myPrsCapture)).items,
    ];
    expect(all.filter((i) => i.ci === 'unknown' || i.review === 'unknown')).toEqual([]);
  });
});

describe('fetchPulls', () => {
  it('sends one GraphQL call for all tracked repos, not one per repo', async () => {
    const fetchMock = stubFetch(reply(withIds(reposCapture)));
    const digest = await fetchPulls(conn());

    expect(fetchMock).toHaveBeenCalledTimes(1);
    const [url, init] = fetchMock.mock.calls[0] as [string, RequestInit];
    expect(url).toBe('https://api.github.com/graphql');
    expect(init.method).toBe('POST');
    expect(JSON.parse(String(init.body)).variables).toMatchObject({ owner0: 'acme', name0: 'repo-1', name7: 'repo-8' });
    expect(digest.items).toHaveLength(19);
  });

  it('puts a renamed repo in errors and still loads the others', async () => {
    const body = withIds(reposCapture) as { data: Record<string, unknown>; errors?: unknown[] };
    body.data.repo3 = null;
    body.errors = [{ type: 'NOT_FOUND', path: ['repo3'], message: 'Could not resolve to a Repository' }];
    stubFetch(reply(body));

    const digest = await fetchPulls(conn());
    expect(digest.errors).toEqual(['acme/repo-4: Could not resolve to a Repository']);
    expect(digest.defaultBranches).toHaveLength(7);
  });

  it('throws the first GraphQL error that is not tied to one repo', async () => {
    stubFetch(reply({ data: { viewer: null }, errors: [{ message: 'Field viewer is broken', path: ['viewer'] }] }));
    await expect(fetchPulls(conn())).rejects.toThrow('o GitHub recusou a consulta: Field viewer is broken');
  });

  it('throws the first message when GraphQL answers errors without data', async () => {
    stubFetch(reply({ errors: [{ message: 'Parse error on "}"' }, { message: 'second' }] }));
    await expect(fetchPulls(conn())).rejects.toThrow('o GitHub recusou a consulta: Parse error on "}"');
  });

  it('keeps the rate-limit message when GraphQL reports RATE_LIMITED', async () => {
    const reset = Math.floor(new Date('2026-09-14T18:30:00Z').getTime() / 1000);
    stubFetch(reply({ errors: [{ type: 'RATE_LIMITED', message: 'API rate limit exceeded' }] }, { 'x-ratelimit-reset': String(reset) }));
    await expect(fetchPulls(conn())).rejects.toThrow(/restam 0, volta às \d{2}:\d{2}/);
  });

  it('keeps the rate-limit message on a 403 with no quota left', async () => {
    stubFetch(reply({ message: 'API rate limit exceeded' }, { 'x-ratelimit-remaining': '0' }, 403));
    await expect(fetchPulls(conn())).rejects.toThrow(/limite de requisições do GitHub atingido — restam 0/);
  });

  it('does not call GitHub without tracked repos', async () => {
    const fetchMock = stubFetch();
    expect(await fetchPulls(conn(''))).toEqual({ items: [], errors: [], defaultBranches: [], truncated: [] });
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it('reports a repo name that is not owner/name without querying it', async () => {
    const fetchMock = stubFetch(reply(withIds(reposCapture)));
    const digest = await fetchPulls(conn(`${TRACKED.join(', ')}, not-a-repo`));
    expect(digest.errors).toEqual(['not-a-repo: nome inválido — use o formato dono/nome']);
    expect(JSON.parse(String((fetchMock.mock.calls[0][1] as RequestInit).body)).variables).not.toHaveProperty('owner8');
  });
});

describe('fetchReviewRequests', () => {
  it('searches review requests in one GraphQL call', async () => {
    const fetchMock = stubFetch(reply(withIds(reviewCapture)));
    const digest = await fetchReviewRequests(conn());

    expect(fetchMock).toHaveBeenCalledTimes(1);
    const init = fetchMock.mock.calls[0][1] as RequestInit;
    expect(JSON.parse(String(init.body)).variables).toEqual({ q: 'is:open is:pr review-requested:@me' });
    expect(digest.items).toHaveLength(21);
    expect(digest.items.every((i) => i.awaitingYou && !i.mine)).toBe(true);
    expect(digest).toMatchObject({ truncated: false, total: 21, scopeNote: null });
  });

  it('says when the search found more than one page holds', async () => {
    const body = withIds(reviewCapture);
    body.data.search.issueCount = 250;
    stubFetch(reply(body));
    expect(await fetchReviewRequests(conn())).toMatchObject({ truncated: true, total: 250 });
  });

  it('turns an empty list with a token missing `repo` into a scope note', async () => {
    stubFetch(reply({ data: { search: { issueCount: 0, nodes: [] } } }, { 'x-oauth-scopes': 'gist' }));
    expect((await fetchReviewRequests(conn())).scopeNote).toMatch(/escopo `repo`/);
  });
});

describe('fetchMyPulls', () => {
  it('searches the PRs the user opened, across every repo the token sees', async () => {
    const fetchMock = stubFetch(reply(withIds(myPrsCapture)));
    const digest = await fetchMyPulls(conn());

    expect(JSON.parse(String((fetchMock.mock.calls[0][1] as RequestInit).body)).variables).toEqual({
      q: 'is:open is:pr author:@me',
    });
    expect(digest).toMatchObject({ truncated: false, total: 4 });
    expect(digest.items.every((i) => i.mine && !i.awaitingYou)).toBe(true);
  });
});

describe('githubRequest', () => {
  it('sends the method and a JSON body', async () => {
    const fetchMock = stubFetch(reply({ id: 1 }));
    const data = await githubRequest('ghp_token', '/repos/acme/repo-1/pulls/1/reviews', {
      method: 'POST',
      body: { event: 'APPROVE' },
    });

    const init = fetchMock.mock.calls[0][1] as RequestInit;
    expect(data).toEqual({ id: 1 });
    expect(init.method).toBe('POST');
    expect(init.body).toBe('{"event":"APPROVE"}');
    expect((init.headers as Record<string, string>)['content-type']).toBe('application/json');
  });

  it('returns null on 204', async () => {
    stubFetch(new Response(null, { status: 204 }));
    expect(await githubRequest('ghp_token', '/x', { method: 'PUT' })).toBeNull();
  });

  it("throws GitHub's own message and error details", async () => {
    stubFetch(reply({ message: 'Validation Failed', errors: [{ message: 'Pull Request is not mergeable' }] }, {}, 422));
    await expect(githubRequest('ghp_token', '/x', { method: 'PUT' })).rejects.toThrow(
      'GitHub respondeu 422: Validation Failed: Pull Request is not mergeable',
    );
  });

  it("adds GitHub's message to a permission refusal", async () => {
    stubFetch(reply({ message: 'Resource not accessible by personal access token' }, { 'x-ratelimit-remaining': '4000' }, 403));
    await expect(githubRequest('ghp_token', '/x')).rejects.toThrow(
      'o token não tem permissão: Resource not accessible by personal access token',
    );
  });

  it('refuses a path that does not start with a slash', async () => {
    const fetchMock = stubFetch();
    await expect(githubRequest('ghp_token', '@evil.example/x')).rejects.toThrow(/caminho inválido/);
    expect(fetchMock).not.toHaveBeenCalled();
  });
});

describe('githubErrorDetail', () => {
  it('describes a field error that has no message', () => {
    expect(githubErrorDetail({ message: 'Validation Failed', errors: [{ field: 'sha', code: 'invalid' }] })).toBe(
      'Validation Failed: sha invalid',
    );
  });

  it('returns null for a body without explanation', () => {
    expect(githubErrorDetail(null)).toBeNull();
    expect(githubErrorDetail({})).toBeNull();
  });
});
