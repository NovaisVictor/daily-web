import { describe, expect, it, beforeEach, afterEach, vi } from 'vitest';
import { NextRequest } from 'next/server';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';

const currentUser = vi.fn();
vi.mock('@/lib/api/context', () => ({
  requireUser: async () => {
    const user = await currentUser();
    if (!user) return { ok: false, response: new Response('não autenticado', { status: 401 }) };
    return { ok: true, value: user };
  },
}));

const resolveJiraProblem = vi.fn();
vi.mock('@/lib/refresher', () => ({
  resolveJiraProblem: (...args: unknown[]) => resolveJiraProblem(...args),
  panel: async <T,>(fn: () => Promise<T>) => ({ data: await fn(), error: null }),
}));

import { GET as getStartDate, PUT as putStartDate } from '@/app/api/jira/issues/[key]/start-date/route';
import { PUT as putParent } from '@/app/api/jira/issues/[key]/parent/route';
import { GET as getEpics } from '@/app/api/jira/epics/route';
import { saveConnection, setModuleEnabled } from '@/lib/vault/connections';
import { setInstanceMetaForTests } from '@/lib/integrations/jiraApi';
import statusesFixture from '../fixtures/jira-statuses.json';
import changelogFixture from '../fixtures/jira-changelog.json';

let dir: string;
const ME = { id: 'u-1', username: 'joao' };
const BASE_URL = 'https://acme.atlassian.net';

function req(method: string, url: string, body?: unknown): NextRequest {
  return new NextRequest(`http://localhost${url}`, {
    method,
    ...(body !== undefined ? { body: JSON.stringify(body) } : {}),
  });
}

const params = (key: string) => ({ params: Promise.resolve({ key }) });

function connectJira() {
  saveConnection(ME.id, 'jira', 'Jira', { cloud: 'acme', email: 'eu@acme', token: 'x' });
  setModuleEnabled(ME.id, 'jira', true);
}

function stubJira(handler: (url: URL, init?: RequestInit) => { status: number; body?: unknown }) {
  const fetchMock = vi.fn(async (raw: string, init?: RequestInit) => {
    const { status, body } = handler(new URL(raw), init);
    return { ok: status < 400, status, json: async () => body, text: async () => JSON.stringify(body ?? '') };
  });
  vi.stubGlobal('fetch', fetchMock);
  return fetchMock;
}

const epicIssue = (key: string) => ({
  key,
  fields: {
    summary: `Épico ${key}`,
    status: { name: 'Em andamento', statusCategory: { key: 'indeterminate' } },
    project: { key: key.split('-')[0] },
    issuetype: { name: 'Epic', subtask: false, hierarchyLevel: 1 },
  },
});

beforeEach(async () => {
  dir = mkdtempSync(path.join(tmpdir(), 'daily-web-jira-fix-'));
  process.env.DAILY_WEB_DB_PATH = path.join(dir, 'test.db');
  process.env.DAILY_WEB_SECRET_KEY = Buffer.alloc(32, 'a').toString('base64');
  vi.clearAllMocks();
  currentUser.mockResolvedValue(ME);
  setInstanceMetaForTests(BASE_URL, {
    startField: 'customfield_10015',
    flaggedField: null,
    priorityRank: new Map(),
  });
  const { getDb } = await import('@/lib/db');
  getDb();
});

afterEach(() => {
  vi.unstubAllGlobals();
  setInstanceMetaForTests(BASE_URL, null);
  rmSync(dir, { recursive: true, force: true });
});

describe('/api/jira/issues/[key]/start-date', () => {
  it('401 sem sessão', async () => {
    currentUser.mockResolvedValue(null);
    expect((await getStartDate(req('GET', '/x'), params('TT-1'))).status).toBe(401);
    expect((await putStartDate(req('PUT', '/x', { date: '2026-10-20' }), params('TT-1'))).status).toBe(401);
  });

  it('400 com chave ou data inválida, sem ir ao Jira', async () => {
    connectJira();
    const fetchMock = stubJira(() => ({ status: 500 }));
    expect((await getStartDate(req('GET', '/x'), params('TT 1'))).status).toBe(400);
    expect((await putStartDate(req('PUT', '/x', { date: '2026-02-30' }), params('TT-1'))).status).toBe(400);
    expect((await putStartDate(req('PUT', '/x', {}), params('TT-1'))).status).toBe(400);
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it('400 sem conexão do Jira', async () => {
    expect((await getStartDate(req('GET', '/x'), params('TT-1'))).status).toBe(400);
  });

  it('GET sugere a data pelo histórico', async () => {
    connectJira();
    stubJira((url) =>
      url.pathname === '/rest/api/3/status'
        ? { status: 200, body: statusesFixture }
        : { status: 200, body: changelogFixture },
    );
    const res = await getStartDate(req('GET', '/x'), params('tt-5016'));
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ date: '2026-10-20' });
  });

  it('PUT grava e tira o problema da lista', async () => {
    connectJira();
    const fetchMock = stubJira(() => ({ status: 204 }));
    const res = await putStartDate(req('PUT', '/x', { date: '2026-10-20' }), params('tt-1'));
    expect(res.status).toBe(200);
    expect(String(fetchMock.mock.calls[0][0])).toBe(`${BASE_URL}/rest/api/3/issue/TT-1`);
    expect(resolveJiraProblem).toHaveBeenCalledWith(ME.id, 'TT-1', [
      'story-in-progress-without-start',
      'story-done-without-start',
    ]);
  });

  it('502 com a mensagem do Jira, sem mexer na lista', async () => {
    connectJira();
    stubJira(() => ({ status: 400, body: { errors: { customfield_10015: 'campo não editável' } } }));
    const res = await putStartDate(req('PUT', '/x', { date: '2026-10-20' }), params('TT-1'));
    expect(res.status).toBe(502);
    expect((await res.json()).error).toContain('campo não editável');
    expect(resolveJiraProblem).not.toHaveBeenCalled();
  });
});

describe('/api/jira/issues/[key]/parent', () => {
  it('401 sem sessão', async () => {
    currentUser.mockResolvedValue(null);
    expect((await putParent(req('PUT', '/x', { epic: 'TT-10' }), params('TT-1'))).status).toBe(401);
  });

  it('400 com chave inválida', async () => {
    connectJira();
    expect((await putParent(req('PUT', '/x', { epic: 'TT-10" OR 1=1' }), params('TT-1'))).status).toBe(400);
    expect((await putParent(req('PUT', '/x', { epic: 'TT-10' }), params('nada'))).status).toBe(400);
  });

  it('400 sem conexão do Jira', async () => {
    expect((await putParent(req('PUT', '/x', { epic: 'TT-10' }), params('TT-1'))).status).toBe(400);
  });

  it('grava e tira os dois problemas resolvidos', async () => {
    connectJira();
    stubJira((url) =>
      url.pathname.endsWith('/search/jql')
        ? { status: 200, body: { issues: [epicIssue('TT-10')] } }
        : { status: 204 },
    );
    const res = await putParent(req('PUT', '/x', { epic: 'tt-10' }), params('TT-1'));
    expect(res.status).toBe(200);
    expect(resolveJiraProblem).toHaveBeenCalledWith(ME.id, 'TT-1', ['story-without-epic']);
    expect(resolveJiraProblem).toHaveBeenCalledWith(ME.id, 'TT-10', ['epic-without-stories']);
  });

  it('502 quando o pai é de outro projeto', async () => {
    connectJira();
    const fetchMock = stubJira(() => ({ status: 200, body: { issues: [epicIssue('CYB-10')] } }));
    const res = await putParent(req('PUT', '/x', { epic: 'CYB-10' }), params('TT-1'));
    expect(res.status).toBe(502);
    expect((await res.json()).error).toBe('CYB-10 é de outro projeto');
    expect(fetchMock).toHaveBeenCalledTimes(1);
    expect(resolveJiraProblem).not.toHaveBeenCalled();
  });
});

describe('/api/jira/epics', () => {
  it('401 sem sessão', async () => {
    currentUser.mockResolvedValue(null);
    expect((await getEpics(req('GET', '/api/jira/epics?project=TT'))).status).toBe(401);
  });

  it('400 com projeto ausente ou fora do formato', async () => {
    connectJira();
    expect((await getEpics(req('GET', '/api/jira/epics'))).status).toBe(400);
    expect((await getEpics(req('GET', '/api/jira/epics?project=TT%22%20OR%201%3D1'))).status).toBe(400);
  });

  it('400 sem conexão do Jira', async () => {
    expect((await getEpics(req('GET', '/api/jira/epics?project=TT'))).status).toBe(400);
  });

  it('devolve chave e resumo dos épicos abertos', async () => {
    connectJira();
    stubJira(() => ({ status: 200, body: { issues: [epicIssue('TT-10')] } }));
    const res = await getEpics(req('GET', '/api/jira/epics?project=tt'));
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ epics: [{ key: 'TT-10', summary: 'Épico TT-10' }] });
  });

  it('502 quando o Jira recusa', async () => {
    connectJira();
    stubJira(() => ({ status: 401 }));
    expect((await getEpics(req('GET', '/api/jira/epics?project=TT'))).status).toBe(502);
  });
});
