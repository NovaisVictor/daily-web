import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { NextRequest } from 'next/server';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import story from '../fixtures/jira-write/transitions-story.json';

const currentUser = vi.fn();
vi.mock('@/lib/auth/currentUser', () => ({ getCurrentUser: () => currentUser() }));

import { GET } from '@/app/api/pulls/jira-sync/route';
import { saveConnection, setModuleEnabled } from '@/lib/vault/connections';

let dir: string;
const ME = { id: 'u-1', username: 'joao' };
const BACKLOG = { fields: { status: { id: '10175', name: 'Backlog' } } };
const ONLY_NEW_AND_DONE = {
  transitions: story.transitions.filter((t) => t.to.statusCategory.key !== 'indeterminate'),
};

function get(query: string): NextRequest {
  return new NextRequest(`http://localhost/api/pulls/jira-sync?${query}`);
}

function connect() {
  saveConnection(ME.id, 'jira', 'Jira', { cloud: 'acme', email: 'eu@acme', token: 'x' });
  setModuleEnabled(ME.id, 'jira', true);
}

function stubJira({ transitions = story as unknown } = {}) {
  const fetchMock = vi.fn(async (url: string) => {
    const body = url.includes('/transitions') ? transitions : BACKLOG;
    return { ok: true, status: 200, json: async () => body };
  });
  vi.stubGlobal('fetch', fetchMock);
  return fetchMock;
}

beforeEach(async () => {
  dir = mkdtempSync(path.join(tmpdir(), 'daily-web-pull-jira-sync-'));
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

describe('GET /api/pulls/jira-sync', () => {
  it('is the only method: the write goes through the Jira transitions route', async () => {
    const route = await import('@/app/api/pulls/jira-sync/route');
    expect('POST' in route).toBe(false);
  });

  it('401 without a session', async () => {
    currentUser.mockResolvedValue(null);
    expect((await GET(get('key=TT-5019&intent=review'))).status).toBe(401);
  });

  it('400 when Jira is not connected', async () => {
    expect((await GET(get('key=TT-5019&intent=review'))).status).toBe(400);
  });

  it.each(['key=not%20a%20key&intent=review', 'intent=review', 'key=TT-5019&intent=done', 'key=TT-5019'])(
    '400 with invalid input %s, without calling Jira',
    async (query) => {
      connect();
      const fetchMock = stubJira();
      expect((await GET(get(query))).status).toBe(400);
      expect(fetchMock).not.toHaveBeenCalled();
    },
  );

  it('picks the Code Review transition for review', async () => {
    connect();
    stubJira();
    const res = await GET(get('key=tt-5019&intent=review'));
    expect(res.status).toBe(200);
    expect((await res.json()).transition).toEqual({
      id: '7',
      name: 'Code Review PR',
      to: { name: 'Code Review PR', category: 'indeterminate' },
      requires: 'nothing',
    });
  });

  it('picks the Em Andamento transition for in-progress', async () => {
    connect();
    stubJira();
    const res = await GET(get('key=TT-5019&intent=in-progress'));
    expect((await res.json()).transition.id).toBe('31');
  });

  it('404 when no transition leads to review', async () => {
    connect();
    stubJira({ transitions: ONLY_NEW_AND_DONE });
    const res = await GET(get('key=TT-5019&intent=review'));
    expect(res.status).toBe(404);
    expect((await res.json()).error).toBe('nenhuma transição para revisão disponível — abrir no Jira');
  });

  it("502 with Jira's message when Jira refuses", async () => {
    connect();
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue({ ok: false, status: 500, text: async () => JSON.stringify({ errorMessages: ['Jira fora do ar'] }) }),
    );
    const res = await GET(get('key=TT-5019&intent=review'));
    expect(res.status).toBe(502);
    expect((await res.json()).error).toContain('Jira fora do ar');
  });
});
