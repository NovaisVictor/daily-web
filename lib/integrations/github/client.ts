const TIMEOUT_MS = 20_000;
export const GITHUB_API = 'https://api.github.com';

export type GithubMethod = 'GET' | 'POST' | 'PUT' | 'PATCH';

export interface GithubRequestOptions {
  method?: GithubMethod;
  body?: unknown;
}

export interface GithubReply {
  /** Parsed JSON, or `null` for a 204. */
  data: unknown;
  headers: Headers;
}

export function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

export function unexpected(where: string, detail: string): Error {
  return new Error(`resposta inesperada do GitHub ${where}: ${detail}`);
}

/** A hora em que a cota do GitHub volta, já em relógio de parede: o cabeçalho
 *  vem em segundos desde a época, que não diz nada a quem lê a mensagem. */
function resetAt(header: string | null): string {
  const seconds = Number(header);
  if (!Number.isFinite(seconds) || seconds <= 0) return '';
  return new Date(seconds * 1000).toLocaleTimeString('pt-BR', {
    hour: '2-digit',
    minute: '2-digit',
  });
}

function rateLimitMessage(headers: Headers): string {
  const volta = resetAt(headers.get('x-ratelimit-reset'));
  return `limite de requisições do GitHub atingido — restam 0${volta ? `, volta às ${volta}` : ''}`;
}

function errorEntryText(entry: unknown): string {
  if (typeof entry === 'string') return entry.trim();
  if (!isRecord(entry)) return '';
  if (typeof entry.message === 'string' && entry.message.trim()) return entry.message.trim();
  return [entry.field, entry.code]
    .filter((part): part is string => typeof part === 'string' && part !== '')
    .join(' ');
}

/** GitHub's own explanation from an error body `{ message, errors[] }`, e.g.
 *  "Validation Failed: Pull Request is not mergeable". `null` when the body
 *  carries none. */
export function githubErrorDetail(body: unknown): string | null {
  if (!isRecord(body)) return null;
  const message = typeof body.message === 'string' ? body.message.trim() : '';
  const details = (Array.isArray(body.errors) ? body.errors : [])
    .map(errorEntryText)
    .filter((text) => text !== '' && text !== message);
  if (!message && details.length === 0) return null;
  if (!message) return details.join('; ');
  return details.length > 0 ? `${message}: ${details.join('; ')}` : message;
}

async function readBody(response: Response): Promise<unknown> {
  const text = await response.text().catch(() => '');
  if (text === '') return null;
  try {
    return JSON.parse(text) as unknown;
  } catch {
    return null;
  }
}

function failureMessage(status: number, headers: Headers, body: unknown): string {
  if (status === 401) return 'o GitHub recusou o token';
  const detail = githubErrorDetail(body);
  if ((status === 403 || status === 429) && headers.get('x-ratelimit-remaining') === '0') {
    return rateLimitMessage(headers);
  }
  if (detail && /rate limit/i.test(detail)) return `limite de requisições do GitHub atingido: ${detail}`;
  if (status === 403) return detail ? `o token não tem permissão: ${detail}` : 'o token não tem permissão';
  return detail ? `GitHub respondeu ${status}: ${detail}` : `GitHub respondeu ${status}`;
}

/** One REST call with the module's auth, timeout and error mapping. `path`
 *  must start with `/` and have each segment already encoded. */
export async function githubCall(
  token: string,
  path: string,
  options: GithubRequestOptions = {},
): Promise<GithubReply> {
  // Without the leading slash, "@host/x" would turn api.github.com into userinfo.
  if (!path.startsWith('/')) throw new Error(`caminho inválido para a API do GitHub: ${path}`);
  const hasBody = options.body !== undefined;
  const response = await fetch(`${GITHUB_API}${path}`, {
    method: options.method ?? 'GET',
    headers: {
      authorization: `Bearer ${token}`,
      accept: 'application/vnd.github+json',
      'x-github-api-version': '2022-11-28',
      ...(hasBody ? { 'content-type': 'application/json' } : {}),
    },
    body: hasBody ? JSON.stringify(options.body) : undefined,
    signal: AbortSignal.timeout(TIMEOUT_MS),
  });

  if (!response.ok) {
    throw new Error(failureMessage(response.status, response.headers, await readBody(response)));
  }
  if (response.status === 204) return { data: null, headers: response.headers };
  const text = await response.text();
  try {
    return { data: JSON.parse(text) as unknown, headers: response.headers };
  } catch {
    throw unexpected(`em ${path}`, 'o corpo não é JSON');
  }
}

export async function githubRequest(
  token: string,
  path: string,
  options: GithubRequestOptions = {},
): Promise<unknown> {
  return (await githubCall(token, path, options)).data;
}

export interface GraphqlError {
  message: string;
  /** E.g. `NOT_FOUND`, `RATE_LIMITED`; `null` when GitHub sends none. */
  type: string | null;
  /** First path segment is the alias that failed. */
  path: string[];
}

export interface GraphqlReply {
  data: Record<string, unknown>;
  errors: GraphqlError[];
  headers: Headers;
}

function parseGraphqlError(raw: unknown): GraphqlError {
  if (!isRecord(raw)) return { message: 'erro sem descrição', type: null, path: [] };
  return {
    message: typeof raw.message === 'string' && raw.message.trim() ? raw.message.trim() : 'erro sem descrição',
    type: typeof raw.type === 'string' ? raw.type : null,
    path: Array.isArray(raw.path) ? raw.path.map(String) : [],
  };
}

export function graphqlErrorMessage(error: GraphqlError): string {
  return `o GitHub recusou a consulta: ${error.message}`;
}

/** One GraphQL query. A 200 with `errors` and no `data` throws the first
 *  message; partial `data` comes back with its `errors` so the caller can
 *  fail one alias without failing the rest. */
export async function githubGraphql(
  token: string,
  query: string,
  variables: Record<string, unknown> = {},
): Promise<GraphqlReply> {
  const { data: body, headers } = await githubCall(token, '/graphql', {
    method: 'POST',
    body: { query, variables },
  });
  if (!isRecord(body)) throw unexpected('no GraphQL', 'o corpo não é um objeto');

  const errors = (Array.isArray(body.errors) ? body.errors : []).map(parseGraphqlError);
  if (errors.some((error) => error.type === 'RATE_LIMITED')) throw new Error(rateLimitMessage(headers));

  const data = isRecord(body.data) ? body.data : null;
  if (data === null) {
    if (errors.length > 0) throw new Error(graphqlErrorMessage(errors[0]));
    throw unexpected('no GraphQL', '`data` ausente');
  }
  return { data, errors, headers };
}
