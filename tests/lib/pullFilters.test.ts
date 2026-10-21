import { describe, expect, it } from 'vitest';
import {
  EMPTY_PULL_FILTERS,
  matchesPullFilters,
  parsePullFilters,
  pullFilterOptions,
  pullFiltersToParams,
  type PullFilterState,
} from '@/lib/pullFilters';
import type { PullRequestItem } from '@/lib/types';

const NOW = new Date('2026-10-21T12:00:00Z');

function pull(over: Partial<PullRequestItem> = {}): PullRequestItem {
  return {
    id: 'PR_1',
    repo: 'joao/daily-web',
    number: 3,
    title: 'Arrumar o build',
    url: 'https://github.com/joao/daily-web/pull/3',
    author: 'joao',
    draft: false,
    awaitingYou: false,
    mine: false,
    isPullRequest: true,
    updatedAt: '2026-10-21T10:00:00Z',
    createdAt: '2026-10-20T10:00:00Z',
    ci: 'passing',
    failedChecks: [],
    review: 'pending',
    pendingReviewers: [],
    merge: 'clean',
    size: { additions: 1, deletions: 1, files: 1 },
    headRef: 'feature/x',
    baseRef: 'main',
    headSha: 'abc123',
    ...over,
  };
}

const parse = (query: string) => parsePullFilters(new URLSearchParams(query));
const filters = (over: Partial<PullFilterState>): PullFilterState => ({
  ...EMPTY_PULL_FILTERS,
  ...over,
});
const include = (...values: string[]) => ({ values, mode: 'include' as const });

describe('parsePullFilters', () => {
  it('returns no filter for an empty URL', () => {
    expect(parse('')).toEqual(EMPTY_PULL_FILTERS);
  });

  it('reads comma-separated repos', () => {
    expect(parse('pr_repo=joao/a,joao/b').repo.values).toEqual(['joao/a', 'joao/b']);
  });

  it('drops repos that are not owner/name', () => {
    expect(parse('pr_repo=joao/a,a/b/c,nope').repo.values).toEqual(['joao/a']);
  });

  it('dedupes repeated repos ignoring case', () => {
    expect(parse('pr_repo=joao/a,Joao/A&pr_repo=joao/a').repo.values).toEqual(['joao/a']);
  });

  it('drops authors that are not GitHub logins', () => {
    expect(parse('pr_author=maria,<script>,dependabot[bot]').author.values).toEqual([
      'maria',
      'dependabot[bot]',
    ]);
  });

  it('drops unknown states', () => {
    expect(parse('pr_state=draft,merged,stale').state).toEqual(['draft', 'stale']);
  });

  it('dedupes repeated states', () => {
    expect(parse('pr_state=draft,draft&pr_state=draft').state).toEqual(['draft']);
  });

  it('ignores a search longer than 200 characters', () => {
    expect(parse(`pr_q=${'a'.repeat(201)}`).query).toBe('');
  });

  it('reads the exclude mode only when it is exactly exclude', () => {
    expect(parse('pr_author=maria&pr_author_mode=EXCLUDE').author.mode).toBe('include');
  });
});

describe('pullFiltersToParams', () => {
  it('keeps params owned by other panels', () => {
    const params = pullFiltersToParams(
      new URLSearchParams('pulls=meus&jiraBusca=x'),
      filters({ state: ['draft'] }),
    );
    expect(params.toString()).toBe('pulls=meus&jiraBusca=x&pr_state=draft');
  });

  it('removes empty filters from the URL', () => {
    const params = pullFiltersToParams(
      new URLSearchParams('pr_q=x&pr_repo=joao/a&pr_repo_mode=exclude&pr_state=draft'),
      EMPTY_PULL_FILTERS,
    );
    expect(params.toString()).toBe('');
  });

  it('round-trips through parse', () => {
    const state = filters({
      query: 'build',
      repo: { values: ['joao/a'], mode: 'exclude' },
      author: include('maria', 'joao'),
      state: ['ci-failing', 'stale'],
    });
    expect(parsePullFilters(pullFiltersToParams(new URLSearchParams(), state))).toEqual(state);
  });
});

describe('matchesPullFilters', () => {
  it('matches everything without filters', () => {
    expect(matchesPullFilters(pull(), EMPTY_PULL_FILTERS, NOW)).toBe(true);
  });

  it('searches the title ignoring accents and case', () => {
    const item = pull({ title: 'Revisão do build' });
    expect(matchesPullFilters(item, filters({ query: 'REVISAO' }), NOW)).toBe(true);
  });

  it('searches repo#number', () => {
    expect(matchesPullFilters(pull(), filters({ query: 'daily-web#3' }), NOW)).toBe(true);
  });

  it('searches the author', () => {
    expect(matchesPullFilters(pull({ author: 'maria' }), filters({ query: 'mari' }), NOW)).toBe(true);
  });

  it('searches the linked Jira keys', () => {
    const item = pull({
      jira: [{ key: 'TT-42', url: 'https://jira/TT-42', status: 'Doing', statusCategory: 'indeterminate' }],
    });
    expect(matchesPullFilters(item, filters({ query: 'tt-42' }), NOW)).toBe(true);
  });

  it('rejects an item the search does not hit', () => {
    expect(matchesPullFilters(pull(), filters({ query: 'deploy' }), NOW)).toBe(false);
  });

  it('accepts any of the selected repos', () => {
    const f = filters({ repo: include('joao/other', 'joao/daily-web') });
    expect(matchesPullFilters(pull(), f, NOW)).toBe(true);
  });

  it('compares repos ignoring case', () => {
    expect(matchesPullFilters(pull(), filters({ repo: include('Joao/Daily-Web') }), NOW)).toBe(true);
  });

  it('rejects a repo outside the selection', () => {
    expect(matchesPullFilters(pull(), filters({ repo: include('joao/other') }), NOW)).toBe(false);
  });

  it('rejects a selected repo in exclude mode', () => {
    const f = filters({ repo: { values: ['joao/daily-web'], mode: 'exclude' } });
    expect(matchesPullFilters(pull(), f, NOW)).toBe(false);
  });

  it('rejects an author outside the selection', () => {
    expect(matchesPullFilters(pull(), filters({ author: include('maria') }), NOW)).toBe(false);
  });

  it('accepts any of the selected states', () => {
    const f = filters({ state: ['draft', 'ci-failing'] });
    expect(matchesPullFilters(pull({ ci: 'failing' }), f, NOW)).toBe(true);
  });

  it('requires every dimension to match', () => {
    const f = filters({ repo: include('joao/daily-web'), state: ['draft'] });
    expect(matchesPullFilters(pull({ draft: false }), f, NOW)).toBe(false);
  });

  it.each([
    ['ci-failing', { ci: 'failing' }],
    ['changes-requested', { review: 'changes-requested' }],
    ['approved', { review: 'approved' }],
    ['conflict', { merge: 'conflict' }],
    ['draft', { draft: true }],
    ['awaiting-you', { awaitingYou: true }],
    ['stale', { updatedAt: '2026-10-18T12:00:00Z' }],
  ] as const)('matches state %s', (state, over) => {
    expect(matchesPullFilters(pull(over), filters({ state: [state] }), NOW)).toBe(true);
  });

  it.each([
    ['ci-failing', { ci: 'running' }],
    ['changes-requested', { review: 'pending' }],
    ['approved', { review: 'unknown' }],
    ['conflict', { merge: 'unknown' }],
    ['draft', { draft: false }],
    ['awaiting-you', { awaitingYou: false }],
    ['stale', { updatedAt: '2026-10-18T12:00:01Z' }],
  ] as const)('does not match state %s', (state, over) => {
    expect(matchesPullFilters(pull(over), filters({ state: [state] }), NOW)).toBe(false);
  });

  it('does not treat an unparseable update date as stale', () => {
    const item = pull({ updatedAt: '' });
    expect(matchesPullFilters(item, filters({ state: ['stale'] }), NOW)).toBe(false);
  });
});

describe('pullFilterOptions', () => {
  it('sorts repos and counts each pull request once across lists', () => {
    const a = pull({ repo: 'joao/zeta', number: 1 });
    const b = pull({ repo: 'joao/alpha', number: 2 });
    expect(pullFilterOptions([a, b, a]).repos).toEqual([
      { value: 'joao/alpha', count: 1 },
      { value: 'joao/zeta', count: 1 },
    ]);
  });

  it('leaves deleted authors out of the author options', () => {
    const items = [pull({ number: 1, author: '' }), pull({ number: 2, author: 'maria' })];
    expect(pullFilterOptions(items).authors).toEqual([{ value: 'maria', count: 1 }]);
  });
});
