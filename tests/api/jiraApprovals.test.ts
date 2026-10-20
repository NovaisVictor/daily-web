import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { NextRequest } from 'next/server';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import single from '@/tests/fixtures/jira-write/approval-single.json';
import captured from '@/tests/fixtures/jira-write/approvals-pending.json';

const currentUser = vi.fn();
vi.mock('@/lib/api/context', async (importOriginal) => ({
  ...(await importOriginal<typeof import('@/lib/api/context')>()),
  requireUser: async () => {
    const user = await currentUser();
    if (!user) return { ok: false, response: new Response('não autenticado', { status: 401 }) };
    return { ok: true, value: user };
  },
}));

import { GET, POST } from '@/app/api/jira/issues/[key]/approvals/route';
import { saveConnection, setModuleEnabled } from '@/lib/vault/connections';

let dir: string;
const ME = { id: 'u-1', username: 'joao' };
const BASE = 'https://acme.atlassian.net';

/** No pending approval existed at capture time: the captured approval with only
 *  `canAnswerApproval` and `finalDecision` flipped. */
const pendingFromCaptured = { ...single, canAnswerApproval: true, finalDecision: 'pending' };
const pendingPage = { ...captured.decidedRequest.response, values: [pendingFromCaptured] };
const decidedPage = captured.decidedRequest.response;

function req(method: string, body?: unknown): NextRequest {
  return new NextRequest('http://localhost/api/jira/issues/PDS-2763/approvals', {
    method,
    ...(body === undefined ? {} : { body: typeof body === 'string' ? body : JSON.stringify(body) }),
  });
}

const ctx = (key: string) => ({ params: Promise.resolve({ key }) });

function ok(body: unknown) {
  return { ok: true, status: 200, headers: new Headers(), json: async () => body };
}

function stubFetch(...responses: unknown[]) {
  const fetchMock = vi.fn();
  for (const r of responses) fetchMock.mockResolvedValueOnce(r);
  vi.stubGlobal('fetch', fetchMock);
  return fetchMock;
}

beforeEach(async () => {
  dir = mkdtempSync(path.join(tmpdir(), 'daily-web-approvals-'));
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

describe('GET /api/jira/issues/[key]/approvals', () => {
  it('401 without a session', async () => {
    currentUser.mockResolvedValue(null);
    expect((await GET(req('GET'), ctx('PDS-2763'))).status).toBe(401);
  });

  it('400 with an invalid key, without calling Jira', async () => {
    const fetchMock = stubFetch();
    expect((await GET(req('GET'), ctx('not a key'))).status).toBe(400);
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it('returns only the approvals the user can still answer', async () => {
    const fetchMock = stubFetch(ok({ ...pendingPage, values: [single, pendingFromCaptured] }));
    const res = await GET(req('GET'), ctx('pds-2763'));
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ approvals: [{ id: '3516', name: 'Aprovação' }] });
    expect(fetchMock.mock.calls[0][0]).toBe(`${BASE}/rest/servicedeskapi/request/PDS-2763/approval?start=0&limit=50`);
  });

  it('502 when Jira answers an unexpected shape', async () => {
    stubFetch(ok({ ...pendingPage, values: [{ ...pendingFromCaptured, finalDecision: 'maybe' }] }));
    const res = await GET(req('GET'), ctx('PDS-2763'));
    expect(res.status).toBe(502);
    expect((await res.json()).error).toMatch(/decisão desconhecida/);
  });
});

describe('POST /api/jira/issues/[key]/approvals', () => {
  it('401 without a session', async () => {
    currentUser.mockResolvedValue(null);
    expect((await POST(req('POST', { approvalId: '3516', decision: 'approve' }), ctx('PDS-2763'))).status).toBe(401);
  });

  it('400 with an invalid key', async () => {
    expect((await POST(req('POST', { approvalId: '3516', decision: 'approve' }), ctx('../x'))).status).toBe(400);
  });

  it.each([
    ['a non-numeric approval id', { approvalId: '35a6', decision: 'approve' }],
    ['a numeric (not string) approval id', { approvalId: 3516, decision: 'approve' }],
    ['an unknown decision', { approvalId: '3516', decision: 'approved' }],
    ['a missing decision', { approvalId: '3516' }],
    ['a body that is not JSON', 'nope'],
  ])('400 with %s, without calling Jira', async (_label, body) => {
    const fetchMock = stubFetch();
    expect((await POST(req('POST', body), ctx('PDS-2763'))).status).toBe(400);
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it('409 when the approval is no longer answerable, without deciding', async () => {
    const fetchMock = stubFetch(ok(decidedPage));
    const res = await POST(req('POST', { approvalId: '3516', decision: 'approve' }), ctx('PDS-2763'));
    expect(res.status).toBe(409);
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it('502 with Jira’s own message when Jira refuses the decision', async () => {
    stubFetch(ok(pendingPage), {
      ok: false,
      status: 400,
      headers: new Headers(),
      text: async () => JSON.stringify({ errorMessages: ['Você não pode responder esta aprovação'] }),
    });
    const res = await POST(req('POST', { approvalId: '3516', decision: 'decline' }), ctx('PDS-2763'));
    expect(res.status).toBe(502);
    expect((await res.json()).error).toContain('Você não pode responder esta aprovação');
  });

  it('re-reads the list, then posts the decision to the approval', async () => {
    const fetchMock = stubFetch(ok(pendingPage), ok({ ...pendingFromCaptured, finalDecision: 'declined' }));
    const res = await POST(req('POST', { approvalId: '3516', decision: 'decline' }), ctx('PDS-2763'));
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ ok: true });
    expect(fetchMock.mock.calls[0][0]).toBe(`${BASE}/rest/servicedeskapi/request/PDS-2763/approval?start=0&limit=50`);
    const [url, init] = fetchMock.mock.calls[1];
    expect(url).toBe(`${BASE}/rest/servicedeskapi/request/PDS-2763/approval/3516`);
    expect(init.method).toBe('POST');
    expect(JSON.parse(init.body)).toEqual({ decision: 'decline' });
  });
});
