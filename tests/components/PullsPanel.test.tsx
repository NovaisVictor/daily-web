import { describe, expect, it, vi, afterEach, beforeEach } from 'vitest';
import { render, screen, cleanup, fireEvent, waitFor } from '@testing-library/react';
import { PullsPanel } from '@/components/PullsPanel';
import type { PullRequestItem, ReviewRequestsDigest } from '@/lib/types';
import { FocusBlockProvider } from '@/components/FocusBlockProvider';

/** A URL da página, em memória: o painel lê a aba dela e escreve nela, e o
 *  teste confere o que ficou gravado. */
const nav = vi.hoisted(() => ({
  search: '',
  history: [] as string[],
  listeners: new Set<() => void>(),
}));

vi.mock('next/navigation', async () => {
  const { useSyncExternalStore } = await import('react');
  const subscribe = (listener: () => void) => {
    nav.listeners.add(listener);
    return () => nav.listeners.delete(listener);
  };
  const push = (url: string) => {
    nav.history.push(url);
    nav.search = url.split('?')[1] ?? '';
    nav.listeners.forEach((listener) => listener());
  };
  return {
    usePathname: () => '/',
    useRouter: () => ({ push }),
    useSearchParams: () =>
      new URLSearchParams(useSyncExternalStore(subscribe, () => nav.search)),
  };
});


beforeEach(() => {
  nav.search = '';
  nav.history = [];
  vi.spyOn(global, 'fetch').mockResolvedValue(
    new Response(JSON.stringify({ repos: [] }), { status: 200 }),
  );
});

afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
});

function pull(over: Partial<PullRequestItem>): PullRequestItem {
  return {
    repo: 'joao/daily-web',
    number: 3,
    title: 'Arrumar o build',
    url: 'https://github.com/joao/daily-web/pull/3',
    author: 'joao',
    draft: false,
    awaitingYou: false,
    mine: true,
    isPullRequest: true,
    id: 'PR_test',
    createdAt: '',
    ci: 'none',
    failedChecks: [],
    review: 'none',
    pendingReviewers: [],
    reviewers: [],
    reviewRequestedAt: null,
    merge: 'unknown',
    size: { additions: 1, deletions: 1, files: 1 },
    headRef: 'feature/x',
    baseRef: 'main',
    headSha: 'abc123',
    updatedAt: '2026-08-26T10:00:00Z',
    ...over,
  };
}

describe('PullsPanel', () => {
  it('mostra agendar foco só quando há agenda Google', () => {
    vi.mocked(global.fetch).mockImplementation(
      async () => new Response(JSON.stringify({ repos: [] }), { status: 200 }),
    );
    const panel = <PullsPanel pulls={{ data: { items: [pull({})], errors: [], defaultBranches: [], truncated: [] }, error: null }} />;
    const { rerender } = render(panel);
    expect(screen.queryByLabelText('agendar foco para joao/daily-web#3')).not.toBeInTheDocument();
    rerender(
      <FocusBlockProvider calendars={[{ id: 'c', label: 'Google', account: 'a@b.com', canWrite: true }]} onCreated={() => {}}>
        {panel}
      </FocusBlockProvider>,
    );
    expect(screen.getByLabelText('agendar foco para joao/daily-web#3')).toBeInTheDocument();
  });

  it('lista cada PR com link para o GitHub', () => {
    render(<PullsPanel pulls={{ data: { items: [pull({})], errors: [], defaultBranches: [], truncated: [] }, error: null }} />);
    const link = screen.getByRole('link', { name: 'Arrumar o build' });
    expect(link).toHaveAttribute('href', 'https://github.com/joao/daily-web/pull/3');
    // O repositório virou cabeçalho do bloco; a linha só carrega o número.
    expect(screen.getByRole('heading', { name: 'joao/daily-web' })).toBeInTheDocument();
    expect(screen.getByText('#3')).toBeInTheDocument();
  });

  it('marca o PR que está esperando a sua revisão', () => {
    render(
      <PullsPanel
        pulls={{ data: { items: [pull({ awaitingYou: true })], errors: [], defaultBranches: [], truncated: [] }, error: null }}
      />,
    );
    expect(screen.getByText('revisar')).toBeInTheDocument();
  });

  it('mostra o autor quando o PR não é seu', () => {
    render(
      <PullsPanel
        pulls={{
          data: { items: [pull({ mine: false, author: 'dependabot[bot]' })], errors: [], defaultBranches: [], truncated: [] },
          error: null,
        }}
      />,
    );
    expect(screen.getByText('dependabot[bot]')).toBeInTheDocument();
  });

  it('marca rascunho', () => {
    render(<PullsPanel pulls={{ data: { items: [pull({ draft: true })], errors: [], defaultBranches: [], truncated: [] }, error: null }} />);
    expect(screen.getByText('rascunho')).toBeInTheDocument();
  });

  // Um repositório renomeado falha sozinho; os PRs dos outros continuam na
  // tela em vez de sumirem junto com ele.
  it('mostra o erro de um repositório sem esconder os PRs que vieram', () => {
    render(
      <PullsPanel
        pulls={{
          data: { items: [pull({})], errors: ['joao/antigo: GitHub respondeu 404'], defaultBranches: [], truncated: [] },
          error: null,
        }}
      />,
    );
    expect(screen.getByText('Arrumar o build')).toBeInTheDocument();
    expect(screen.getByRole('alert').textContent).toContain('404');
  });

  it('mostra o erro do painel quando presente', () => {
    render(<PullsPanel pulls={{ data: { items: [], errors: [], defaultBranches: [], truncated: [] }, error: 'o GitHub recusou o token' }} />);
    expect(screen.getByRole('alert').textContent).toContain('recusou o token');
  });

  it('busca e lista os repositórios acompanhados ao montar', async () => {
    vi.mocked(global.fetch).mockResolvedValue(
      new Response(JSON.stringify({ repos: ['joaosouzacoder/daily-web'] }), { status: 200 }),
    );
    render(<PullsPanel pulls={{ data: { items: [], errors: [], defaultBranches: [], truncated: [] }, error: null }} />);
    await waitFor(() => expect(screen.getByText('joaosouzacoder/daily-web')).toBeInTheDocument());
  });

  it('adiciona um repositório e chama onChanged', async () => {
    vi.mocked(global.fetch)
      .mockResolvedValueOnce(new Response(JSON.stringify({ repos: [] }), { status: 200 }))
      .mockResolvedValueOnce(new Response(JSON.stringify({ repos: ['a/b'] }), { status: 200 }));
    const onChanged = vi.fn();
    render(<PullsPanel pulls={{ data: { items: [], errors: [], defaultBranches: [], truncated: [] }, error: null }} onChanged={onChanged} />);
    fireEvent.change(screen.getByLabelText('novo repositório'), { target: { value: 'a/b' } });
    fireEvent.click(screen.getByRole('button', { name: 'Adicionar repositório' }));
    await waitFor(() => expect(onChanged).toHaveBeenCalled());
    expect(global.fetch).toHaveBeenCalledWith(
      '/api/pulls/repos',
      expect.objectContaining({ method: 'POST', body: JSON.stringify({ repo: 'a/b' }) }),
    );
  });

  it('mostra erro quando o servidor rejeita o repositório', async () => {
    vi.mocked(global.fetch)
      .mockResolvedValueOnce(new Response(JSON.stringify({ repos: [] }), { status: 200 }))
      .mockResolvedValueOnce(new Response(JSON.stringify({ error: 'repositório inválido' }), { status: 400 }));
    render(<PullsPanel pulls={{ data: { items: [], errors: [], defaultBranches: [], truncated: [] }, error: null }} />);
    fireEvent.change(screen.getByLabelText('novo repositório'), { target: { value: '-x' } });
    fireEvent.click(screen.getByRole('button', { name: 'Adicionar repositório' }));
    await waitFor(() => expect(screen.getByRole('alert').textContent).toContain('repositório inválido'));
  });

  it('remove um repositório e chama onChanged', async () => {
    vi.mocked(global.fetch)
      .mockResolvedValueOnce(new Response(JSON.stringify({ repos: ['a/b'] }), { status: 200 }))
      .mockResolvedValueOnce(new Response(JSON.stringify({ repos: [] }), { status: 200 }));
    const onChanged = vi.fn();
    render(<PullsPanel pulls={{ data: { items: [], errors: [], defaultBranches: [], truncated: [] }, error: null }} onChanged={onChanged} />);
    await waitFor(() => expect(screen.getByText('a/b')).toBeInTheDocument());
    fireEvent.click(screen.getByLabelText('remover a/b'));
    await waitFor(() => expect(onChanged).toHaveBeenCalled());
    expect(global.fetch).toHaveBeenCalledWith(
      '/api/pulls/repos',
      expect.objectContaining({ method: 'DELETE', body: JSON.stringify({ repo: 'a/b' }) }),
    );
  });
});

describe('repositório clicável', () => {
  it('o nome do repositório abre o repositório no GitHub', () => {
    render(<PullsPanel pulls={{ data: { items: [pull({})], errors: [], defaultBranches: [], truncated: [] }, error: null }} />);
    const link = screen.getByRole('link', { name: 'joao/daily-web' });
    expect(link).toHaveAttribute('href', 'https://github.com/joao/daily-web');
    expect(link).toHaveAttribute('target', '_blank');
  });

  // O nome vem da configuração do usuário e vira href. O que não tem a forma
  // dono/nome continua no cabeçalho, como texto.
  it('um nome fora do formato continua texto, sem virar link', () => {
    render(
      <PullsPanel
        pulls={{ data: { items: [pull({ repo: 'javascript:alert(1)' })], errors: [], defaultBranches: [], truncated: [] }, error: null }}
      />,
    );
    expect(screen.queryByRole('link', { name: 'javascript:alert(1)' })).toBeNull();
    expect(screen.getByRole('heading', { name: 'javascript:alert(1)' })).toBeInTheDocument();
  });
});

describe('aba de revisões pedidas', () => {
  function review(over: Partial<ReviewRequestsDigest> = {}): ReviewRequestsDigest {
    return { items: [], truncated: false, total: 0, scopeNote: null, ...over };
  }

  const pedido = pull({
    repo: 'outra/org',
    number: 7,
    title: 'Trocar o parser',
    url: 'https://github.com/outra/org/pull/7',
    author: 'maria',
    mine: false,
    awaitingYou: true,
    createdAt: '2026-09-01T10:00:00Z',
  });

  function abrirRevisoes() {
    fireEvent.click(screen.getByRole('tab', { name: /Revisões/ }));
  }

  it('a aba padrão não vai para a URL, e a outra vai', () => {
    render(
      <PullsPanel
        pulls={{ data: { items: [], errors: [], defaultBranches: [], truncated: [] }, error: null }}
        reviewRequests={{ data: review(), error: null }}
      />,
    );

    abrirRevisoes();
    expect(nav.history.at(-1)).toBe('/?pulls=revisoes');

    fireEvent.click(screen.getByRole('tab', { name: /Acompanhados/ }));
    expect(nav.history.at(-1)).toBe('/');
  });

  it('um valor que não é aba nenhuma cai na padrão', () => {
    nav.search = 'pulls=inventada';
    render(
      <PullsPanel
        pulls={{ data: { items: [pull({})], errors: [], defaultBranches: [], truncated: [] }, error: null }}
        reviewRequests={{ data: review({ items: [pedido] }), error: null }}
      />,
    );

    expect(screen.getByRole('tab', { name: /Acompanhados/ })).toHaveAttribute(
      'aria-selected',
      'true',
    );
  });

  it('a aba vem aberta quando a URL pede', () => {
    nav.search = 'pulls=revisoes';
    render(
      <PullsPanel
        pulls={{ data: { items: [], errors: [], defaultBranches: [], truncated: [] }, error: null }}
        reviewRequests={{ data: review({ items: [pedido] }), error: null }}
      />,
    );

    expect(screen.getByRole('link', { name: 'Trocar o parser' })).toBeInTheDocument();
  });

  it('a aba Meus PRs vem aberta quando a URL pede, agrupada pelo que trava cada PR', () => {
    nav.search = 'pulls=meus';
    render(
      <PullsPanel
        pulls={{ data: { items: [], errors: [], defaultBranches: [], truncated: [] }, error: null }}
        myPulls={{ data: { items: [pull({ ci: 'failing' })], truncated: false, total: 1 }, error: null }}
      />,
    );

    expect(screen.getByRole('heading', { name: /Precisa de você/ })).toBeInTheDocument();
  });

  it('cada linha diz de qual repositório veio, com link para ele', () => {
    render(
      <PullsPanel
        pulls={{ data: { items: [], errors: [], defaultBranches: [], truncated: [] }, error: null }}
        reviewRequests={{ data: review({ items: [pedido] }), error: null }}
      />,
    );
    abrirRevisoes();

    expect(screen.getByRole('link', { name: 'outra/org' })).toHaveAttribute(
      'href',
      'https://github.com/outra/org',
    );
    expect(screen.getByRole('link', { name: 'Trocar o parser' })).toHaveAttribute(
      'href',
      'https://github.com/outra/org/pull/7',
    );
    expect(screen.getByText('maria')).toBeInTheDocument();
    expect(screen.getByText('#7')).toBeInTheDocument();
  });

  it('lista vazia diz que não há pedido', () => {
    render(
      <PullsPanel
        pulls={{ data: { items: [], errors: [], defaultBranches: [], truncated: [] }, error: null }}
        reviewRequests={{ data: review(), error: null }}
      />,
    );
    abrirRevisoes();

    expect(screen.getByText(/Nenhuma revisão pedida a você/)).toBeInTheDocument();
  });

  it('lista vazia por alcance do token explica o que fazer', () => {
    render(
      <PullsPanel
        pulls={{ data: { items: [], errors: [], defaultBranches: [], truncated: [] }, error: null }}
        reviewRequests={{
          data: review({ scopeNote: 'este token clássico não tem o escopo `repo`' }),
          error: null,
        }}
      />,
    );
    abrirRevisoes();

    expect(screen.getByText(/não tem o escopo `repo`/)).toBeInTheDocument();
  });

  it('token recusado aparece como erro, não como lista vazia', () => {
    render(
      <PullsPanel
        pulls={{ data: { items: [], errors: [], defaultBranches: [], truncated: [] }, error: null }}
        reviewRequests={{ data: null, error: 'o GitHub recusou o token' }}
      />,
    );
    abrirRevisoes();

    expect(screen.getByText('o GitHub recusou o token')).toBeInTheDocument();
    expect(screen.queryByText(/Nenhuma revisão pedida/)).not.toBeInTheDocument();
  });

  it('avisa quando a página cortou a lista', () => {
    render(
      <PullsPanel
        pulls={{ data: { items: [], errors: [], defaultBranches: [], truncated: [] }, error: null }}
        reviewRequests={{ data: review({ items: [pedido], truncated: true, total: 250 }), error: null }}
      />,
    );
    abrirRevisoes();

    expect(screen.getByText(/Mostrando 1 de 250/)).toBeInTheDocument();
  });

  it('a gaveta de repositórios acompanhados não segue para a outra aba', () => {
    render(
      <PullsPanel
        pulls={{ data: { items: [], errors: [], defaultBranches: [], truncated: [] }, error: null }}
        reviewRequests={{ data: review({ items: [pedido] }), error: null }}
      />,
    );
    expect(screen.getByText('Repositórios acompanhados')).toBeInTheDocument();

    abrirRevisoes();
    expect(screen.queryByText('Repositórios acompanhados')).not.toBeInTheDocument();
  });
});

describe('cards do Jira no PR', () => {
  it('mostra a chave com link e o status atual de cada card citado', () => {
    render(
      <PullsPanel
        pulls={{
          data: {
            items: [
              pull({
                title: 'feat: login (TT-42, TT-43)',
                jira: [
                  { key: 'TT-42', url: 'https://acme.atlassian.net/browse/TT-42', status: 'Code Review PR', statusCategory: 'indeterminate' },
                  { key: 'TT-43', url: 'https://acme.atlassian.net/browse/TT-43', status: 'Resolvido', statusCategory: 'done' },
                ],
              }),
            ],
            errors: [],
            defaultBranches: [],
            truncated: [],
          },
          error: null,
        }}
      />,
    );
    const card = screen.getByTitle('TT-42 no Jira');
    expect(card).toHaveAttribute('href', 'https://acme.atlassian.net/browse/TT-42');
    expect(card).toHaveTextContent('Code review pr');
    expect(screen.getByTitle('TT-43 no Jira').querySelector('.jira-status-done')).not.toBeNull();
  });

  it('PR sem card não ganha selo', () => {
    render(<PullsPanel pulls={{ data: { items: [pull({})], errors: [], defaultBranches: [], truncated: [] }, error: null }} />);
    expect(screen.queryByTitle(/no Jira$/)).toBeNull();
  });
});

describe('filtros sem resultado', () => {
  const digest = { items: [pull({})], errors: [], defaultBranches: [], truncated: [] };
  const semNada = { items: [], truncated: false, total: 0, scopeNote: null };

  it('Acompanhados diz que os filtros não acharam nada, não que não há PR aberto', () => {
    nav.search = 'pr_q=inexistente';
    render(<PullsPanel pulls={{ data: digest, error: null }} />);
    expect(screen.getByText('Nenhum resultado para os filtros.')).toBeInTheDocument();
  });

  it('Revisões diz que os filtros não acharam nada', () => {
    nav.search = 'pulls=revisoes&pr_q=inexistente';
    render(
      <PullsPanel
        pulls={{ data: digest, error: null }}
        reviewRequests={{ data: { ...semNada, items: [pull({ awaitingYou: true, mine: false })], total: 1 }, error: null }}
      />,
    );
    expect(screen.getByText('Nenhum resultado para os filtros.')).toBeInTheDocument();
  });

  it('Meus PRs diz que os filtros não acharam nada', () => {
    nav.search = 'pulls=meus&pr_q=inexistente';
    render(
      <PullsPanel
        pulls={{ data: digest, error: null }}
        myPulls={{ data: { items: [pull({})], truncated: false, total: 1 }, error: null }}
      />,
    );
    expect(screen.getByText('Nenhum resultado para os filtros.')).toBeInTheDocument();
  });

  it('sem filtro, a lista vazia continua dizendo que não há nada aberto', () => {
    render(<PullsPanel pulls={{ data: { ...digest, items: [] }, error: null }} />);
    expect(screen.getByText('Nada aberto nos repositórios acompanhados.')).toBeInTheDocument();
  });
});

describe('repositório com mais do que cabe numa página', () => {
  it('diz quantos pull requests vieram de quantos existem', () => {
    render(
      <PullsPanel
        pulls={{
          data: {
            items: [pull({})],
            errors: [],
            defaultBranches: [],
            truncated: [{ repo: 'joao/daily-web', kind: 'pulls', shown: 50, total: 80 }],
          },
          error: null,
        }}
      />,
    );
    expect(screen.getByText('Mostrando 50 de 80 pull requests')).toBeInTheDocument();
  });

  it('diz quantas issues vieram de quantas existem', () => {
    render(
      <PullsPanel
        pulls={{
          data: {
            items: [pull({ isPullRequest: false, number: 9 })],
            errors: [],
            defaultBranches: [],
            truncated: [{ repo: 'joao/daily-web', kind: 'issues', shown: 50, total: 61 }],
          },
          error: null,
        }}
      />,
    );
    expect(screen.getByText('Mostrando 50 de 61 issues')).toBeInTheDocument();
  });
});

describe('busca com parte dos dados recusada', () => {
  it('mostra o aviso junto da lista de revisões que veio', () => {
    nav.search = 'pulls=revisoes';
    render(
      <PullsPanel
        pulls={{ data: { items: [], errors: [], defaultBranches: [], truncated: [] }, error: null }}
        reviewRequests={{
          data: {
            items: [pull({ awaitingYou: true, mine: false })],
            truncated: false,
            total: 1,
            scopeNote: null,
            errors: ['busca do GitHub: parte dos dados não veio (FORBIDDEN)'],
          },
          error: null,
        }}
      />,
    );
    expect(screen.getByText('busca do GitHub: parte dos dados não veio (FORBIDDEN)')).toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'Arrumar o build' })).toBeInTheDocument();
  });
});
