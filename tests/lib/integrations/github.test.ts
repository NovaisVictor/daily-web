import { describe, expect, it } from 'vitest';
import { afterEach, beforeEach, vi } from 'vitest';
import {
  fetchReviewRequests,
  groupByRepo,
  parseRepoList,
  rankPulls,
  repoUrl,
  REVIEW_REQUESTS_QUERY,
  scopeNote,
  serializeRepoList,
} from '@/lib/integrations/githubApi';
import type { Connection } from '@/lib/vault/connections';
import type { PullRequestItem } from '@/lib/types';

function item(over: Partial<PullRequestItem>): PullRequestItem {
  return {
    repo: 'joao/repo',
    number: 1,
    title: 't',
    url: 'u',
    author: 'a',
    draft: false,
    awaitingYou: false,
    mine: false,
    isPullRequest: true,
    updatedAt: '2026-08-01T00:00:00Z',
    id: 'PR_test',
    createdAt: '2026-08-01T00:00:00Z',
    ci: 'none',
    failedChecks: [],
    review: 'none',
    pendingReviewers: [],
    merge: 'unknown',
    size: { additions: 1, deletions: 1, files: 1 },
    headRef: 'feature/x',
    baseRef: 'main',
    headSha: 'abc123',
    ...over,
  };
}

describe('rankPulls', () => {
  it('põe primeiro o que pediram para você revisar, depois o seu', () => {
    const ordered = rankPulls([
      item({ number: 1 }),
      item({ number: 2, mine: true }),
      item({ number: 3, awaitingYou: true }),
    ]);
    expect(ordered.map((p) => p.number)).toEqual([3, 2, 1]);
  });

  it('desempata pelo mais recente', () => {
    const ordered = rankPulls([
      item({ number: 1, updatedAt: '2026-08-01T00:00:00Z' }),
      item({ number: 2, updatedAt: '2026-08-20T00:00:00Z' }),
    ]);
    expect(ordered.map((p) => p.number)).toEqual([2, 1]);
  });
});

describe('lista de repositórios', () => {
  it('lê e escreve a lista separada por vírgula, ignorando espaços', () => {
    expect(parseRepoList(' a/b ,c/d , ')).toEqual(['a/b', 'c/d']);
    expect(serializeRepoList(['a/b', 'c/d'])).toBe('a/b, c/d');
  });

  it('devolve vazio para string vazia', () => {
    expect(parseRepoList('')).toEqual([]);
  });
});

describe('groupByRepo', () => {
  function pull(over: Partial<PullRequestItem>): PullRequestItem {
    return { ...item({}), isPullRequest: true, ...over };
  }

  // O endpoint /issues devolve issue e pull request na mesma lista; sem
  // separar, o painel misturava as duas coisas.
  it('separa issue de pull request dentro do repositório', () => {
    const grupos = groupByRepo([
      pull({ repo: 'a/b', number: 13, isPullRequest: true }),
      pull({ repo: 'a/b', number: 12, isPullRequest: false }),
    ]);
    expect(grupos).toHaveLength(1);
    expect(grupos[0].repo).toBe('a/b');
    expect(grupos[0].issues.map((i) => i.number)).toEqual([12]);
    expect(grupos[0].pulls.map((i) => i.number)).toEqual([13]);
  });

  it('agrupa por repositório, em ordem alfabética', () => {
    const grupos = groupByRepo([
      pull({ repo: 'z/z', number: 1 }),
      pull({ repo: 'a/a', number: 2 }),
    ]);
    expect(grupos.map((g) => g.repo)).toEqual(['a/a', 'z/z']);
  });

  it('mantém a ordem de prioridade dentro de cada seção', () => {
    const grupos = groupByRepo([
      pull({ repo: 'a/b', number: 1 }),
      pull({ repo: 'a/b', number: 2, awaitingYou: true }),
    ]);
    expect(grupos[0].pulls.map((p) => p.number)).toEqual([2, 1]);
  });

  it('não cria seção vazia no lugar errado', () => {
    const grupos = groupByRepo([pull({ repo: 'a/b', isPullRequest: false })]);
    expect(grupos[0].pulls).toEqual([]);
    expect(grupos[0].issues).toHaveLength(1);
  });

  it('devolve vazio para lista vazia', () => {
    expect(groupByRepo([])).toEqual([]);
  });
});

describe('repoUrl', () => {
  it('aponta para o repositório no GitHub', () => {
    expect(repoUrl('joaosouzacoder/daily-web')).toBe('https://github.com/joaosouzacoder/daily-web');
  });

  // O nome do repositório é digitado pelo usuário e vira href. Um valor
  // estranho não pode virar link nenhum: sem dono/nome não há URL.
  it('recusa o que não tem a forma dono/nome', () => {
    expect(repoUrl('daily-web')).toBeNull();
    expect(repoUrl('')).toBeNull();
    expect(repoUrl('a/b/c')).toBeNull();
  });

  it('recusa caminho relativo e esquema embutido', () => {
    expect(repoUrl('../../etc/passwd')).toBeNull();
    expect(repoUrl('javascript:alert(1)')).toBeNull();
    expect(repoUrl('joao/repo?x=1')).toBeNull();
    expect(repoUrl('https://evil.com/a')).toBeNull();
  });
});


// --- Revisões pedidas a você ---------------------------------------------------

function conn(token = 'ghp_token'): Connection {
  return {
    id: 'c1',
    module: 'pulls',
    label: 'GitHub',
    values: { token },
    createdAt: '',
    updatedAt: '',
  } as unknown as Connection;
}

/** A GraphQL search reply with one PR from a repo outside the tracked list. */
function searchReply(issueCount: number, nodes: unknown[], headers: Record<string, string> = {}, status = 200) {
  return new Response(JSON.stringify({ data: { search: { issueCount, nodes } } }), { status, headers });
}

function searchNode(over: Record<string, unknown> = {}) {
  return {
    id: 'PR_7',
    number: 7,
    title: 'Trocar o parser',
    url: 'https://github.com/outra/org/pull/7',
    isDraft: false,
    createdAt: '2026-09-01T10:00:00Z',
    updatedAt: '2026-09-10T10:00:00Z',
    author: { login: 'maria' },
    additions: 1,
    deletions: 1,
    changedFiles: 1,
    mergeable: 'MERGEABLE',
    mergeStateStatus: 'CLEAN',
    reviewDecision: 'REVIEW_REQUIRED',
    headRefName: 'feature/x',
    baseRefName: 'main',
    reviewRequests: { nodes: [] },
    commits: { nodes: [{ commit: { oid: 'abc', statusCheckRollup: null } }] },
    repository: { nameWithOwner: 'outra/org' },
    ...over,
  };
}

function reply(body: unknown, headers: Record<string, string> = {}, status = 200) {
  return new Response(JSON.stringify(body), { status, headers });
}

describe('REVIEW_REQUESTS_QUERY', () => {
  it('pede só o que ainda espera a sua revisão', () => {
    expect(REVIEW_REQUESTS_QUERY).toBe('is:open is:pr review-requested:@me');
  });
});

describe('fetchReviewRequests', () => {
  beforeEach(() => vi.restoreAllMocks());
  afterEach(() => vi.unstubAllGlobals());

  it('leva o repositório, o autor, a idade e o link', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(searchReply(1, [searchNode()])));

    const [item] = (await fetchReviewRequests(conn())).items;

    expect(item).toMatchObject({
      repo: 'outra/org',
      number: 7,
      title: 'Trocar o parser',
      url: 'https://github.com/outra/org/pull/7',
      author: 'maria',
      createdAt: '2026-09-01T10:00:00Z',
      updatedAt: '2026-09-10T10:00:00Z',
    });
  });

  it('toda linha da busca está esperando a sua revisão e não é sua', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(searchReply(1, [searchNode()])));

    const [item] = (await fetchReviewRequests(conn())).items;

    expect(item.awaitingYou).toBe(true);
    expect(item.mine).toBe(false);
    expect(item.isPullRequest).toBe(true);
  });
});

describe('scopeNote', () => {
  it('não avisa nada quando há o que mostrar', () => {
    expect(scopeNote('', false)).toBeNull();
    expect(scopeNote(null, false)).toBeNull();
  });

  it('com token clássico sem `repo`, explica o que fica de fora', () => {
    expect(scopeNote('read:user, gist', true)).toMatch(/escopo `repo`/);
  });

  it('com token clássico com `repo`, a lista vazia é vazia mesmo', () => {
    expect(scopeNote('repo, read:user', true)).toBeNull();
  });

  it('com token fine-grained, diz que o alcance é o que foi concedido', () => {
    expect(scopeNote(null, true)).toMatch(/fine-grained/);
  });
});

describe('fetchReviewRequests: a ida ao GitHub', () => {
  beforeEach(() => vi.restoreAllMocks());
  afterEach(() => vi.restoreAllMocks());

  it('faz uma chamada só, para a busca', async () => {
    const fetchMock = vi.fn().mockResolvedValue(searchReply(1, [searchNode()]));
    vi.stubGlobal('fetch', fetchMock);

    const digest = await fetchReviewRequests(conn());

    expect(fetchMock).toHaveBeenCalledTimes(1);
    expect(String(fetchMock.mock.calls[0][0])).toBe('https://api.github.com/graphql');
    expect(digest.items.map((i) => i.repo)).toEqual(['outra/org']);
    expect(digest.truncated).toBe(false);
    vi.unstubAllGlobals();
  });

  it('diz quando a página cortou a lista', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue(searchReply(250, [searchNode()])),
    );

    const digest = await fetchReviewRequests(conn());

    expect(digest.truncated).toBe(true);
    expect(digest.total).toBe(250);
    vi.unstubAllGlobals();
  });

  it('lista vazia com token sem alcance vira aviso, não silêncio', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue(searchReply(0, [], { 'x-oauth-scopes': 'gist' })),
    );

    const digest = await fetchReviewRequests(conn());

    expect(digest.items).toEqual([]);
    expect(digest.scopeNote).toMatch(/escopo `repo`/);
    vi.unstubAllGlobals();
  });

  it('lista vazia com token completo não inventa problema', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue(searchReply(0, [], { 'x-oauth-scopes': 'repo' })),
    );

    expect((await fetchReviewRequests(conn())).scopeNote).toBeNull();
    vi.unstubAllGlobals();
  });

  it('token recusado vira mensagem, não lista vazia', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(reply({}, {}, 401)));

    await expect(fetchReviewRequests(conn())).rejects.toThrow(/recusou o token/);
    vi.unstubAllGlobals();
  });

  it('sem permissão vira mensagem própria', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(reply({}, { 'x-ratelimit-remaining': '12' }, 403)));

    await expect(fetchReviewRequests(conn())).rejects.toThrow(/não tem permissão/);
    vi.unstubAllGlobals();
  });

  it('limite atingido diz quanto sobrou e quando volta', async () => {
    const reset = Math.floor(new Date('2026-09-14T18:30:00Z').getTime() / 1000);
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue(
        reply({}, { 'x-ratelimit-remaining': '0', 'x-ratelimit-reset': String(reset) }, 403),
      ),
    );

    await expect(fetchReviewRequests(conn())).rejects.toThrow(/restam 0, volta às \d{2}:\d{2}/);
    vi.unstubAllGlobals();
  });
});
