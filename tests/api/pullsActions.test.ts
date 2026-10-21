import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { NextRequest } from 'next/server';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import runsFixture from '../fixtures/github/actions-runs.json';

const currentUser = vi.fn();
vi.mock('@/lib/api/context', async (importOriginal) => ({
  ...(await importOriginal<typeof import('@/lib/api/context')>()),
  requireUser: async () => {
    const user = await currentUser();
    if (!user) return { ok: false, response: new Response('não autenticado', { status: 401 }) };
    return { ok: true, value: user };
  },
}));

const invalidate = vi.fn();
vi.mock('@/lib/refresher', async (importOriginal) => ({
  ...(await importOriginal<typeof import('@/lib/refresher')>()),
  invalidate: (userId: string) => invalidate(userId),
}));

import { POST as reviews } from '@/app/api/pulls/[owner]/[repo]/[number]/reviews/route';
import { POST as comments } from '@/app/api/pulls/[owner]/[repo]/[number]/comments/route';
import { POST as reviewers } from '@/app/api/pulls/[owner]/[repo]/[number]/reviewers/route';
import { POST as merge } from '@/app/api/pulls/[owner]/[repo]/[number]/merge/route';
import { POST as rerun } from '@/app/api/pulls/[owner]/[repo]/[number]/rerun/route';
import { saveConnection, setModuleEnabled } from '@/lib/vault/connections';

type Handler = typeof reviews;

let dir: string;
const ME = { id: 'u-1', username: 'joao' };
const OTHER = { id: 'u-2', username: 'maria' };
const SHA = '9fd7b84776d6e7cd1a3d25dd3b933e084d4045b4';
const OTHER_SHA = '1111111111111111111111111111111111111111';
const API = 'https://api.github.com/repos/acme/repo-4';

interface Target {
  owner: string;
  repo: string;
  number: string;
}

const PR: Target = { owner: 'acme', repo: 'repo-4', number: '42' };

function post(handler: Handler, body: unknown, target: Target = PR) {
  const request = new NextRequest(
    `http://localhost/api/pulls/${target.owner}/${target.repo}/${target.number}/x`,
    { method: 'POST', body: JSON.stringify(body) },
  );
  return handler(request, { params: Promise.resolve(target) });
}

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
  return {
    url,
    method: init.method,
    auth: init.headers.authorization,
    body: init.body === undefined ? undefined : JSON.parse(init.body),
  };
}

function openPull(over: Record<string, unknown> = {}) {
  return { number: 42, state: 'open', mergeable: true, head: { sha: SHA }, ...over };
}

const VALID: Record<string, [Handler, unknown]> = {
  reviews: [reviews, { event: 'APPROVE' }],
  comments: [comments, { body: 'oi' }],
  reviewers: [reviewers, { reviewers: ['user-1'] }],
  merge: [merge, { method: 'squash', headSha: SHA }],
  rerun: [rerun, { headSha: SHA }],
};
const ROUTES = Object.entries(VALID);

beforeEach(async () => {
  dir = mkdtempSync(path.join(tmpdir(), 'daily-web-pulls-actions-'));
  process.env.DAILY_WEB_DB_PATH = path.join(dir, 'test.db');
  process.env.DAILY_WEB_SECRET_KEY = Buffer.alloc(32, 'a').toString('base64');
  vi.clearAllMocks();
  currentUser.mockResolvedValue(ME);
  const { getDb } = await import('@/lib/db');
  getDb();
  saveConnection(ME.id, 'pulls', 'GitHub', { token: 'token-joao', repos: 'acme/repo-4' });
  setModuleEnabled(ME.id, 'pulls', true);
  saveConnection(OTHER.id, 'pulls', 'GitHub', { token: 'token-maria', repos: 'acme/repo-4' });
  setModuleEnabled(OTHER.id, 'pulls', true);
});

afterEach(() => {
  vi.unstubAllGlobals();
  rmSync(dir, { recursive: true, force: true });
});

describe.each(ROUTES)('POST /api/pulls/[owner]/[repo]/[number]/%s', (_name, [handler, body]) => {
  it('401 without a session', async () => {
    currentUser.mockResolvedValue(null);
    expect((await post(handler, body)).status).toBe(401);
  });

  it('400 when the user has no GitHub connection', async () => {
    currentUser.mockResolvedValue({ id: 'u-3', username: 'sem-github' });
    const res = await post(handler, body);
    expect(res.status).toBe(400);
    expect((await res.json()).error).toBe('GitHub não conectado');
  });

  it('400 when the pulls module is disabled', async () => {
    setModuleEnabled(ME.id, 'pulls', false);
    expect((await post(handler, body)).status).toBe(400);
  });

  it.each([
    ['an owner with a slash', { ...PR, owner: 'acme/x' }],
    ['a dot-dot repository', { ...PR, repo: '..' }],
    ['a zero number', { ...PR, number: '0' }],
    ['a negative number', { ...PR, number: '-1' }],
    ['a fractional number', { ...PR, number: '1.5' }],
    ['a number over 1e9', { ...PR, number: '1000000001' }],
  ])('400 on %s without calling GitHub', async (_case, target) => {
    const fetchMock = stubFetch();
    expect((await post(handler, body, target)).status).toBe(400);
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("502 with GitHub's own message when GitHub refuses", async () => {
    stubFetch(reply(422, { message: 'Validation Failed', errors: [{ message: 'nope' }] }), reply(422, {}));
    const res = await post(handler, body);
    expect(res.status).toBe(502);
    expect((await res.json()).error).toContain('Validation Failed: nope');
  });

  it("uses the logged-in user's own token", async () => {
    const fetchMock = stubFetch(reply(500, {}));
    await post(handler, body);
    expect(call(fetchMock, 0).auth).toBe('Bearer token-joao');
  });
});

describe('POST .../reviews', () => {
  it.each([
    ['an unknown event', { event: 'COMMENT' }],
    ['a missing event', {}],
    ['request changes without a comment', { event: 'REQUEST_CHANGES', body: '   ' }],
    ['a non-string comment', { event: 'APPROVE', body: 42 }],
    ['a comment over 10000 characters', { event: 'APPROVE', body: 'a'.repeat(10001) }],
    ['an array payload', ['APPROVE']],
  ])('400 on %s', async (_case, payload) => {
    const fetchMock = stubFetch();
    expect((await post(reviews, payload)).status).toBe(400);
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it('approves without a body when the comment is blank', async () => {
    const fetchMock = stubFetch(reply(200, { id: 7, state: 'APPROVED' }));
    const res = await post(reviews, { event: 'APPROVE', body: '  ' });
    expect(await res.json()).toEqual({ ok: true, review: { id: 7, state: 'APPROVED' } });
    expect(call(fetchMock, 0)).toMatchObject({ url: `${API}/pulls/42/reviews`, method: 'POST', body: { event: 'APPROVE' } });
  });

  it('requests changes with the trimmed comment', async () => {
    const fetchMock = stubFetch(reply(200, { id: 8, state: 'CHANGES_REQUESTED' }));
    await post(reviews, { event: 'REQUEST_CHANGES', body: '  falta teste  ' });
    expect(call(fetchMock, 0).body).toEqual({ event: 'REQUEST_CHANGES', body: 'falta teste' });
  });

  it('invalidates the cached dashboard after the write', async () => {
    stubFetch(reply(200, { id: 7, state: 'APPROVED' }));
    await post(reviews, { event: 'APPROVE' });
    expect(invalidate).toHaveBeenCalledWith(ME.id);
  });
});

describe('POST .../comments', () => {
  it.each([
    ['a missing body', {}],
    ['a blank body', { body: '  ' }],
    ['a non-string body', { body: 1 }],
    ['a body over 10000 characters', { body: 'a'.repeat(10001) }],
  ])('400 on %s', async (_case, payload) => {
    const fetchMock = stubFetch();
    expect((await post(comments, payload)).status).toBe(400);
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it('posts the trimmed text to the issue comments endpoint', async () => {
    const fetchMock = stubFetch(reply(201, { id: 9, html_url: 'https://github.com/acme/repo-4/pull/42#c9' }));
    const res = await post(comments, { body: '  oi  ' });
    expect(await res.json()).toEqual({ ok: true, comment: { id: 9, url: 'https://github.com/acme/repo-4/pull/42#c9' } });
    expect(call(fetchMock, 0)).toMatchObject({ url: `${API}/issues/42/comments`, method: 'POST', body: { body: 'oi' } });
  });

  it('accepts a body of exactly 10000 characters', async () => {
    stubFetch(reply(201, { id: 9, html_url: 'u' }));
    expect((await post(comments, { body: 'a'.repeat(10000) })).status).toBe(200);
  });
});

describe('POST .../reviewers', () => {
  it.each([
    ['an empty list', { reviewers: [] }],
    ['a missing list', {}],
    ['a login with a space', { reviewers: ['user 1'] }],
    ['a login over 39 characters', { reviewers: ['a'.repeat(40)] }],
    ['a team without a slug', { reviewers: ['team:'] }],
    ['a non-string entry', { reviewers: [1] }],
    ['more than 15 reviewers', { reviewers: Array.from({ length: 16 }, (_, i) => `user-${i}`) }],
  ])('400 on %s', async (_case, payload) => {
    const fetchMock = stubFetch();
    expect((await post(reviewers, payload)).status).toBe(400);
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it('sends teams as team_reviewers and users as reviewers, without duplicates', async () => {
    const fetchMock = stubFetch(
      reply(201, { requested_reviewers: [{ login: 'user-1' }], requested_teams: [{ slug: 'team-1' }] }),
    );
    const res = await post(reviewers, { reviewers: ['user-1', 'team:team-1', 'user-1'] });
    expect(await res.json()).toEqual({ ok: true, requested: ['user-1', 'team:team-1'] });
    expect(call(fetchMock, 0)).toMatchObject({
      url: `${API}/pulls/42/requested_reviewers`,
      method: 'POST',
      body: { reviewers: ['user-1'], team_reviewers: ['team-1'] },
    });
  });
});

describe('POST .../merge', () => {
  it.each([
    ['an unknown method', { method: 'fast-forward', headSha: SHA }],
    ['a missing method', { headSha: SHA }],
    ['a missing head sha', { method: 'squash' }],
    ['a short head sha', { method: 'squash', headSha: 'abc123' }],
  ])('400 on %s', async (_case, payload) => {
    const fetchMock = stubFetch();
    expect((await post(merge, payload)).status).toBe(400);
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it('re-reads the pull request, then merges pinned to the sha sent', async () => {
    const fetchMock = stubFetch(reply(200, openPull()), reply(200, { sha: OTHER_SHA, merged: true, message: 'ok' }));
    const res = await post(merge, { method: 'merge', headSha: SHA });
    expect(await res.json()).toEqual({ ok: true, sha: OTHER_SHA });
    expect(call(fetchMock, 0)).toMatchObject({ url: `${API}/pulls/42`, method: 'GET' });
    expect(call(fetchMock, 1)).toMatchObject({
      url: `${API}/pulls/42/merge`,
      method: 'PUT',
      body: { merge_method: 'merge', sha: SHA },
    });
  });

  it.each([
    ['closed', { state: 'closed' }],
    ['changed since the user looked', { head: { sha: OTHER_SHA } }],
    ['not mergeable', { mergeable: false }],
    ['not computed yet', { mergeable: null }],
  ])('409 without merging when the pull request is %s', async (_case, over) => {
    const fetchMock = stubFetch(reply(200, openPull(over)));
    const res = await post(merge, { method: 'squash', headSha: SHA });
    expect(res.status).toBe(409);
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it('does not invalidate the dashboard on a 409', async () => {
    stubFetch(reply(200, openPull({ state: 'closed' })));
    await post(merge, { method: 'squash', headSha: SHA });
    expect(invalidate).not.toHaveBeenCalled();
  });

  it("502 with GitHub's message when the merge itself is refused", async () => {
    stubFetch(reply(200, openPull()), reply(405, { message: 'Required status check "ci" is expected.' }));
    const res = await post(merge, { method: 'squash', headSha: SHA });
    expect(res.status).toBe(502);
    expect((await res.json()).error).toBe('GitHub respondeu 405: Required status check "ci" is expected.');
  });
});

describe('POST .../rerun', () => {
  it('400 on an invalid head sha', async () => {
    const fetchMock = stubFetch();
    expect((await post(rerun, { headSha: 'main' })).status).toBe(400);
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it('re-runs the failed runs of the head commit and returns how many', async () => {
    const { total_count, workflow_runs } = runsFixture['acme/repo-4'];
    const fetchMock = stubFetch(
      reply(200, { total_count, workflow_runs }),
      ...workflow_runs.map(() => reply(201, {})),
    );
    const res = await post(rerun, { headSha: SHA });
    expect(await res.json()).toEqual({ ok: true, rerun: 5 });
    expect(call(fetchMock, 0)).toMatchObject({ url: `${API}/actions/runs?head_sha=${SHA}&per_page=20`, method: 'GET' });
    expect(call(fetchMock, 1)).toMatchObject({
      url: `${API}/actions/runs/${workflow_runs[0].id}/rerun-failed-jobs`,
      method: 'POST',
    });
  });

  it('returns 0 when no Actions run failed on the commit', async () => {
    const { total_count, workflow_runs } = runsFixture['acme/repo-1'];
    stubFetch(reply(200, { total_count, workflow_runs }));
    expect(await (await post(rerun, { headSha: SHA })).json()).toEqual({ ok: true, rerun: 0 });
  });
});
