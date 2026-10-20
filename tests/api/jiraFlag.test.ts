import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { NextRequest } from 'next/server';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import fieldsFixture from '../fixtures/jira-write/fields-flag-start.json';
import editmetaFixture from '../fixtures/jira-write/editmeta-story.json';

const currentUser = vi.fn();
vi.mock('@/lib/api/context', async (importOriginal) => ({
  ...(await importOriginal<typeof import('@/lib/api/context')>()),
  requireUser: async () => {
    const user = await currentUser();
    if (!user) return { ok: false, response: new Response('não autenticado', { status: 401 }) };
    return { ok: true, value: user };
  },
}));

import { POST } from '@/app/api/jira/issues/[key]/flag/route';
import { saveConnection, setModuleEnabled } from '@/lib/vault/connections';

const BASE = 'https://acme.atlassian.net';
const ME = { id: 'u-1', username: 'joao' };
let dir: string;

type Reply = { status: number; body?: unknown };

function stubJira(routes: Record<string, Reply>) {
  const fetchMock = vi.fn(async (url: string, init: RequestInit) => {
    const reply = routes[`${init.method} ${url.replace(BASE, '')}`];
    if (!reply) throw new Error(`unexpected request ${init.method} ${url}`);
    return {
      ok: reply.status < 400,
      status: reply.status,
      headers: { get: () => (reply.body === undefined ? '0' : null) },
      json: async () => reply.body,
      text: async () => (reply.body === undefined ? '' : JSON.stringify(reply.body)),
    };
  });
  vi.stubGlobal('fetch', fetchMock);
  return fetchMock;
}

const writes = (fetchMock: ReturnType<typeof stubJira>) =>
  fetchMock.mock.calls
    .filter(([, init]) => init.method !== 'GET')
    .map(([url, init]) => ({
      method: init.method,
      path: String(url).replace(BASE, ''),
      body: JSON.parse(String(init.body)),
    }));

const DISCOVERY = {
  'GET /rest/api/3/field': { status: 200, body: fieldsFixture },
  'GET /rest/api/3/issue/TT-5019/editmeta': { status: 200, body: editmetaFixture },
};

function post(key: string, body: unknown) {
  const request = new NextRequest(`http://localhost/api/jira/issues/${key}/flag`, {
    method: 'POST',
    body: JSON.stringify(body),
  });
  return POST(request, { params: Promise.resolve({ key }) });
}

const adf = (text: string) => ({
  type: 'doc',
  version: 1,
  content: [{ type: 'paragraph', content: [{ type: 'text', text }] }],
});

beforeEach(async () => {
  dir = mkdtempSync(path.join(tmpdir(), 'daily-web-flag-'));
  process.env.DAILY_WEB_DB_PATH = path.join(dir, 'test.db');
  process.env.DAILY_WEB_SECRET_KEY = Buffer.alloc(32, 'a').toString('base64');
  vi.clearAllMocks();
  currentUser.mockResolvedValue(ME);
  const { getDb } = await import('@/lib/db');
  getDb();
  saveConnection(ME.id, 'jira', 'Jira', { cloud: 'acme', email: 'eu@acme.com', token: 'x' });
  setModuleEnabled(ME.id, 'jira', true);
});

afterEach(() => {
  vi.unstubAllGlobals();
  rmSync(dir, { recursive: true, force: true });
});

describe('POST /api/jira/issues/[key]/flag', () => {
  it('401 without a session', async () => {
    currentUser.mockResolvedValue(null);
    expect((await post('TT-5019', { action: 'flag', reason: 'x' })).status).toBe(401);
  });

  it('400 with an invalid key', async () => {
    expect((await post('nao-e-chave', { action: 'flag', reason: 'x' })).status).toBe(400);
  });

  it('400 with an unknown action', async () => {
    const fetchMock = stubJira({});
    const res = await post('TT-5019', { action: 'toggle' });
    expect(res.status).toBe(400);
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it('400 when flagging without a reason', async () => {
    expect((await post('TT-5019', { action: 'flag', reason: '   ' })).status).toBe(400);
  });

  it('400 when the reason is longer than 2000 characters', async () => {
    expect((await post('TT-5019', { action: 'flag', reason: 'a'.repeat(2001) })).status).toBe(400);
  });

  it('400 when the unflag note is not text', async () => {
    expect((await post('TT-5019', { action: 'unflag', note: 42 })).status).toBe(400);
  });

  it('flags the issue and comments the trimmed reason', async () => {
    const fetchMock = stubJira({
      ...DISCOVERY,
      'PUT /rest/api/3/issue/TT-5019': { status: 204 },
      'POST /rest/api/3/issue/TT-5019/comment': { status: 201, body: { id: '900' } },
    });

    const res = await post('tt-5019', { action: 'flag', reason: '  aguardando API  ' });

    expect(res.status).toBe(200);
    expect(writes(fetchMock)).toEqual([
      { method: 'PUT', path: '/rest/api/3/issue/TT-5019', body: { fields: { customfield_10021: [{ id: '10019' }] } } },
      { method: 'POST', path: '/rest/api/3/issue/TT-5019/comment', body: { body: adf('Impedimento: aguardando API') } },
    ]);
  });

  it('unflags the issue and comments the note', async () => {
    const fetchMock = stubJira({
      ...DISCOVERY,
      'PUT /rest/api/3/issue/TT-5019': { status: 204 },
      'POST /rest/api/3/issue/TT-5019/comment': { status: 201, body: { id: '901' } },
    });

    const res = await post('TT-5019', { action: 'unflag', note: 'API liberada' });

    expect(res.status).toBe(200);
    expect(writes(fetchMock)).toEqual([
      { method: 'PUT', path: '/rest/api/3/issue/TT-5019', body: { fields: { customfield_10021: [] } } },
      { method: 'POST', path: '/rest/api/3/issue/TT-5019/comment', body: { body: adf('Impedimento removido: API liberada') } },
    ]);
  });

  it('unflags without a comment when no note is given', async () => {
    const fetchMock = stubJira({ ...DISCOVERY, 'PUT /rest/api/3/issue/TT-5019': { status: 204 } });

    const res = await post('TT-5019', { action: 'unflag' });

    expect(res.status).toBe(200);
    expect(writes(fetchMock)).toEqual([
      { method: 'PUT', path: '/rest/api/3/issue/TT-5019', body: { fields: { customfield_10021: [] } } },
    ]);
  });

  it('502 with Jira own message when the edit is refused', async () => {
    stubJira({
      ...DISCOVERY,
      'PUT /rest/api/3/issue/TT-5019': { status: 400, body: { errorMessages: ['Você não pode editar esta issue'] } },
    });

    const res = await post('TT-5019', { action: 'flag', reason: 'x' });

    expect(res.status).toBe(502);
    expect((await res.json()).error).toBe('Jira respondeu 400: Você não pode editar esta issue');
  });

  it('200 with a warning saying the flag changed when only the comment fails', async () => {
    stubJira({
      ...DISCOVERY,
      'PUT /rest/api/3/issue/TT-5019': { status: 204 },
      'POST /rest/api/3/issue/TT-5019/comment': { status: 400, body: { errorMessages: ['comentário recusado'] } },
    });

    const res = await post('TT-5019', { action: 'flag', reason: 'x' });

    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({
      ok: true,
      warning: 'o impedimento foi marcado, mas o comentário não foi gravado: Jira respondeu 400: comentário recusado',
    });
  });

  it('502 when the instance has no Impediment option', async () => {
    stubJira({
      'GET /rest/api/3/field': { status: 200, body: fieldsFixture },
      'GET /rest/api/3/issue/TT-5019/editmeta': {
        status: 200,
        body: { fields: { customfield_10021: { allowedValues: [] } } },
      },
    });

    const res = await post('TT-5019', { action: 'flag', reason: 'x' });

    expect(res.status).toBe(502);
    expect((await res.json()).error).toContain('opção "Impediment" ausente');
  });
});
