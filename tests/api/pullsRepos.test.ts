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

import { POST } from '@/app/api/pulls/repos/route';
import { listConnections, saveConnection } from '@/lib/vault/connections';

let dir: string;
const ME = { id: 'u-1', username: 'joao' };
const THIRTY = Array.from({ length: 30 }, (_, i) => `acme/repo-${i + 1}`);

function add(repo: string) {
  return POST(new NextRequest('http://localhost/api/pulls/repos', { method: 'POST', body: JSON.stringify({ repo }) }));
}

function tracked(): string {
  return listConnections(ME.id, 'pulls')[0].values.repos ?? '';
}

beforeEach(async () => {
  dir = mkdtempSync(path.join(tmpdir(), 'daily-web-pulls-repos-'));
  process.env.DAILY_WEB_DB_PATH = path.join(dir, 'test.db');
  process.env.DAILY_WEB_SECRET_KEY = Buffer.alloc(32, 'a').toString('base64');
  currentUser.mockResolvedValue(ME);
  const { getDb } = await import('@/lib/db');
  getDb();
});

afterEach(() => rmSync(dir, { recursive: true, force: true }));

describe('POST /api/pulls/repos', () => {
  it('adds the 30th repo', async () => {
    saveConnection(ME.id, 'pulls', 'GitHub', { token: 't', repos: THIRTY.slice(0, 29).join(', ') });
    const res = await add('acme/repo-30');
    expect(res.status).toBe(200);
    expect((await res.json()).repos).toHaveLength(30);
  });

  it('refuses a 31st repo with a clear 400, without saving it', async () => {
    saveConnection(ME.id, 'pulls', 'GitHub', { token: 't', repos: THIRTY.join(', ') });
    const res = await add('acme/repo-31');
    expect(res.status).toBe(400);
    expect((await res.json()).error).toBe(
      'limite de 30 repositórios acompanhados — remova um antes de adicionar outro',
    );
    expect(tracked()).not.toContain('acme/repo-31');
  });

  it('accepts a repo already tracked at the limit, without duplicating it', async () => {
    saveConnection(ME.id, 'pulls', 'GitHub', { token: 't', repos: THIRTY.join(', ') });
    const res = await add('acme/repo-3');
    expect(res.status).toBe(200);
    expect((await res.json()).repos).toHaveLength(30);
  });
});
