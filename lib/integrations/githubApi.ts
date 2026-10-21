import type { Connection } from '@/lib/vault/connections';
import type { MyPullsDigest, PullsDigest, PullRequestItem, ReviewRequestsDigest } from '@/lib/types';
import { isValidRepo } from '@/lib/api/validation';
import { githubCall, githubGraphql, graphqlErrorMessage, type GraphqlReply } from './github/client';
import {
  MY_PULLS_QUERY,
  parseReposData,
  parseSearchData,
  repoAlias,
  reposQuery,
  REVIEW_REQUESTS_QUERY,
  SEARCH_PULLS_QUERY,
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
  REVIEW_REQUESTS_QUERY,
  reviewFromDecision,
  SEARCH_LIMIT,
} from './github/pulls';
export type { ReviewRequestsDigest } from '@/lib/types';

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

/** Every tracked repo in one GraphQL query, not one call per repo. */
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

  const { query, variables } = reposQuery(repos);
  const { data, errors } = await githubGraphql(token, query, variables);
  const aliases = new Set(repos.map((_, index) => repoAlias(index)));
  const global = errors.find((error) => !aliases.has(error.path[0] ?? ''));
  if (global) throw new Error(graphqlErrorMessage(global));

  const parsed = parseReposData(data, repos, errors);
  return { ...parsed, items: rankPulls(parsed.items), errors: [...invalid, ...parsed.errors] };
}

// --- Buscas globais ------------------------------------------------------------
//
// As duas listas abaixo não têm nada a ver com os repositórios acompanhados:
// vêm da busca do GitHub, que varre tudo o que o token enxerga. Uma chamada
// por lista e por ciclo, nunca uma por repositório. `review-requested:@me` é
// o que ainda espera a sua revisão — o GitHub tira o pedido quando a revisão
// chega.

async function searchPulls(
  conn: Connection,
  q: string,
): Promise<{ reply: GraphqlReply; items: PullRequestItem[]; total: number }> {
  const reply = await githubGraphql(githubToken(conn), SEARCH_PULLS_QUERY, { q });
  if (reply.errors.length > 0) throw new Error(graphqlErrorMessage(reply.errors[0]));
  const { items, total } = parseSearchData(reply.data);
  return { reply, items, total };
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
  const { reply, items, total } = await searchPulls(conn, REVIEW_REQUESTS_QUERY);
  // A busca já filtrou por isto: toda linha aqui espera a sua revisão.
  const pedidos = items.map((item) => ({ ...item, awaitingYou: true, mine: false }));
  return {
    items: rankPulls(pedidos),
    truncated: total > pedidos.length,
    total,
    scopeNote: scopeNote(reply.headers.get('x-oauth-scopes'), pedidos.length === 0),
  };
}

export async function fetchMyPulls(conn: Connection): Promise<MyPullsDigest> {
  const { items, total } = await searchPulls(conn, MY_PULLS_QUERY);
  const meus = items.map((item) => ({ ...item, awaitingYou: false, mine: true }));
  return { items: rankPulls(meus), truncated: total > meus.length, total };
}

export async function testConnection(conn: Connection): Promise<void> {
  await githubCall(githubToken(conn), '/user');
}
