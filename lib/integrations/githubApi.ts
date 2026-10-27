import type { Connection } from '@/lib/vault/connections';
import type { MyPullsDigest, PullsDigest, PullRequestItem, ReviewRequestsDigest } from '@/lib/types';
import { isValidRepo } from '@/lib/api/validation';
import { isGithubLogin } from '@/lib/githubLogin';
import { githubCall, githubGraphql, graphqlErrorMessage, type GraphqlReply } from './github/client';
import {
  authorAlias,
  AUTHORS_PER_QUERY,
  authorsQuery,
  MY_PULLS_QUERY,
  parseAuthorsData,
  MY_PULLS_SEARCH,
  parseReposData,
  parseSearchData,
  partialNote,
  repoAlias,
  REPOS_PER_QUERY,
  reposQuery,
  REVIEW_REQUESTS_QUERY,
  REVIEW_REQUESTS_SEARCH,
  type AuthorGroup,
  type ParsedRepos,
} from './github/pulls';

export { githubCall, githubErrorDetail, githubGraphql, githubRequest } from './github/client';
export type { GithubMethod, GithubReply, GithubRequestOptions, GraphqlError, GraphqlReply } from './github/client';
export {
  ciFromState,
  failedChecksOf,
  mergeFromState,
  MY_PULLS_QUERY,
  parseIssueNode,
  parsePullNode,
  parseReposData,
  parseSearchData,
  pendingReviewersOf,
  PER_REPO_LIMIT,
  REPOS_PER_QUERY,
  REVIEW_REQUESTS_QUERY,
  reviewersOf,
  reviewerStateOf,
  reviewFromDecision,
  SEARCH_LIMIT,
} from './github/pulls';
export type { ReviewRequestsDigest } from '@/lib/types';

/** Past this the panel stops being a glance; also bounds the GraphQL batches. */
export const TRACKED_REPOS_MAX = 30;

export function parseRepoList(raw: string): string[] {
  return raw
    .split(',')
    .map((item) => item.trim())
    .filter((item) => item.length > 0);
}

export function serializeRepoList(repos: string[]): string {
  return repos.join(', ');
}

/** Each distinct author is one GitHub search per refresh cycle. */
export const TRACKED_AUTHORS_MAX = 20;
export const AUTHORS_PER_REPO_MAX = 10;

/** Followed authors by tracked repo. A repo absent from the map shows every author. */
export type RepoAuthors = Record<string, string[]>;

const caseless = (value: string) => value.toLowerCase();

/** Stored as JSON beside `repos`, not inside it: a server still on the
 *  previous version reads `repos` unchanged and just shows every author. Only
 *  the panel writes this, so a value it could not have written is an error,
 *  not an empty list that would silently widen the panel back to everyone. */
export function parseRepoAuthors(raw: string): RepoAuthors {
  if (raw.trim() === '') return {};
  let value: unknown;
  try {
    value = JSON.parse(raw);
  } catch {
    throw new Error('lista de autores acompanhados ilegível — remova e adicione os autores de novo');
  }
  const valid =
    typeof value === 'object' &&
    value !== null &&
    !Array.isArray(value) &&
    Object.entries(value).every(
      ([repo, authors]) => isValidRepo(repo) && Array.isArray(authors) && authors.every(isGithubLogin),
    );
  if (!valid) throw new Error('lista de autores acompanhados ilegível — remova e adicione os autores de novo');
  return value as RepoAuthors;
}

/** Never `''`: saving a hidden field empty means "keep what is there", so
 *  clearing the last list must still write something. */
export function serializeRepoAuthors(authors: RepoAuthors): string {
  return JSON.stringify(Object.fromEntries(Object.entries(authors).filter(([, logins]) => logins.length > 0)));
}

export function trackedAuthors(conn: Connection): RepoAuthors {
  return parseRepoAuthors(conn.values.repoAuthors ?? '');
}

/** Logins are case-insensitive on GitHub; the first spelling seen wins. */
export function distinctAuthors(logins: string[]): string[] {
  const seen = new Set<string>();
  return logins.filter((login) => {
    if (seen.has(caseless(login))) return false;
    seen.add(caseless(login));
    return true;
  });
}

/** Inverts repo → authors into author → repos, one search per author. */
export function authorGroups(repos: string[], authors: RepoAuthors): AuthorGroup[] {
  const groups = new Map<string, AuthorGroup>();
  for (const repo of repos) {
    for (const author of distinctAuthors(authors[repo] ?? [])) {
      const group = groups.get(caseless(author)) ?? { author, repos: [] };
      group.repos.push(repo);
      groups.set(caseless(author), group);
    }
  }
  return [...groups.values()];
}

export function githubToken(conn: Connection): string {
  const token = (conn.values.token ?? '').trim();
  if (!token) throw new Error('personal access token do GitHub não configurado');
  return token;
}

/** O endereço do repositório no GitHub, ou `null` quando o nome guardado não
 *  tem a forma `dono/nome`. O nome é digitado pelo usuário e aqui vira href:
 *  o que não casa com o formato não vira link, em vez de virar um link torto. */
export function repoUrl(repo: string): string | null {
  if (!isValidRepo(repo)) return null;
  return `https://github.com/${repo}`;
}

export interface RepoGroup {
  repo: string;
  issues: PullRequestItem[];
  pulls: PullRequestItem[];
}

/** Agrupa por repositório e separa issue de pull request. Uma lista corrida
 *  misturava as duas coisas e não dizia de onde cada uma vinha. */
export function groupByRepo(items: PullRequestItem[]): RepoGroup[] {
  const porRepo = new Map<string, RepoGroup>();
  for (const item of items) {
    const grupo = porRepo.get(item.repo) ?? { repo: item.repo, issues: [], pulls: [] };
    (item.isPullRequest ? grupo.pulls : grupo.issues).push(item);
    porRepo.set(item.repo, grupo);
  }
  return [...porRepo.values()]
    .map((g) => ({ ...g, issues: rankPulls(g.issues), pulls: rankPulls(g.pulls) }))
    .sort((a, b) => a.repo.localeCompare(b.repo));
}

/** Primeiro o que pediram para você revisar, depois o que é seu, e o resto
 *  por atualização mais recente. */
export function rankPulls(items: PullRequestItem[]): PullRequestItem[] {
  return [...items].sort(
    (a, b) =>
      Number(b.awaitingYou) - Number(a.awaitingYou) ||
      Number(b.mine) - Number(a.mine) ||
      b.updatedAt.localeCompare(a.updatedAt),
  );
}

export function trackedRepos(conn: Connection): string[] {
  return parseRepoList(conn.values.repos ?? '');
}

async function fetchRepoBatch(token: string, repos: string[], withoutPulls: ReadonlySet<string>): Promise<ParsedRepos> {
  const { query, variables } = reposQuery(repos, withoutPulls);
  const { data, errors } = await githubGraphql(token, query, variables);
  const aliases = new Set(repos.map((_, index) => repoAlias(index)));
  const global = errors.find((error) => !aliases.has(error.path[0] ?? ''));
  if (global) throw new Error(graphqlErrorMessage(global));
  return parseReposData(data, repos, errors, withoutPulls);
}

async function fetchAuthorBatch(token: string, groups: AuthorGroup[]): Promise<ParsedRepos> {
  const { query, variables } = authorsQuery(groups);
  const { data, errors } = await githubGraphql(token, query, variables);
  const aliases = new Set(groups.map((_, index) => authorAlias(index)));
  const global = errors.find((error) => !aliases.has(error.path[0] ?? ''));
  if (global) throw new Error(graphqlErrorMessage(global));
  return parseAuthorsData(data, groups, errors);
}

function batchesOf<T>(values: T[], size: number): T[][] {
  const batches: T[][] = [];
  for (let start = 0; start < values.length; start += size) batches.push(values.slice(start, start + size));
  return batches;
}

/** Tracked repos in GraphQL queries of up to REPOS_PER_QUERY repos each, run in
 *  parallel, never one call per repo. A failed query puts only its repos in
 *  `errors`; when every query fails, the panel fails with the first reason.
 *
 *  A repo with followed authors takes its PRs from a search per author instead
 *  of its own pull list: that list holds only the PER_REPO_LIMIT most recently
 *  updated, so filtering it would silently lose an author's older PRs in a busy
 *  repo. Its issues still come from the repo query, unfiltered. */
export async function fetchPulls(conn: Connection): Promise<PullsDigest> {
  const token = githubToken(conn);
  const tracked = trackedRepos(conn);
  const authors = trackedAuthors(conn);
  const empty: PullsDigest = { items: [], errors: [], defaultBranches: [], truncated: [] };
  if (tracked.length === 0) return empty;

  const repos = tracked.filter(isValidRepo);
  const invalid = tracked
    .filter((repo) => !isValidRepo(repo))
    .map((repo) => `${repo}: nome inválido — use o formato dono/nome`);
  if (repos.length === 0) return { ...empty, errors: invalid };

  const groups = authorGroups(repos, authors);
  const byAuthor = new Set(groups.flatMap((group) => group.repos));
  const repoBatches = batchesOf(repos, REPOS_PER_QUERY);
  const authorBatches = batchesOf(groups, AUTHORS_PER_QUERY);
  const settled = await Promise.allSettled([
    ...repoBatches.map((batch) => fetchRepoBatch(token, batch, byAuthor)),
    ...authorBatches.map((batch) => fetchAuthorBatch(token, batch)),
  ]);
  const failures = settled.flatMap((outcome) => (outcome.status === 'rejected' ? [outcome.reason] : []));
  if (failures.length === settled.length) throw failures[0];

  const subjects = [
    ...repoBatches,
    ...authorBatches.map((batch) => batch.map((group) => `autor ${group.author}`)),
  ];
  const merged: PullsDigest = { ...empty, errors: [...invalid] };
  settled.forEach((outcome, index) => {
    if (outcome.status === 'rejected') {
      const reason = outcome.reason instanceof Error ? outcome.reason.message : String(outcome.reason);
      merged.errors.push(...subjects[index].map((subject) => `${subject}: ${reason}`));
      return;
    }
    merged.items.push(...outcome.value.items);
    merged.errors.push(...outcome.value.errors);
    merged.defaultBranches.push(...outcome.value.defaultBranches);
    merged.truncated.push(...outcome.value.truncated);
  });
  return { ...merged, items: rankPulls(merged.items) };
}

// --- Buscas globais ------------------------------------------------------------
//
// As duas listas abaixo não têm nada a ver com os repositórios acompanhados:
// vêm da busca do GitHub, que varre tudo o que o token enxerga. Uma chamada
// por lista e por ciclo, nunca uma por repositório. `review-requested:@me` é
// o que ainda espera a sua revisão — o GitHub tira o pedido quando a revisão
// chega.

interface SearchResult {
  reply: GraphqlReply;
  items: PullRequestItem[];
  total: number;
  errors: string[];
}

/** An error on `search` itself fails the list; one inside it (a node or field
 *  GitHub refused) keeps the rest and becomes a single note. */
async function searchPulls(conn: Connection, query: string, q: string): Promise<SearchResult> {
  const reply = await githubGraphql(githubToken(conn), query, { q });
  const fatal = reply.errors.find((error) => error.path[0] !== 'search' || error.path.length === 1);
  if (fatal) throw new Error(graphqlErrorMessage(fatal));
  const { items, total } = parseSearchData(reply.data);
  const note = partialNote('busca do GitHub', reply.errors);
  return { reply, items, total, errors: note ? [note] : [] };
}

/**
 * Por que a lista pode estar vazia sem estar certa. O cabeçalho
 * `x-oauth-scopes` só existe em token clássico: nele dá para ver se falta o
 * escopo `repo`, sem o qual nada de repositório privado aparece. O token
 * fine-grained não declara escopo nenhum aqui — dele só dá para dizer que o
 * alcance é o que foi concedido na criação. Sem lista vazia não há aviso:
 * quem está vendo PRs não precisa ouvir sobre escopo.
 */
export function scopeNote(scopesHeader: string | null, empty: boolean): string | null {
  if (!empty) return null;
  if (scopesHeader === null) {
    return 'Nenhuma revisão pedida a você. Se esperava ver algo, confira: um token fine-grained só enxerga os repositórios concedidos a ele, com permissão de leitura em Pull requests.';
  }
  const scopes = scopesHeader
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean);
  if (!scopes.includes('repo')) {
    return 'Nenhuma revisão pedida a você — e este token clássico não tem o escopo `repo`, então pedidos em repositórios privados não aparecem aqui. Gere um token com `repo` para vê-los.';
  }
  return null;
}

export async function fetchReviewRequests(conn: Connection): Promise<ReviewRequestsDigest> {
  const { reply, items, total, errors } = await searchPulls(conn, REVIEW_REQUESTS_SEARCH, REVIEW_REQUESTS_QUERY);
  // A busca já filtrou por isto: toda linha aqui espera a sua revisão.
  const pedidos = items.map((item) => ({ ...item, awaitingYou: true, mine: false }));
  return {
    items: rankPulls(pedidos),
    truncated: total > pedidos.length,
    total,
    scopeNote: scopeNote(reply.headers.get('x-oauth-scopes'), pedidos.length === 0),
    ...(errors.length > 0 ? { errors } : {}),
  };
}

export async function fetchMyPulls(conn: Connection): Promise<MyPullsDigest> {
  const { items, total, errors } = await searchPulls(conn, MY_PULLS_SEARCH, MY_PULLS_QUERY);
  const meus = items.map((item) => ({ ...item, awaitingYou: false, mine: true }));
  return { items: rankPulls(meus), truncated: total > meus.length, total, ...(errors.length > 0 ? { errors } : {}) };
}

export async function testConnection(conn: Connection): Promise<void> {
  await githubCall(githubToken(conn), '/user');
}
