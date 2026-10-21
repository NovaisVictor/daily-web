import type { Connection } from '@/lib/vault/connections';
import type { MyPullsDigest, PullsDigest, PullRequestItem, ReviewRequestsDigest } from '@/lib/types';
import { isValidRepo } from '@/lib/api/validation';
import { githubCall, githubGraphql, graphqlErrorMessage, type GraphqlReply } from './github/client';
import {
  MY_PULLS_QUERY,
  MY_PULLS_SEARCH,
  parseReposData,
  parseSearchData,
  partialNote,
  repoAlias,
  REPOS_PER_QUERY,
  reposQuery,
  REVIEW_REQUESTS_QUERY,
  REVIEW_REQUESTS_SEARCH,
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

async function fetchRepoBatch(token: string, repos: string[]): Promise<ParsedRepos> {
  const { query, variables } = reposQuery(repos);
  const { data, errors } = await githubGraphql(token, query, variables);
  const aliases = new Set(repos.map((_, index) => repoAlias(index)));
  const global = errors.find((error) => !aliases.has(error.path[0] ?? ''));
  if (global) throw new Error(graphqlErrorMessage(global));
  return parseReposData(data, repos, errors);
}

function batchesOf<T>(values: T[], size: number): T[][] {
  const batches: T[][] = [];
  for (let start = 0; start < values.length; start += size) batches.push(values.slice(start, start + size));
  return batches;
}

/** Tracked repos in GraphQL queries of up to REPOS_PER_QUERY repos each, run in
 *  parallel, never one call per repo. A failed query puts only its repos in
 *  `errors`; when every query fails, the panel fails with the first reason. */
export async function fetchPulls(conn: Connection): Promise<PullsDigest> {
  const token = githubToken(conn);
  const tracked = trackedRepos(conn);
  const empty: PullsDigest = { items: [], errors: [], defaultBranches: [], truncated: [] };
  if (tracked.length === 0) return empty;

  const repos = tracked.filter(isValidRepo);
  const invalid = tracked
    .filter((repo) => !isValidRepo(repo))
    .map((repo) => `${repo}: nome inválido — use o formato dono/nome`);
  if (repos.length === 0) return { ...empty, errors: invalid };

  const batches = batchesOf(repos, REPOS_PER_QUERY);
  const settled = await Promise.allSettled(batches.map((batch) => fetchRepoBatch(token, batch)));
  const failures = settled.flatMap((outcome) => (outcome.status === 'rejected' ? [outcome.reason] : []));
  if (failures.length === settled.length) throw failures[0];

  const merged: PullsDigest = { ...empty, errors: [...invalid] };
  settled.forEach((outcome, index) => {
    if (outcome.status === 'rejected') {
      const reason = outcome.reason instanceof Error ? outcome.reason.message : String(outcome.reason);
      merged.errors.push(...batches[index].map((repo) => `${repo}: ${reason}`));
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
