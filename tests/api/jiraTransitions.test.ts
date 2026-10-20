import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { NextRequest } from 'next/server';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import story from '../fixtures/jira-write/transitions-story.json';

const currentUser = vi.fn();
vi.mock('@/lib/auth/currentUser', () => ({ getCurrentUser: () => currentUser() }));

import { GET, POST } from '@/app/api/jira/issues/[key]/transitions/route';
import { saveConnection, setModuleEnabled } from '@/lib/vault/connections';

let dir: string;
const ME = { id: 'u-1', username: 'joao' };
const ISSUE_STATUS = { fields: { status: { id: '11540', name: 'Em Andamento' } } };

function req(method: string, body?: unknown): NextRequest {
  return new NextRequest('http://localhost/api/jira/issues/TT-5019/transitions', {
    method,
    ...(body === undefined ? {} : { body: typeof body === 'string' ? body : JSON.stringify(body) }),
  });
}

const params = (key: string) => ({ params: Promise.resolve({ key }) });

function connect() {
  saveConnection(ME.id, 'jira', 'Jira', { cloud: 'acme', email: 'eu@acme', token: 'x' });
  setModuleEnabled(ME.id, 'jira', true);
}

function stubJira(write: unknown = { ok: true, status: 204, json: async () => null }) {
  const fetchMock = vi.fn(async (url: string, init: RequestInit) => {
    if (init.method === 'POST') return write;
    const body = url.includes('/transitions') ? story : ISSUE_STATUS;
    return { ok: true, status: 200, json: async () => body };
  });
  vi.stubGlobal('fetch', fetchMock);
  return fetchMock;
}

beforeEach(async () => {
  dir = mkdtempSync(path.join(tmpdir(), 'daily-web-transitions-'));
  process.env.DAILY_WEB_DB_PATH = path.join(dir, 'test.db');
  process.env.DAILY_WEB_SECRET_KEY = Buffer.alloc(32, 'a').toString('base64');
  vi.clearAllMocks();
  currentUser.mockResolvedValue(ME);
  const { getDb } = await import('@/lib/db');
  getDb();
});

afterEach(() => {
  vi.unstubAllGlobals();
  rmSync(dir, { recursive: true, force: true });
});

describe('GET /api/jira/issues/[key]/transitions', () => {
  it('401 without a session', async () => {
    currentUser.mockResolvedValue(null);
    expect((await GET(req('GET'), params('TT-5019'))).status).toBe(401);
  });

  it('400 with an invalid key', async () => {
    connect();
    expect((await GET(req('GET'), params('not a key'))).status).toBe(400);
  });

  it('lists the transitions parsed from Jira', async () => {
    connect();
    stubJira();
    const res = await GET(req('GET'), params('tt-5019'));
    expect(res.status).toBe(200);
    const { transitions } = await res.json();
    expect(transitions).toHaveLength(10);
    expect(transitions[0]).toEqual({
      id: '2',
      name: 'Em Discovery',
      to: { name: 'Discovery', category: 'new' },
      requires: 'nothing',
    });
  });

  it("502 with Jira's message when Jira refuses", async () => {
    connect();
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue({ ok: false, status: 500, text: async () => JSON.stringify({ errorMessages: ['Jira fora do ar'] }) }),
    );
    const res = await GET(req('GET'), params('TT-5019'));
    expect(res.status).toBe(502);
    expect((await res.json()).error).toContain('Jira fora do ar');
  });
});

describe('POST /api/jira/issues/[key]/transitions', () => {
  it('401 without a session', async () => {
    currentUser.mockResolvedValue(null);
    expect((await POST(req('POST', { transitionId: '41' }), params('TT-5019'))).status).toBe(401);
  });

  it('400 with an invalid key', async () => {
    connect();
    expect((await POST(req('POST', { transitionId: '41' }), params('TT_5019'))).status).toBe(400);
  });

  it.each([[{}], [{ transitionId: 41 }], [{ transitionId: '41a' }], [{ transitionId: '' }], ['not json']])(
    '400 with an invalid body %j',
    async (body) => {
      connect();
      const fetchMock = stubJira();
      expect((await POST(req('POST', body), params('TT-5019'))).status).toBe(400);
      expect(fetchMock).not.toHaveBeenCalled();
    },
  );

  it('409 when the transition is no longer available, without writing', async () => {
    connect();
    const fetchMock = stubJira();
    const res = await POST(req('POST', { transitionId: '999' }), params('TT-5019'));
    expect(res.status).toBe(409);
    expect((await res.json()).error).toBe('essa transição não está mais disponível');
    expect(fetchMock.mock.calls.some(([, init]) => init.method === 'POST')).toBe(false);
  });

  it("502 with Jira's message when Jira refuses the transition", async () => {
    connect();
    stubJira({
      ok: false,
      status: 400,
      text: async () => JSON.stringify({ errorMessages: ['O campo Resolução é obrigatório'] }),
    });
    const res = await POST(req('POST', { transitionId: '41' }), params('TT-5019'));
    expect(res.status).toBe(502);
    expect((await res.json()).error).toContain('O campo Resolução é obrigatório');
  });

  it('posts the transition to Jira and answers ok', async () => {
    connect();
    const fetchMock = stubJira();
    const res = await POST(req('POST', { transitionId: '41' }), params('TT-5019'));
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ ok: true });
    const post = fetchMock.mock.calls.find(([, init]) => init.method === 'POST');
    expect(post?.[0]).toBe('https://acme.atlassian.net/rest/api/3/issue/TT-5019/transitions');
    expect(JSON.parse(String(post?.[1].body))).toEqual({ transition: { id: '41' } });
  });
});
