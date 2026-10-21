import { isValidRepo } from '@/lib/api/validation';
import { matchesQuery } from '@/lib/filters';
import type { FilterMode, JiraFilterGroup } from '@/lib/jiraFilters';
import type { PullRequestItem } from '@/lib/types';

export type PullState =
  | 'ci-failing'
  | 'changes-requested'
  | 'approved'
  | 'conflict'
  | 'draft'
  | 'awaiting-you'
  | 'stale';

export const PULL_STATES: readonly PullState[] = [
  'ci-failing',
  'changes-requested',
  'approved',
  'conflict',
  'draft',
  'awaiting-you',
  'stale',
];

export const PULL_STATE_LABEL: Record<PullState, string> = {
  'ci-failing': 'CI falhando',
  'changes-requested': 'Mudanças pedidas',
  approved: 'Aprovado',
  conflict: 'Conflito',
  draft: 'Rascunho',
  'awaiting-you': 'Aguardando você',
  stale: 'Parado há 3+ dias',
};

export const STALE_AFTER_MS = 3 * 24 * 60 * 60 * 1000;

export type PullFilterGroup = JiraFilterGroup<string>;

export interface PullFilterState {
  query: string;
  repo: PullFilterGroup;
  author: PullFilterGroup;
  state: PullState[];
}

export const EMPTY_PULL_FILTERS: PullFilterState = {
  query: '',
  repo: { values: [], mode: 'include' },
  author: { values: [], mode: 'include' },
  state: [],
};

const PARAMS = {
  query: 'pr_q',
  repo: 'pr_repo',
  repoMode: 'pr_repo_mode',
  author: 'pr_author',
  authorMode: 'pr_author_mode',
  state: 'pr_state',
} as const;

const MAX_TEXT = 200;
const LOGIN_PATTERN = /^[A-Za-z0-9](?:[A-Za-z0-9-]{0,38})(?:\[bot\])?$/;

function tokens(params: URLSearchParams, name: string): string[] {
  return params
    .getAll(name)
    .flatMap((value) => value.split(','))
    .map((token) => token.trim())
    .filter(Boolean);
}

function distinct<T extends string>(values: (T | null)[], key: (value: T) => string): T[] {
  const seen = new Set<string>();
  const out: T[] = [];
  for (const value of values) {
    if (value === null || seen.has(key(value))) continue;
    seen.add(key(value));
    out.push(value);
  }
  return out;
}

const caseless = (value: string) => value.toLowerCase();

function parseGroup(
  params: URLSearchParams,
  name: string,
  modeName: string,
  valid: (raw: string) => boolean,
): PullFilterGroup {
  const mode: FilterMode = params.get(modeName) === 'exclude' ? 'exclude' : 'include';
  const values = distinct(
    tokens(params, name).map((token) => (valid(token) ? token : null)),
    caseless,
  );
  return { values, mode };
}

function parseState(raw: string): PullState | null {
  return PULL_STATES.find((state) => state === raw) ?? null;
}

/** A URL é editável à mão: o que não é um valor que a tela produz é
 *  descartado em vez de virar erro. */
export function parsePullFilters(params: URLSearchParams): PullFilterState {
  const query = params.get(PARAMS.query) ?? '';
  return {
    query: query.length > MAX_TEXT ? '' : query,
    repo: parseGroup(params, PARAMS.repo, PARAMS.repoMode, isValidRepo),
    author: parseGroup(params, PARAMS.author, PARAMS.authorMode, (raw) => LOGIN_PATTERN.test(raw)),
    state: distinct(tokens(params, PARAMS.state).map(parseState), (state) => state),
  };
}

export function pullFiltersToParams(
  current: URLSearchParams,
  filters: PullFilterState,
): URLSearchParams {
  const params = new URLSearchParams(current);
  const put = (name: string, value: string) => {
    if (value) params.set(name, value);
    else params.delete(name);
  };
  const putGroup = (name: string, modeName: string, group: PullFilterGroup) => {
    put(name, group.values.join(','));
    put(modeName, group.values.length > 0 && group.mode === 'exclude' ? 'exclude' : '');
  };

  put(PARAMS.query, filters.query);
  putGroup(PARAMS.repo, PARAMS.repoMode, filters.repo);
  putGroup(PARAMS.author, PARAMS.authorMode, filters.author);
  put(PARAMS.state, filters.state.join(','));
  return params;
}

export function isStale(item: PullRequestItem, now: Date): boolean {
  const updated = Date.parse(item.updatedAt);
  return !Number.isNaN(updated) && now.getTime() - updated >= STALE_AFTER_MS;
}

export function hasPullState(item: PullRequestItem, state: PullState, now: Date): boolean {
  switch (state) {
    case 'ci-failing':
      return item.ci === 'failing';
    case 'changes-requested':
      return item.review === 'changes-requested';
    case 'approved':
      return item.review === 'approved';
    case 'conflict':
      return item.merge === 'conflict';
    case 'draft':
      return item.draft;
    case 'awaiting-you':
      return item.awaitingYou;
    case 'stale':
      return isStale(item, now);
  }
}

function matchesGroup(value: string, group: PullFilterGroup): boolean {
  if (group.values.length === 0) return true;
  const hit = group.values.some((selected) => caseless(selected) === caseless(value));
  return group.mode === 'include' ? hit : !hit;
}

/** Dentro de uma dimensão os valores se somam (OU); entre dimensões, todas
 *  precisam valer (E) — o mesmo recorte do painel do Jira. */
export function matchesPullFilters(
  item: PullRequestItem,
  filters: PullFilterState,
  now: Date = new Date(),
): boolean {
  if (!matchesGroup(item.repo, filters.repo)) return false;
  if (!matchesGroup(item.author, filters.author)) return false;
  if (filters.state.length > 0 && !filters.state.some((s) => hasPullState(item, s, now))) {
    return false;
  }
  const fields = [
    item.title,
    `${item.repo}#${item.number}`,
    item.author,
    ...(item.jira ?? []).map((ref) => ref.key),
  ];
  return matchesQuery(fields, filters.query);
}

export function hasPullFilters(filters: PullFilterState): boolean {
  return (
    filters.query.trim() !== '' ||
    filters.repo.values.length > 0 ||
    filters.author.values.length > 0 ||
    filters.state.length > 0
  );
}

export interface PullFilterOption {
  value: string;
  count: number;
}

export interface PullFilterOptions {
  repos: PullFilterOption[];
  authors: PullFilterOption[];
}

/** O mesmo PR aparece em mais de uma lista (acompanhado e com revisão
 *  pedida); a contagem é de PRs distintos. */
export function pullFilterOptions(items: PullRequestItem[]): PullFilterOptions {
  const seen = new Set<string>();
  const repos = new Map<string, number>();
  const authors = new Map<string, number>();
  for (const item of items) {
    const key = `${caseless(item.repo)}#${item.number}`;
    if (seen.has(key)) continue;
    seen.add(key);
    repos.set(item.repo, (repos.get(item.repo) ?? 0) + 1);
    if (item.author) authors.set(item.author, (authors.get(item.author) ?? 0) + 1);
  }
  const sorted = (counts: Map<string, number>) =>
    [...counts.entries()]
      .map(([value, count]) => ({ value, count }))
      .sort((a, b) => a.value.localeCompare(b.value));
  return { repos: sorted(repos), authors: sorted(authors) };
}
