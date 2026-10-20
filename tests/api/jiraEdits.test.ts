import { describe, expect, it, beforeEach, afterEach, vi } from 'vitest';
import { NextRequest } from 'next/server';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import priorities from '../fixtures/jira-write/priorities.json';
import myself from '../fixtures/jira-write/myself.json';
import flagged from '../fixtures/jira-write/issue-flagged.json';

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

import { GET, PUT } from '@/app/api/jira/issues/[key]/fields/route';
import { saveConnection, setModuleEnabled } from '@/lib/vault/connections';

let dir: string;
const ME = { id: 'u-1', username: 'joao' };
const BASE = 'https://acme.atlassian.net';

function put(key: string, body: unknown) {
  const req = new NextRequest(`http://localhost/api/jira/issues/${key}/fields`, {
    method: 'PUT',
    body: JSON.stringify(body),
  });
  return PUT(req, { params: Promise.resolve({ key }) });
}

function get(key: string, query = '?options=priority') {
  const req = new NextRequest(`http://localhost/api/jira/issues/${key}/fields${query}`);
  return GET(req, { params: Promise.resolve({ key }) });
}

function json(status: number, body: unknown) {
  return { ok: status < 400, status, headers: new Headers(), json: async () => body, text: async () => JSON.stringify(body) };
}

const noContent = { ok: true, status: 204, headers: new Headers(), json: async () => null, text: async () => '' };

function calls(fetchMock: ReturnType<typeof vi.fn>) {
  return fetchMock.mock.calls.map(([url, init]) => ({
    url: String(url),
    method: (init as RequestInit).method,
    body: (init as RequestInit).body ? JSON.parse(String((init as RequestInit).body)) : undefined,
  }));
}

beforeEach(async () => {
  dir = mkdtempSync(path.join(tmpdir(), 'daily-web-jira-edits-'));
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

describe('PUT /api/jira/issues/[key]/fields', () => {
  it('401 without a session', async () => {
    currentUser.mockResolvedValue(null);
    expect((await put('TT-1', { change: 'assign-self' })).status).toBe(401);
  });

  it('400 on a bad key', async () => {
    expect((await put('nope', { change: 'assign-self' })).status).toBe(400);
  });

  it('400 on an unknown change or a malformed value, without calling Jira', async () => {
    const fetchMock = vi.fn();
    vi.stubGlobal('fetch', fetchMock);
    for (const body of [
      { change: 'summary', summary: 'x' },
      { change: 'due', dueDate: '2026-13-01' },
      { change: 'due', dueDate: '31/10/2026' },
      { change: 'priority', priorityId: 'Alta' },
      null,
    ]) {
      expect((await put('TT-1', body)).status).toBe(400);
    }
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it('sets the due date', async () => {
    const fetchMock = vi.fn().mockResolvedValue(noContent);
    vi.stubGlobal('fetch', fetchMock);
    const res = await put('TT-1', { change: 'due', dueDate: '2026-10-31' });
    expect(res.status).toBe(200);
    expect(calls(fetchMock)).toEqual([
      { url: `${BASE}/rest/api/3/issue/TT-1`, method: 'PUT', body: { fields: { duedate: '2026-10-31' } } },
    ]);
  });

  it('clears the due date', async () => {
    const fetchMock = vi.fn().mockResolvedValue(noContent);
    vi.stubGlobal('fetch', fetchMock);
    expect((await put('TT-1', { change: 'due', dueDate: null })).status).toBe(200);
    expect(calls(fetchMock)[0].body).toEqual({ fields: { duedate: null } });
  });

  it('sets a priority that exists', async () => {
    const fetchMock = vi.fn().mockResolvedValueOnce(json(200, priorities)).mockResolvedValueOnce(noContent);
    vi.stubGlobal('fetch', fetchMock);
    expect((await put('TT-1', { change: 'priority', priorityId: '2' })).status).toBe(200);
    expect(calls(fetchMock)).toEqual([
      { url: `${BASE}/rest/api/3/priority`, method: 'GET', body: undefined },
      { url: `${BASE}/rest/api/3/issue/TT-1`, method: 'PUT', body: { fields: { priority: { id: '2' } } } },
    ]);
  });

  it('400 for a priority id Jira does not list, without writing', async () => {
    const fetchMock = vi.fn().mockResolvedValueOnce(json(200, priorities));
    vi.stubGlobal('fetch', fetchMock);
    const res = await put('TT-1', { change: 'priority', priorityId: '99' });
    expect(res.status).toBe(400);
    expect(await res.json()).toEqual({ error: 'prioridade desconhecida' });
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it('assigns to the logged-in account', async () => {
    const fetchMock = vi.fn().mockResolvedValueOnce(json(200, myself)).mockResolvedValueOnce(noContent);
    vi.stubGlobal('fetch', fetchMock);
    expect((await put('TT-1', { change: 'assign-self' })).status).toBe(200);
    expect(calls(fetchMock)).toEqual([
      { url: `${BASE}/rest/api/3/myself`, method: 'GET', body: undefined },
      {
        url: `${BASE}/rest/api/3/issue/TT-1/assignee`,
        method: 'PUT',
        body: { accountId: '557058:00000000-0000-0000-0000-000000000001' },
      },
    ]);
  });

  it("502 with Jira's own message when Jira refuses", async () => {
    const fetchMock = vi.fn().mockResolvedValue(json(400, { errorMessages: [], errors: { duedate: 'Data inválida.' } }));
    vi.stubGlobal('fetch', fetchMock);
    const res = await put('TT-1', { change: 'due', dueDate: '2026-10-31' });
    expect(res.status).toBe(502);
    expect(await res.json()).toEqual({ error: 'Jira respondeu 400: duedate: Data inválida.' });
  });
});

describe('GET /api/jira/issues/[key]/fields?options=priority', () => {
  it('401 without a session', async () => {
    currentUser.mockResolvedValue(null);
    expect((await get('TT-1')).status).toBe(401);
  });

  it('400 on a bad key or unknown options', async () => {
    expect((await get('nope')).status).toBe(400);
    expect((await get('TT-1', '?options=status')).status).toBe(400);
  });

  it('returns the list and the current priority', async () => {
    const fetchMock = vi.fn(async (url: string) =>
      url.endsWith('/priority') ? json(200, priorities) : json(200, flagged),
    );
    vi.stubGlobal('fetch', fetchMock);
    const res = await get('TT-5007');
    expect(res.status).toBe(200);
    const data = await res.json();
    expect(data.current).toEqual({ id: '5', name: 'Trivial' });
    expect(data.priorities.map((p: { name: string }) => p.name)).toEqual(['Crítica', 'Alta', 'Média', 'Baixa', 'Trivial']);
    expect(calls(fetchMock).map((c) => c.url).sort()).toEqual([
      `${BASE}/rest/api/3/issue/TT-5007?fields=priority`,
      `${BASE}/rest/api/3/priority`,
    ]);
  });

  it('502 when Jira answers an unexpected shape', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(json(200, { values: [] })));
    const res = await get('TT-1');
    expect(res.status).toBe(502);
    expect((await res.json()).error).toMatch(/resposta inesperada do Jira/);
  });
});
