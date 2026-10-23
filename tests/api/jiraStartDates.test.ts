import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { NextRequest } from 'next/server';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import statuses from '@/tests/fixtures/jira-statuses.json';
import changelog from '@/tests/fixtures/jira-changelog.json';

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
vi.mock('@/lib/refresher', async (importOriginal) => ({ ...(await importOriginal<typeof import('@/lib/refresher')>()), invalidate: (id: string) => invalidate(id) }));

import { GET, POST } from '@/app/api/jira/problems/start-dates/route';
import { saveConnection, setModuleEnabled } from '@/lib/vault/connections';
import { setInstanceMetaForTests } from '@/lib/integrations/jiraApi';

let dir: string;
const ME = { id: 'u-1', username: 'joao' };
const JIRA = 'https://acme.atlassian.net';
const knownMeta = (startField: string | null) =>
  setInstanceMetaForTests(JIRA, { startField, flaggedField: null, priorityRank: new Map() });

function get(query: string): NextRequest {
  return new NextRequest(`http://localhost/api/jira/problems/start-dates${query}`);
}

function post(body: unknown): NextRequest {
  return new NextRequest('http://localhost/api/jira/problems/start-dates', {
    method: 'POST',
    body: JSON.stringify(body),
  });
}

const ok = (body: unknown) => ({ ok: true, status: 200, json: async () => body });
const noContent = () => ({ ok: true, status: 204, headers: new Headers() });
const refused = (status: number, body: unknown) => ({ ok: false, status, text: async () => JSON.stringify(body) });

function stubJira(respond: (path: string) => unknown) {
  const fetchMock = vi.fn(async (url: string, _init?: RequestInit) => respond(url.replace(JIRA, '')));
  vi.stubGlobal('fetch', fetchMock);
  return fetchMock;
}

beforeEach(async () => {
  dir = mkdtempSync(path.join(tmpdir(), 'daily-web-start-dates-'));
  process.env.DAILY_WEB_DB_PATH = path.join(dir, 'test.db');
  process.env.DAILY_WEB_SECRET_KEY = Buffer.alloc(32, 'a').toString('base64');
  vi.clearAllMocks();
  knownMeta('customfield_10015');
  currentUser.mockResolvedValue(ME);
  const { getDb } = await import('@/lib/db');
  getDb();
  saveConnection(ME.id, 'jira', 'Jira', { cloud: 'acme', email: 'eu@acme', token: 'x' });
  setModuleEnabled(ME.id, 'jira', true);
});

afterEach(() => {
  vi.unstubAllGlobals();
  setInstanceMetaForTests(JIRA, null);
  rmSync(dir, { recursive: true, force: true });
});

describe('GET /api/jira/problems/start-dates', () => {
  it('401 without a session', async () => {
    currentUser.mockResolvedValue(null);
    expect((await GET(get('?keys=TT-1'))).status).toBe(401);
  });

  it('400 on a missing, malformed or oversized key list, without calling Jira', async () => {
    const fetchMock = stubJira(() => ok({}));
    const tooMany = Array.from({ length: 51 }, (_, i) => `TT-${i + 1}`).join(',');
    for (const query of ['', '?keys=', '?keys=TT-1,nope', '?keys=TT-1/../x', `?keys=${tooMany}`]) {
      expect((await GET(get(query))).status).toBe(400);
    }
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it('suggests the first in-progress day read from the changelog', async () => {
    const issue = { fields: { created: '2026-10-01T10:00:00.000-0300', status: { statusCategory: { key: 'indeterminate' } } } };
    const fetchMock = stubJira((p) => {
      if (p === '/rest/api/3/status') return ok(statuses);
      return ok(p.includes('/changelog') ? changelog : issue);
    });
    const res = await GET(get('?keys=tt-5016'));
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({
      suggestions: [{ key: 'TT-5016', status: 'suggested', date: '2026-10-20', basis: 'started' }],
    });
    expect(fetchMock.mock.calls.map(([url]) => url).sort()).toEqual([
      `${JIRA}/rest/api/3/issue/TT-5016/changelog?startAt=0&maxResults=100`,
      `${JIRA}/rest/api/3/issue/TT-5016?fields=created,status`,
      `${JIRA}/rest/api/3/status`,
    ]);
    expect(fetchMock.mock.calls.every(([, init]) => init?.method === 'GET')).toBe(true);
  });

  it('reports an issue whose history says nothing as unavailable', async () => {
    const issue = { fields: { created: '2026-10-01T10:00:00.000-0300', status: { statusCategory: { key: 'new' } } } };
    stubJira((p) => {
      if (p === '/rest/api/3/status') return ok(statuses);
      return ok(p.includes('/changelog') ? { isLast: true, values: [] } : issue);
    });
    const res = await GET(get('?keys=TT-1,TT-2'));
    expect(res.status).toBe(502);
    expect((await res.json()).error).toBe('o histórico não diz quando começou');
  });

  it('502 with Jira message when no issue could be read', async () => {
    stubJira(() => refused(400, { errorMessages: ['Você não tem permissão'] }));
    const res = await GET(get('?keys=TT-1'));
    expect(res.status).toBe(502);
    expect((await res.json()).error).toBe('Jira respondeu 400: Você não tem permissão');
  });
});

describe('POST /api/jira/problems/start-dates', () => {
  it('401 without a session', async () => {
    currentUser.mockResolvedValue(null);
    expect((await POST(post({ items: [{ key: 'TT-1', date: '2026-10-01' }] }))).status).toBe(401);
  });

  it('400 on an invalid body, without calling Jira', async () => {
    const fetchMock = stubJira(() => ok({}));
    const many = Array.from({ length: 51 }, (_, i) => ({ key: `TT-${i + 1}`, date: '2026-10-01' }));
    const bodies = [
      null,
      {},
      { items: [] },
      { items: many },
      { items: ['TT-1'] },
      { items: [{ key: 'nope', date: '2026-10-01' }] },
      { items: [{ key: 'TT-1', date: '2026-02-30' }] },
      { items: [{ key: 'TT-1', date: '01/10/2026' }] },
      { items: [{ key: 'TT-1', date: '2999-01-01' }] },
      { items: [{ key: 'TT-1', date: '2026-10-01' }, { key: 'tt-1', date: '2026-10-02' }] },
    ];
    for (const body of bodies) expect((await POST(post(body))).status).toBe(400);
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it('writes each date to the start field and drops the cached state', async () => {
    const fetchMock = stubJira(() => noContent());
    const res = await POST(post({ items: [{ key: 'TT-1', date: '2026-10-01' }, { key: 'TT-2', date: '2026-10-02' }] }));
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({
      ok: true,
      results: [
        { key: 'TT-1', outcome: 'written' },
        { key: 'TT-2', outcome: 'written' },
      ],
    });
    const puts = fetchMock.mock.calls.filter(([, init]) => init?.method === 'PUT');
    expect(puts.map(([url, init]) => [url, init?.body])).toEqual([
      [`${JIRA}/rest/api/3/issue/TT-1`, JSON.stringify({ fields: { customfield_10015: '2026-10-01' } })],
      [`${JIRA}/rest/api/3/issue/TT-2`, JSON.stringify({ fields: { customfield_10015: '2026-10-02' } })],
    ]);
    expect(invalidate).toHaveBeenCalledWith(ME.id);
  });

  it('200 with partial refusals carrying Jira message', async () => {
    stubJira((p) => {
      if (p === '/rest/api/3/issue/TT-1') return refused(400, { errors: { customfield_10015: 'campo não pode ser alterado' } });
      return noContent();
    });
    const res = await POST(post({ items: [{ key: 'TT-1', date: '2026-10-01' }, { key: 'TT-2', date: '2026-10-02' }] }));
    expect(res.status).toBe(200);
    expect((await res.json()).results).toEqual([
      { key: 'TT-1', outcome: 'refused', error: 'Jira respondeu 400: customfield_10015: campo não pode ser alterado' },
      { key: 'TT-2', outcome: 'written' },
    ]);
  });

  it('200 without dropping the cache when every issue was refused', async () => {
    stubJira(() => refused(400, { errorMessages: ['não'] }));
    const res = await POST(post({ items: [{ key: 'TT-1', date: '2026-10-01' }] }));
    expect(res.status).toBe(200);
    expect((await res.json()).results).toEqual([{ key: 'TT-1', outcome: 'refused', error: 'Jira respondeu 400: não' }]);
    expect(invalidate).not.toHaveBeenCalled();
  });

  it('502 without writing when the instance has no start field', async () => {
    knownMeta(null);
    const fetchMock = stubJira(() => noContent());
    const res = await POST(post({ items: [{ key: 'TT-1', date: '2026-10-01' }] }));
    expect(res.status).toBe(502);
    expect((await res.json()).error).toBe('campo "Start date" não encontrado no Jira');
    expect(fetchMock).not.toHaveBeenCalled();
  });
});
