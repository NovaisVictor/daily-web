import { describe, expect, it, beforeEach, afterEach, vi } from 'vitest';
import { NextRequest } from 'next/server';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import issueTypes from '../fixtures/jira-write/createmeta-issuetypes.json';

const currentUser = vi.fn();
vi.mock('@/lib/api/context', async (importOriginal) => {
  const actual = await importOriginal<typeof import('@/lib/api/context')>();
  return {
    ...actual,
    requireUser: async () => {
      const user = await currentUser();
      if (!user) return { ok: false, response: new Response('não autenticado', { status: 401 }) };
      return { ok: true, value: user };
    },
  };
});

import { POST } from '@/app/api/jira/issues/[key]/stories/route';
import { saveConnection, setModuleEnabled } from '@/lib/vault/connections';

let dir: string;
const ME = { id: 'u-1', username: 'joao' };
const BASE = 'https://acme.atlassian.net';

const epic = { key: 'TT-2376', fields: { project: { key: 'TT' }, issuetype: { id: '10000', name: 'Epic', hierarchyLevel: 1 } } };
const story = { key: 'TT-5019', fields: { project: { key: 'TT' }, issuetype: { id: '10005', name: 'História', hierarchyLevel: 0 } } };

function post(key: string, body: unknown) {
  const req = new NextRequest(`http://localhost/api/jira/issues/${key}/stories`, {
    method: 'POST',
    body: JSON.stringify(body),
  });
  return POST(req, { params: Promise.resolve({ key }) });
}

function json(status: number, body: unknown) {
  return { ok: status < 400, status, headers: new Headers(), json: async () => body, text: async () => JSON.stringify(body) };
}

function calls(fetchMock: ReturnType<typeof vi.fn>) {
  return fetchMock.mock.calls.map(([url, init]) => ({
    url: String(url),
    method: (init as RequestInit).method,
    body: (init as RequestInit).body ? JSON.parse(String((init as RequestInit).body)) : undefined,
  }));
}

beforeEach(async () => {
  dir = mkdtempSync(path.join(tmpdir(), 'daily-web-jira-stories-'));
  process.env.DAILY_WEB_DB_PATH = path.join(dir, 'test.db');
  process.env.DAILY_WEB_SECRET_KEY = Buffer.alloc(32, 'a').toString('base64');
  vi.clearAllMocks();
  currentUser.mockResolvedValue(ME);
  const { getDb } = await import('@/lib/db');
  getDb();
  saveConnection(ME.id, 'jira', 'Jira', { cloud: 'acme', email: 'eu@acme', token: 'x' });
  setModuleEnabled(ME.id, 'jira', true);
});

afterEach(() => {
  vi.unstubAllGlobals();
  rmSync(dir, { recursive: true, force: true });
});

describe('POST /api/jira/issues/[key]/stories', () => {
  it('401 without a session', async () => {
    currentUser.mockResolvedValue(null);
    expect((await post('TT-2376', { summary: 'Nova' })).status).toBe(401);
  });

  it('400 on a bad key', async () => {
    expect((await post('épico', { summary: 'Nova' })).status).toBe(400);
  });

  it('400 on an empty, too long or non-text summary, without calling Jira', async () => {
    const fetchMock = vi.fn();
    vi.stubGlobal('fetch', fetchMock);
    for (const body of [{ summary: '   ' }, { summary: 'x'.repeat(256) }, { summary: 3 }, { summary: 'ok', description: [] }, null]) {
      expect((await post('TT-2376', body)).status).toBe(400);
    }
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it('creates a História under the epic and returns its key', async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(json(200, epic))
      .mockResolvedValueOnce(json(200, issueTypes))
      .mockResolvedValueOnce(json(201, { id: '90001', key: 'TT-9999', self: `${BASE}/rest/api/3/issue/90001` }));
    vi.stubGlobal('fetch', fetchMock);

    const res = await post('tt-2376', { summary: '  Nova história  ', description: 'linha 1\n\nlinha 2' });
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ ok: true, key: 'TT-9999', url: `${BASE}/browse/TT-9999` });
    expect(calls(fetchMock)).toEqual([
      { url: `${BASE}/rest/api/3/issue/TT-2376?fields=project,issuetype`, method: 'GET', body: undefined },
      { url: `${BASE}/rest/api/3/issue/createmeta/TT/issuetypes`, method: 'GET', body: undefined },
      {
        url: `${BASE}/rest/api/3/issue`,
        method: 'POST',
        body: {
          fields: {
            project: { key: 'TT' },
            issuetype: { id: '10005' },
            summary: 'Nova história',
            parent: { key: 'TT-2376' },
            description: {
              type: 'doc',
              version: 1,
              content: [
                { type: 'paragraph', content: [{ type: 'text', text: 'linha 1' }] },
                { type: 'paragraph', content: [{ type: 'text', text: 'linha 2' }] },
              ],
            },
          },
        },
      },
    ]);
  });

  it('leaves the description out when none is given', async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(json(200, epic))
      .mockResolvedValueOnce(json(200, issueTypes))
      .mockResolvedValueOnce(json(201, { id: '90001', key: 'TT-9999' }));
    vi.stubGlobal('fetch', fetchMock);
    expect((await post('TT-2376', { summary: 'Nova' })).status).toBe(200);
    expect(calls(fetchMock)[2].body.fields).not.toHaveProperty('description');
  });

  it('400 when the issue is not an epic, without creating anything', async () => {
    const fetchMock = vi.fn().mockResolvedValueOnce(json(200, story));
    vi.stubGlobal('fetch', fetchMock);
    const res = await post('TT-5019', { summary: 'Nova' });
    expect(res.status).toBe(400);
    expect(await res.json()).toEqual({ error: 'TT-5019 não é um épico' });
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it('502 with a clear message when the project has no story type', async () => {
    const onlyBug = { issueTypes: issueTypes.issueTypes.filter((t) => t.name !== 'História') };
    const fetchMock = vi.fn().mockResolvedValueOnce(json(200, epic)).mockResolvedValueOnce(json(200, onlyBug));
    vi.stubGlobal('fetch', fetchMock);
    const res = await post('TT-2376', { summary: 'Nova' });
    expect(res.status).toBe(502);
    expect((await res.json()).error).toMatch(/não tem um tipo História/);
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  it("502 with Jira's own message when Jira refuses the create", async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(json(200, epic))
      .mockResolvedValueOnce(json(200, issueTypes))
      .mockResolvedValueOnce(json(400, { errorMessages: [], errors: { parent: 'Pai inválido.' } }));
    vi.stubGlobal('fetch', fetchMock);
    const res = await post('TT-2376', { summary: 'Nova' });
    expect(res.status).toBe(502);
    expect(await res.json()).toEqual({ error: 'Jira respondeu 400: parent: Pai inválido.' });
  });

  it('502 telling to check the epic before retrying when the create times out', async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(json(200, epic))
      .mockResolvedValueOnce(json(200, issueTypes))
      .mockRejectedValueOnce(new DOMException('The operation was aborted due to timeout', 'TimeoutError'));
    vi.stubGlobal('fetch', fetchMock);
    const res = await post('TT-2376', { summary: 'Nova' });
    expect(res.status).toBe(502);
    expect(await res.json()).toEqual({
      error: 'o Jira demorou a responder — confira no épico se a história foi criada antes de tentar de novo',
    });
  });

  it('502 saying the epic or project is missing when the create answers 404', async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(json(200, epic))
      .mockResolvedValueOnce(json(200, issueTypes))
      .mockResolvedValueOnce(json(404, {}));
    vi.stubGlobal('fetch', fetchMock);
    const res = await post('TT-2376', { summary: 'Nova' });
    expect(await res.json()).toEqual({ error: 'épico ou projeto não encontrado no Jira' });
  });
});
