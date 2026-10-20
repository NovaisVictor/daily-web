import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { NextRequest } from 'next/server';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';

const currentUser = vi.fn();
vi.mock('@/lib/api/context', async (importOriginal) => ({
  ...(await importOriginal<typeof import('@/lib/api/context')>()),
  requireUser: async () => {
    const user = await currentUser();
    if (!user) return { ok: false, response: new Response('não autenticado', { status: 401 }) };
    return { ok: true, value: user };
  },
}));

import { POST } from '@/app/api/jira/issues/[key]/comments/route';
import { saveConnection, setModuleEnabled } from '@/lib/vault/connections';

let dir: string;
const ME = { id: 'u-1', username: 'joao' };

function post(key: string, body: unknown) {
  const request = new NextRequest(`http://localhost/api/jira/issues/${key}/comments`, {
    method: 'POST',
    body: JSON.stringify(body),
  });
  return POST(request, { params: Promise.resolve({ key }) });
}

beforeEach(async () => {
  dir = mkdtempSync(path.join(tmpdir(), 'daily-web-comments-'));
  process.env.DAILY_WEB_DB_PATH = path.join(dir, 'test.db');
  process.env.DAILY_WEB_SECRET_KEY = Buffer.alloc(32, 'a').toString('base64');
  vi.clearAllMocks();
  currentUser.mockResolvedValue(ME);
  const { getDb } = await import('@/lib/db');
  getDb();
  saveConnection(ME.id, 'jira', 'Jira', { cloud: 'example', email: 'pessoa-1@example.com', token: 'x' });
  setModuleEnabled(ME.id, 'jira', true);
});

afterEach(() => {
  vi.unstubAllGlobals();
  rmSync(dir, { recursive: true, force: true });
});

describe('POST /api/jira/issues/[key]/comments', () => {
  it('401 without a session', async () => {
    currentUser.mockResolvedValue(null);
    expect((await post('TT-123', { body: 'oi' })).status).toBe(401);
  });

  it('400 on an invalid issue key', async () => {
    const fetchMock = vi.fn();
    vi.stubGlobal('fetch', fetchMock);
    expect((await post('TT 123', { body: 'oi' })).status).toBe(400);
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it.each([
    ['missing body', {}],
    ['blank body', { body: '   ' }],
    ['non-string body', { body: 42 }],
    ['too long body', { body: 'a'.repeat(5001) }],
    ['array payload', ['oi']],
  ])('400 on %s', async (_name, payload) => {
    const fetchMock = vi.fn();
    vi.stubGlobal('fetch', fetchMock);
    const res = await post('TT-123', payload);
    expect(res.status).toBe(400);
    expect((await res.json()).error).toMatch(/comentário vazio/);
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("502 with Jira's own message when Jira refuses", async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue({
        ok: false,
        status: 400,
        text: async () => JSON.stringify({ errorMessages: [], errors: { comment: 'Comment body can not be empty!' } }),
      }),
    );
    const res = await post('TT-123', { body: 'oi' });
    expect(res.status).toBe(502);
    expect((await res.json()).error).toContain('comment: Comment body can not be empty!');
  });

  it('502 when Jira answers without the comment id', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue({ ok: true, status: 201, json: async () => ({}) }));
    const res = await post('TT-123', { body: 'oi' });
    expect(res.status).toBe(502);
    expect((await res.json()).error).toMatch(/id do comentário ausente/);
  });

  it('posts the trimmed text as ADF and returns the comment id', async () => {
    const fetchMock = vi.fn().mockResolvedValue({ ok: true, status: 201, json: async () => ({ id: '10000' }) });
    vi.stubGlobal('fetch', fetchMock);

    const res = await post('tt-123', { body: '  oi\n\n*tudo bem?*  ' });

    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ ok: true, comment: { id: '10000' } });
    const [url, init] = fetchMock.mock.calls[0];
    expect(url).toBe('https://example.atlassian.net/rest/api/3/issue/TT-123/comment');
    expect(init.method).toBe('POST');
    expect(JSON.parse(init.body)).toEqual({
      body: {
        type: 'doc',
        version: 1,
        content: [
          { type: 'paragraph', content: [{ type: 'text', text: 'oi' }] },
          { type: 'paragraph', content: [{ type: 'text', text: '*tudo bem?*' }] },
        ],
      },
    });
  });
});
