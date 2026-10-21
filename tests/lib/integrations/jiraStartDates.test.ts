import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import statuses from '@/tests/fixtures/jira-statuses.json';
import changelog from '@/tests/fixtures/jira-changelog.json';
import { setInstanceMetaForTests } from '@/lib/integrations/jiraApi';
import { suggestStartDates, writeStartDates } from '@/lib/integrations/jira/startDates';
import type { Connection } from '@/lib/vault/connections';

const BASE = 'https://acme.atlassian.net';
const CONN = {
  id: 'c1',
  module: 'jira',
  label: 'Jira',
  values: { cloud: 'acme', email: 'eu@acme.com', token: 'segredo' },
} as unknown as Connection;

const ok = (body: unknown) => ({ ok: true, status: 200, json: async () => body });
const refused = (status: number, body: unknown) => ({
  ok: false,
  status,
  json: async () => body,
  text: async () => JSON.stringify(body),
});

const ISSUE_IN_PROGRESS = {
  fields: { created: '2026-10-01T10:00:00.000-0300', status: { statusCategory: { key: 'indeterminate' } } },
};

type Responder = (path: string, init: RequestInit) => unknown;

function stubJira(respond: Responder) {
  const fetchMock = vi.fn(async (url: string, init: RequestInit) => respond(url.replace(BASE, ''), init));
  vi.stubGlobal('fetch', fetchMock);
  return fetchMock;
}

const history = (path: string) => {
  if (path === '/rest/api/3/status') return ok(statuses);
  if (path.includes('/changelog')) return ok(changelog);
  return ok(ISSUE_IN_PROGRESS);
};

const knownMeta = (startField: string | null) =>
  setInstanceMetaForTests(BASE, { startField, flaggedField: null, priorityRank: new Map() });

beforeEach(() => knownMeta('customfield_10015'));

afterEach(() => {
  vi.unstubAllGlobals();
  setInstanceMetaForTests(BASE, null);
});

describe('suggestStartDates', () => {
  it('suggests the day the issue first entered progress, with its basis', async () => {
    stubJira(history);
    expect(await suggestStartDates(CONN, ['TT-5016'])).toEqual([
      { key: 'TT-5016', status: 'suggested', date: '2026-10-20', basis: 'started' },
    ]);
  });

  it('reports an issue whose history gives no date as unavailable', async () => {
    stubJira((path) => {
      if (path === '/rest/api/3/status') return ok(statuses);
      if (path.includes('/changelog')) return ok({ isLast: true, values: [] });
      return ok({ fields: { created: '2026-10-01T10:00:00.000-0300', status: { statusCategory: { key: 'new' } } } });
    });
    expect(await suggestStartDates(CONN, ['TT-1'])).toEqual([
      { key: 'TT-1', status: 'failed', error: 'o histórico não diz quando começou' },
    ]);
  });

  it('keeps no more than four requests in flight', async () => {
    let inFlight = 0;
    let peak = 0;
    vi.stubGlobal(
      'fetch',
      vi.fn(async (url: string) => {
        inFlight += 1;
        peak = Math.max(peak, inFlight);
        await new Promise((resolve) => setTimeout(resolve, 5));
        inFlight -= 1;
        return history(url.replace(BASE, ''));
      }),
    );
    const keys = Array.from({ length: 10 }, (_, i) => `TT-${i + 1}`);
    const suggestions = await suggestStartDates(CONN, keys);
    expect(suggestions.every((s) => s.status === 'suggested')).toBe(true);
    expect(peak).toBeLessThanOrEqual(4);
  });

  it('reports a failed issue with the reason and still suggests the others', async () => {
    stubJira((path) => {
      if (path.startsWith('/rest/api/3/issue/TT-2')) return refused(400, { errorMessages: ['sem permissão'] });
      return history(path);
    });
    expect(await suggestStartDates(CONN, ['TT-1', 'TT-2'])).toEqual([
      { key: 'TT-1', status: 'suggested', date: '2026-10-20', basis: 'started' },
      { key: 'TT-2', status: 'failed', error: 'Jira respondeu 400: sem permissão' },
    ]);
  });
});

describe('writeStartDates', () => {
  it('sets the start field on each issue and carries on past a refusal', async () => {
    const fetchMock = stubJira((path) => {
      if (path === '/rest/api/3/issue/TT-1') {
        return refused(400, { errorMessages: [], errors: { customfield_10015: 'campo não editável' } });
      }
      return { ok: true, status: 204, headers: new Headers() };
    });
    expect(
      await writeStartDates(CONN, [
        { key: 'TT-1', date: '2026-10-01' },
        { key: 'TT-2', date: '2026-10-02' },
      ]),
    ).toEqual([
      { key: 'TT-1', outcome: 'refused', error: 'Jira respondeu 400: customfield_10015: campo não editável' },
      { key: 'TT-2', outcome: 'written' },
    ]);
    const put = fetchMock.mock.calls.find(([url]) => String(url).endsWith('/issue/TT-2'));
    expect(put?.[1]).toMatchObject({ method: 'PUT', body: JSON.stringify({ fields: { customfield_10015: '2026-10-02' } }) });
  });

  it('throws before writing anything when the start field does not exist', async () => {
    knownMeta(null);
    const fetchMock = stubJira(() => ok([]));
    await expect(writeStartDates(CONN, [{ key: 'TT-1', date: '2026-10-01' }])).rejects.toThrow(/Start date/);
    expect(fetchMock.mock.calls.some(([, init]) => init.method === 'PUT')).toBe(false);
  });
});
