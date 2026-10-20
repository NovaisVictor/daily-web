import { afterEach, describe, expect, it, vi } from 'vitest';
import changelogStory from '@/tests/fixtures/jira-write/changelog-status.json';
import changelogTwice from '@/tests/fixtures/jira-write/changelog-status-no-start-date.json';
import transitions from '@/tests/fixtures/jira-write/transitions-story.json';
import {
  firstInProgressDay,
  isCalendarDate,
  parseChangelogPage,
  parseCreatedDay,
  parseStatusCategories,
  suggestStartDates,
  writeStartDates,
} from '@/lib/integrations/jira/startDates';
import type { Connection } from '@/lib/vault/connections';

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

type Responder = (path: string, init: RequestInit) => unknown;

function stubJira(respond: Responder) {
  const fetchMock = vi.fn(async (url: string, init: RequestInit) =>
    respond(url.replace('https://acme.atlassian.net', ''), init),
  );
  vi.stubGlobal('fetch', fetchMock);
  return fetchMock;
}

const paths = (fetchMock: ReturnType<typeof stubJira>) => fetchMock.mock.calls.map(([url]) => String(url));

afterEach(() => vi.unstubAllGlobals());

describe('parseStatusCategories', () => {
  it('maps each target status id to its category from the captured transitions', () => {
    const categories = parseStatusCategories(transitions);
    expect(categories.get('11540')).toBe('indeterminate');
    expect(categories.get('10175')).toBe('new');
  });

  it('fails visibly on an unknown status category', () => {
    const bad = { transitions: [{ id: '1', to: { id: '9', statusCategory: { key: 'paused' } } }] };
    expect(() => parseStatusCategories(bad)).toThrow(/categoria de status desconhecida \(paused\)/);
  });

  it('fails visibly when the transitions list is missing', () => {
    expect(() => parseStatusCategories({})).toThrow(/resposta inesperada do Jira/);
  });
});

describe('parseChangelogPage', () => {
  it('reads the day of each status change as Jira wrote it, in its own offset', () => {
    const page = parseChangelogPage(changelogStory);
    expect(page.changes[0]).toEqual({ day: '2026-10-20', toStatusIds: ['11540'] });
    expect(page.next).toBeNull();
  });

  it('points to the next page while isLast is false', () => {
    const page = parseChangelogPage({ ...changelogStory, isLast: false, startAt: 100 });
    expect(page.next).toBe(102);
  });

  it('fails visibly on an unexpected shape', () => {
    expect(() => parseChangelogPage({ values: 'x' })).toThrow(/resposta inesperada do Jira no histórico/);
    expect(() => parseChangelogPage({ values: [], startAt: 0 })).toThrow(/isLast ausente/);
  });
});

describe('firstInProgressDay', () => {
  it('takes the first entry into an in-progress status when the issue entered it twice', () => {
    const { changes } = parseChangelogPage(changelogTwice);
    expect(firstInProgressDay(changes, parseStatusCategories(transitions))).toBe('2026-10-09');
  });

  it('ignores a target status the transitions do not know', () => {
    const changes = [{ day: '2026-01-01', toStatusIds: ['99999'] }];
    expect(firstInProgressDay(changes, parseStatusCategories(transitions))).toBeNull();
  });
});

describe('parseCreatedDay', () => {
  it('takes the date part of created', () => {
    expect(parseCreatedDay({ fields: { created: '2026-09-30T23:50:00.000-0300' } })).toBe('2026-09-30');
  });

  it('fails visibly without created', () => {
    expect(() => parseCreatedDay({ fields: {} })).toThrow(/resposta inesperada do Jira na issue/);
  });
});

describe('isCalendarDate', () => {
  it('accepts real dates and rejects impossible ones', () => {
    expect(isCalendarDate('2024-02-29')).toBe(true);
    expect(isCalendarDate('2026-02-29')).toBe(false);
    expect(isCalendarDate('2026-1-01')).toBe(false);
  });
});

describe('suggestStartDates', () => {
  it('suggests the first in-progress day from the changelog', async () => {
    const fetchMock = stubJira((path) =>
      path.includes('/changelog') ? ok(changelogTwice) : ok(transitions),
    );
    expect(await suggestStartDates(CONN, ['TT-4404'])).toEqual([
      { key: 'TT-4404', status: 'suggested', date: '2026-10-09', source: 'changelog' },
    ]);
    expect(paths(fetchMock)).toEqual(
      expect.arrayContaining([
        'https://acme.atlassian.net/rest/api/3/issue/TT-4404/changelog?startAt=0&maxResults=100',
        'https://acme.atlassian.net/rest/api/3/issue/TT-4404/transitions',
      ]),
    );
  });

  it('falls back to the created date when the issue never moved into progress', async () => {
    const empty = { ...changelogStory, values: [] };
    const fetchMock = stubJira((path) => {
      if (path.includes('/changelog')) return ok(empty);
      if (path.includes('/transitions')) return ok(transitions);
      return ok({ fields: { created: '2026-10-01T09:00:00.000-0300' } });
    });
    expect(await suggestStartDates(CONN, ['TT-1'])).toEqual([
      { key: 'TT-1', status: 'suggested', date: '2026-10-01', source: 'created' },
    ]);
    expect(paths(fetchMock)).toContain('https://acme.atlassian.net/rest/api/3/issue/TT-1?fields=created');
  });

  it('follows changelog pages until isLast, at most five', async () => {
    const fetchMock = stubJira((path) => {
      if (path.includes('/transitions')) return ok(transitions);
      if (path.includes('/changelog')) return ok({ ...changelogStory, values: [], startAt: 0, isLast: false });
      return ok({ fields: { created: '2026-10-01T09:00:00.000-0300' } });
    });
    await suggestStartDates(CONN, ['TT-1']);
    expect(paths(fetchMock).filter((p) => p.includes('/changelog'))).toHaveLength(5);
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
        return ok(url.includes('/changelog') ? changelogStory : transitions);
      }),
    );
    const keys = Array.from({ length: 10 }, (_, i) => `TT-${i + 1}`);
    const suggestions = await suggestStartDates(CONN, keys);
    expect(suggestions.every((s) => s.status === 'suggested')).toBe(true);
    expect(peak).toBe(4);
  });

  it('reports a failed issue with the reason and still suggests the others', async () => {
    stubJira((path) => {
      if (path.startsWith('/rest/api/3/issue/TT-2/')) return refused(404, {});
      return ok(path.includes('/changelog') ? changelogStory : transitions);
    });
    expect(await suggestStartDates(CONN, ['TT-1', 'TT-2'])).toEqual([
      { key: 'TT-1', status: 'suggested', date: '2026-10-20', source: 'changelog' },
      { key: 'TT-2', status: 'failed', error: 'issue não encontrada no Jira' },
    ]);
  });
});

const FIELDS = [{ id: 'customfield_10015', name: 'Data de início' }];

describe('writeStartDates', () => {
  it('sets the start field on each issue and carries on past a refusal', async () => {
    const fetchMock = stubJira((path) => {
      if (path === '/rest/api/3/field') return ok(FIELDS);
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
    const fetchMock = stubJira(() => ok([]));
    await expect(writeStartDates(CONN, [{ key: 'TT-1', date: '2026-10-01' }])).rejects.toThrow(/Start date/);
    expect(fetchMock.mock.calls.some(([, init]) => init.method === 'PUT')).toBe(false);
  });
});
