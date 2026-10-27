import { describe, expect, it, afterEach, beforeEach, vi } from 'vitest';
import type { ComponentProps } from 'react';
import { render, screen, cleanup, fireEvent, waitFor, within } from '@testing-library/react';
import { JiraPanel } from '@/components/JiraPanel';
import type { JiraDatedItem, JiraItem, JiraProblemItem, PullRequestItem } from '@/lib/types';
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
  // Filtros substituem a última entrada em vez de empilhar uma nova.
  const replace = (url: string) => {
    nav.history[nav.history.length > 0 ? nav.history.length - 1 : 0] = url;
    nav.search = url.split('?')[1] ?? '';
    nav.listeners.forEach((listener) => listener());
  };
  return {
    usePathname: () => '/',
    useRouter: () => ({ push, replace }),
    useSearchParams: () =>
      new URLSearchParams(useSyncExternalStore(subscribe, () => nav.search)),
  };
});

/** O status aparece também como opção do filtro; estes testes falam da linha. */
const NA_LISTA = 'script, style, option';

/** Papel, exibição, status, tipo e hierarquia ficam atrás do gatilho "Filtros". */
const abrirFiltros = () => fireEvent.click(screen.getByRole('button', { name: /^Filtros/ }));

vi.mock('@/lib/hooks/useJiraPersonView', () => ({
  useJiraPersonView: vi.fn().mockReturnValue({ view: null, loading: false, error: null }),
}));

/** As três listas do painel são obrigatórias; cada teste só quer falar de
 *  uma delas, então o resto vem vazio por padrão. */
function Panel(props: Partial<ComponentProps<typeof JiraPanel>>) {
  return (
    <JiraPanel
      jira={{ data: [], error: null }}
      watched={{ data: [], error: null }}
      delivered={{ data: [], error: null }}
      approved={{ data: [], error: null }}
      problems={{ data: [], error: null }}
      ancestors={[]}
      people={[]}
      refreshedAt={null}
      onChanged={() => {}}
      {...props}
    />
  );
}

function issue(over: Partial<JiraItem>): JiraItem {
  return {
    key: 'A-1',
    summary: 'Resumo',
    status: 'Aberto',
    statusCategory: 'new',
    project: 'A',
    url: 'https://example/A-1',
    parent: null,
    role: 'assignee',
    awaitingApproval: false,
    kind: 'História',
    subtask: false,
    hierarchyLevel: null,
    updatedAt: new Date().toISOString(),
    dueDate: '',
    priority: null,
    flag: 'none',
    ...over,
  };
}

function dated(over: Partial<JiraDatedItem>): JiraDatedItem {
  return { ...issue({}), today: true, ...over };
}

afterEach(() => {
  cleanup();
  nav.search = '';
  nav.history = [];
  vi.unstubAllGlobals();
});

describe('JiraPanel', () => {
  it('mostra agendar foco só quando há agenda Google', () => {
    const panel = <Panel jira={{ data: [issue({})], error: null }} />;
    const { rerender } = render(panel);
    expect(screen.queryByLabelText('agendar foco para A-1')).not.toBeInTheDocument();
    rerender(
      <FocusBlockProvider calendars={[{ id: 'c', label: 'Google', account: 'a@b.com', canWrite: true }]} onCreated={() => {}}>
        {panel}
      </FocusBlockProvider>,
    );
    expect(screen.getByLabelText('agendar foco para A-1')).toBeInTheDocument();
  });

  it('lista as issues com chave e resumo', () => {
    render(<Panel watched={{ data: [], error: null }} onChanged={() => {}} jira={{ data: [issue({})], error: null }} />);
    expect(screen.getByText('A-1')).toBeInTheDocument();
    expect(screen.getByText('Resumo')).toBeInTheDocument();
  });

  it('mostra issues com papel both no filtro minhas', () => {
    render(
      <Panel
        watched={{ data: [], error: null }}
        onChanged={() => {}}
        jira={{
          data: [issue({ key: 'A-1', role: 'reporter' }), issue({ key: 'A-2', role: 'both' })],
          error: null,
        }}
      />,
    );
    abrirFiltros();
    fireEvent.click(screen.getByRole('button', { name: 'Minhas' }));
    expect(screen.getByText('A-2')).toBeInTheDocument();
    expect(screen.queryByText('A-1')).toBeNull();
  });

  it('mostra issues com papel both no filtro relator', () => {
    render(
      <Panel
        watched={{ data: [], error: null }}
        onChanged={() => {}}
        jira={{
          data: [issue({ key: 'A-1', role: 'assignee' }), issue({ key: 'A-2', role: 'both' })],
          error: null,
        }}
      />,
    );
    abrirFiltros();
    fireEvent.click(screen.getByRole('button', { name: 'Relator' }));
    expect(screen.getByText('A-2')).toBeInTheDocument();
    expect(screen.queryByText('A-1')).toBeNull();
  });

  it('filtra por busca textual', () => {
    render(
      <Panel
        watched={{ data: [], error: null }}
        onChanged={() => {}}
        jira={{
          data: [
            issue({ key: 'A-1', summary: 'Corrigir login' }),
            issue({ key: 'A-2', summary: 'Ajustar deploy' }),
          ],
          error: null,
        }}
      />,
    );
    fireEvent.change(screen.getByLabelText('buscar issues'), { target: { value: 'login' } });
    expect(screen.getByText('A-1')).toBeInTheDocument();
    expect(screen.queryByText('A-2')).toBeNull();
  });

  it('separa os projetos em blocos próprios na hierarquia', () => {
    render(
      <Panel
        watched={{ data: [], error: null }}
        onChanged={() => {}}
        jira={{
          data: [
            issue({ key: 'PDS-1', project: 'PDS', summary: 'Chamado' }),
            issue({ key: 'TT-1', project: 'TT', summary: 'História' }),
          ],
          error: null,
        }}
      />,
    );
    expect(screen.getByRole('heading', { name: /PDS/ })).toBeInTheDocument();
    expect(screen.getByRole('heading', { name: /TT/ })).toBeInTheDocument();
  });

  it('aninha a filha sob a mãe quando as duas estão na lista', () => {
    render(
      <Panel
        watched={{ data: [], error: null }}
        onChanged={() => {}}
        jira={{
          data: [
            issue({ key: 'TT-1', project: 'TT', summary: 'Épico mãe' }),
            issue({
              key: 'TT-9',
              project: 'TT',
              summary: 'História filha',
              parent: { key: 'TT-1', summary: 'Épico mãe' },
            }),
          ],
          error: null,
        }}
      />,
    );
    // O ramo começa fechado; a seta é que revela a filha.
    fireEvent.click(screen.getByLabelText(/expandir a issue sob TT-1/));

    const rows = screen.getAllByRole('listitem');
    // A mãe vem primeiro e a filha logo abaixo, recuada.
    expect(rows[0].textContent).toContain('TT-1');
    expect(rows[1].textContent).toContain('TT-9');
    expect(rows[1].getAttribute('style')).toContain('padding-left: calc(1.5rem)');
  });

  it('começa a árvore no objetivo, com o caminho já aberto', () => {
    render(
      <Panel
        watched={{ data: [], error: null }}
        onChanged={() => {}}
        jira={{
          data: [
            issue({
              key: 'TT-9',
              project: 'TT',
              summary: 'História minha',
              parent: { key: 'TT-5', summary: 'Épico' },
            }),
          ],
          error: null,
        }}
        ancestors={[
          issue({
            key: 'TT-5',
            project: 'TT',
            summary: 'Épico',
            kind: 'Epic',
            parent: { key: 'TT-1', summary: 'Objetivo' },
          }),
          issue({ key: 'TT-1', project: 'TT', summary: 'Objetivo', kind: 'Objective' }),
        ]}
      />,
    );

    // Nada de clicar: o caminho até o objetivo nasce aberto, senão a história
    // ficaria escondida atrás de dois níveis que não são de ninguém.
    const rows = screen.getAllByRole('listitem');
    expect(rows.map((row) => row.textContent?.match(/TT-\d+/)?.[0])).toEqual([
      'TT-1',
      'TT-5',
      'TT-9',
    ]);
  });

  it('leaves the status of an ancestor row as plain text, without the transition picker', () => {
    render(
      <Panel
        watched={{ data: [], error: null }}
        onChanged={() => {}}
        jira={{
          data: [
            issue({
              key: 'TT-9',
              project: 'TT',
              summary: 'História minha',
              parent: { key: 'TT-1', summary: 'Objetivo' },
            }),
          ],
          error: null,
        }}
        ancestors={[issue({ key: 'TT-1', project: 'TT', summary: 'Objetivo', kind: 'Objective' })]}
      />,
    );

    expect(screen.getByRole('button', { name: /^mudar status de TT-9 / })).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /^mudar status de TT-1 / })).not.toBeInTheDocument();
  });

  it('recolhe o caminho quando o usuário fecha o ramo', () => {
    render(
      <Panel
        watched={{ data: [], error: null }}
        onChanged={() => {}}
        jira={{
          data: [
            issue({
              key: 'TT-9',
              project: 'TT',
              summary: 'História minha',
              parent: { key: 'TT-1', summary: 'Objetivo' },
            }),
          ],
          error: null,
        }}
        ancestors={[
          issue({ key: 'TT-1', project: 'TT', summary: 'Objetivo', kind: 'Objective' }),
        ]}
      />,
    );

    fireEvent.click(screen.getByLabelText(/recolher a issue sob TT-1/));

    const rows = screen.getAllByRole('listitem');
    expect(rows).toHaveLength(1);
    expect(rows[0].textContent).toContain('TT-1');
  });

  // O contador do projeto diz quanto trabalho há ali. O caminho até o
  // objetivo não é trabalho de ninguém e não entra na conta.
  it('não conta o caminho no total do projeto', () => {
    render(
      <Panel
        watched={{ data: [], error: null }}
        onChanged={() => {}}
        jira={{
          data: [
            issue({
              key: 'TT-9',
              project: 'TT',
              summary: 'História minha',
              parent: { key: 'TT-1', summary: 'Objetivo' },
            }),
          ],
          error: null,
        }}
        ancestors={[
          issue({ key: 'TT-1', project: 'TT', summary: 'Objetivo', kind: 'Objective' }),
        ]}
      />,
    );

    expect(screen.getByRole('heading', { name: /TT/ }).textContent).toContain('1');
  });

  // Fora da hierarquia, o agrupamento passou a ser por situação. Agrupar por
  // projeto quase não agrupava: 16 das 19 issues reais são do mesmo projeto.
  it('na lista simples, agrupa por situação em vez de projeto', () => {
    render(
      <Panel
        watched={{ data: [], error: null }}
        onChanged={() => {}}
        jira={{
          data: [
            issue({ key: 'TT-1', project: 'TT', statusCategory: 'indeterminate', status: 'Em andamento' }),
            issue({ key: 'TT-2', project: 'TT', statusCategory: 'new', status: 'Backlog' }),
          ],
          error: null,
        }}
      />,
    );
    abrirFiltros();
    fireEvent.click(screen.getByRole('button', { name: 'Hierarquia' }));

    expect(screen.queryByRole('heading', { name: /^TT/ })).toBeNull();
    expect(screen.getByRole('heading', { name: /Em andamento/ })).toBeInTheDocument();
    expect(screen.getByRole('heading', { name: /Pendentes/ })).toBeInTheDocument();
    expect(screen.getByText('TT-1')).toBeInTheDocument();
  });

  it('mostra o contador quando um filtro está ativo', () => {
    render(
      <Panel
        watched={{ data: [], error: null }}
        onChanged={() => {}}
        jira={{
          data: [issue({ key: 'A-1', role: 'assignee' }), issue({ key: 'A-2', role: 'reporter' })],
          error: null,
        }}
      />,
    );
    abrirFiltros();
    fireEvent.click(screen.getByRole('button', { name: 'Relator' }));
    expect(screen.getByText('1 de 2')).toBeInTheDocument();
  });

  it('mostra o erro do painel quando presente', () => {
    render(<Panel watched={{ data: [], error: null }} onChanged={() => {}} jira={{ data: null, error: 'jira falhou' }} />);
    expect(screen.getByRole('alert').textContent).toContain('jira falhou');
  });
});

describe('situação, idade e prazo na linha', () => {
  // O selo antigo mostrava o papel, que em 15 de 19 issues dizia a mesma
  // coisa. O status tem cinco valores distintos e é o que faltava.
  it('mostra o status em vez do papel padrão', () => {
    render(<Panel watched={{ data: [], error: null }} onChanged={() => {}} jira={{ data: [issue({ status: 'Freezing' })], error: null }} />);
    expect(screen.getByText('Freezing', { ignore: NA_LISTA })).toBeInTheDocument();
    expect(screen.queryByText('RES')).toBeNull();
  });

  it('ainda marca quando você é só o relator, que é a exceção', () => {
    render(<Panel watched={{ data: [], error: null }} onChanged={() => {}} jira={{ data: [issue({ role: 'reporter' })], error: null }} />);
    abrirFiltros();
    fireEvent.click(screen.getByRole('button', { name: 'Ambas' }));
    expect(screen.getByText('REL')).toBeInTheDocument();
  });

  it('junta o mesmo status escrito com caixas diferentes', () => {
    render(
      <Panel
        watched={{ data: [], error: null }}
        onChanged={() => {}}
        jira={{
          data: [
            issue({ key: 'A-1', status: 'Em andamento', statusCategory: 'indeterminate' }),
            issue({ key: 'A-2', status: 'Em Andamento', statusCategory: 'indeterminate' }),
          ],
          error: null,
        }}
      />,
    );
    expect(screen.getAllByText('Em andamento', { ignore: NA_LISTA })).toHaveLength(2);
  });

  function diasAtras(dias: number): string {
    return new Date(Date.now() - dias * 86400000).toISOString();
  }

  it('avisa o que está parado há tempo demais', () => {
    render(<Panel watched={{ data: [], error: null }} onChanged={() => {}} jira={{ data: [issue({ updatedAt: diasAtras(14) })], error: null }} />);
    expect(screen.getByText('parado há 14d')).toBeInTheDocument();
  });

  // Quase tudo é mexido a cada dois dias; avisar sempre apagaria o sinal.
  it('cala sobre o que foi mexido há pouco', () => {
    render(<Panel watched={{ data: [], error: null }} onChanged={() => {}} jira={{ data: [issue({ updatedAt: diasAtras(1) })], error: null }} />);
    expect(screen.queryByText(/parado há/)).toBeNull();
  });

  it('mostra o prazo e destaca o atraso', () => {
    const ontem = new Date(Date.now() - 86400000);
    const iso = (d: Date) =>
      `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;

    render(<Panel watched={{ data: [], error: null }} onChanged={() => {}} jira={{ data: [issue({ dueDate: iso(ontem) })], error: null }} />);
    const prazo = screen.getByText('venceu há 1d');
    expect(prazo).toBeInTheDocument();
    expect(prazo.className).toContain('is-overdue');
  });

  it('não inventa prazo para issue sem data', () => {
    render(<Panel watched={{ data: [], error: null }} onChanged={() => {}} jira={{ data: [issue({ dueDate: '' })], error: null }} />);
    expect(screen.queryByText(/vence/)).toBeNull();
  });
});

describe('acompanhamento otimista', () => {
  const acompanhada: JiraItem = {
    ...issue({}),
    key: 'PDS-1075',
    summary: 'Issue de outro time',
  };

  function montar(onChanged = () => {}) {
    render(
      <Panel
        jira={{ data: [], error: null }}
        watched={{ data: [acompanhada], error: null }}
        onChanged={onChanged}
      />,
    );
  }

  // Remover é decisão local: esperar o onChanged é esperar o Jira responder
  // de novo, segundos para nada.
  it('some da lista assim que o servidor aceita, sem esperar recarregar', async () => {
    const fetchMock = vi.fn().mockResolvedValue({ ok: true, json: async () => ({}) });
    vi.stubGlobal('fetch', fetchMock);
    montar();

    expect(screen.getByText('PDS-1075')).toBeInTheDocument();
    fireEvent.click(screen.getByLabelText('parar de acompanhar PDS-1075'));

    await waitFor(() => expect(screen.queryByText('PDS-1075')).not.toBeInTheDocument());
    expect(screen.getByText('Nenhuma issue acompanhada.')).toBeInTheDocument();
  });

  it('manda a chave no DELETE', async () => {
    const fetchMock = vi.fn().mockResolvedValue({ ok: true, json: async () => ({}) });
    vi.stubGlobal('fetch', fetchMock);
    montar();

    fireEvent.click(screen.getByLabelText('parar de acompanhar PDS-1075'));
    await waitFor(() => expect(fetchMock).toHaveBeenCalled());
    const [url, init] = fetchMock.mock.calls[0];
    expect(url).toBe('/api/jira/watch');
    expect(init.method).toBe('DELETE');
    expect(JSON.parse(init.body)).toEqual({ key: 'PDS-1075' });
  });

  // Sumir da tela e continuar acompanhando no servidor seria pior do que não
  // sumir: a issue volta na próxima atualização sem explicação.
  it('volta para a lista quando o servidor recusa', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue({ ok: false, json: async () => ({}) }));
    montar();

    fireEvent.click(screen.getByLabelText('parar de acompanhar PDS-1075'));
    await waitFor(() => expect(screen.getByRole('alert')).toHaveTextContent(/Falha ao remover/));
    expect(screen.getByText('PDS-1075')).toBeInTheDocument();
  });

  it('recarrega o painel depois de remover', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue({ ok: true, json: async () => ({}) }));
    const onChanged = vi.fn();
    montar(onChanged);

    fireEvent.click(screen.getByLabelText('parar de acompanhar PDS-1075'));
    await waitFor(() => expect(onChanged).toHaveBeenCalled());
  });
});

describe('hierarquia expansível', () => {
  const arvore: JiraItem[] = [
    issue({ key: 'TT-100', summary: 'Iniciativa', project: 'TT', parent: null }),
    issue({ key: 'TT-101', summary: 'Épico', project: 'TT', parent: { key: 'TT-100', summary: 'Iniciativa' } }),
    issue({ key: 'TT-102', summary: 'História', project: 'TT', parent: { key: 'TT-101', summary: 'Épico' } }),
    issue({ key: 'TT-200', summary: 'Solta', project: 'TT', parent: null }),
  ];

  function montar() {
    render(
      <Panel
        jira={{ data: arvore, error: null }}
        watched={{ data: [], error: null }}
        onChanged={() => {}}
      />,
    );
  }

  it('começa fechada, mostrando só o topo', () => {
    montar();
    expect(screen.getByText('TT-100')).toBeInTheDocument();
    expect(screen.getByText('TT-200')).toBeInTheDocument();
    expect(screen.queryByText('TT-101')).toBeNull();
    expect(screen.queryByText('TT-102')).toBeNull();
  });

  it('a seta abre um nível de cada vez', () => {
    montar();
    fireEvent.click(screen.getByLabelText(/expandir a issue sob TT-100/));
    expect(screen.getByText('TT-101')).toBeInTheDocument();
    // O neto continua escondido: abrir a iniciativa não abre o épico.
    expect(screen.queryByText('TT-102')).toBeNull();

    fireEvent.click(screen.getByLabelText(/expandir a issue sob TT-101/));
    expect(screen.getByText('TT-102')).toBeInTheDocument();
  });

  it('a seta fecha de volta', () => {
    montar();
    const seta = () => screen.getByLabelText(/(expandir|recolher) a issue sob TT-100/);
    fireEvent.click(seta());
    expect(screen.getByText('TT-101')).toBeInTheDocument();

    fireEvent.click(seta());
    expect(screen.queryByText('TT-101')).toBeNull();
  });

  it('anuncia o estado para quem usa leitor de tela', () => {
    montar();
    const seta = screen.getByLabelText(/expandir a issue sob TT-100/);
    expect(seta).toHaveAttribute('aria-expanded', 'false');
    fireEvent.click(seta);
    expect(screen.getByLabelText(/recolher a issue sob TT-100/)).toHaveAttribute(
      'aria-expanded',
      'true',
    );
  });

  // Uma seta que não revela nada é um controle que engana.
  it('a issue sem filha não ganha seta', () => {
    montar();
    expect(screen.queryByLabelText(/sob TT-200/)).toBeNull();
  });

  it('diz quantas issues estão sob a que tem mais de uma', () => {
    render(
      <Panel
        jira={{
          data: [
            issue({ key: 'TT-100', summary: 'Épico', project: 'TT', parent: null }),
            issue({ key: 'TT-101', project: 'TT', parent: { key: 'TT-100', summary: 'Épico' } }),
            issue({ key: 'TT-102', project: 'TT', parent: { key: 'TT-100', summary: 'Épico' } }),
          ],
          error: null,
        }}
        watched={{ data: [], error: null }}
        onChanged={() => {}}
      />,
    );
    expect(screen.getByLabelText('expandir as 2 issues sob TT-100')).toBeInTheDocument();
  });

  // Fora da hierarquia não há pai nem filho para revelar.
  it('a lista por situação não mostra setas', () => {
    montar();
    abrirFiltros();
    // O chip diz a visão atual; clicar troca para a lista simples.
    fireEvent.click(screen.getByRole('button', { name: 'Hierarquia' }));
    expect(screen.queryByLabelText(/expandir/)).toBeNull();
    // E ali todas as issues aparecem, porque não há o que colapsar.
    expect(screen.getByText('TT-102')).toBeInTheDocument();
  });
});

// As duas listas não são recortes uma da outra: "Em aberto" é o que ainda
// pede trabalho e "Entregues" é o que saiu hoje.
describe('aba Entregues', () => {
  const entregue = (over: Partial<JiraDatedItem> = {}) =>
    dated({ statusCategory: 'done', status: 'Resolvido', ...over });

  it('abre em "Em aberto" e não mostra as entregues', () => {
    render(
      <Panel
        jira={{ data: [issue({ key: 'TT-1' })], error: null }}
        delivered={{ data: [entregue({ key: 'TT-9' })], error: null }}
      />,
    );
    expect(screen.getByRole('tab', { name: /Em aberto/ })).toHaveAttribute('aria-selected', 'true');
    expect(screen.getByText('TT-1')).toBeInTheDocument();
    expect(screen.queryByText('TT-9')).toBeNull();
  });

  it('mostra as entregues de hoje ao trocar de aba', () => {
    render(
      <Panel
        jira={{ data: [issue({ key: 'TT-1' })], error: null }}
        delivered={{ data: [entregue({ key: 'TT-9', summary: 'Ajuste do cashback' })], error: null }}
      />,
    );
    fireEvent.click(screen.getByRole('tab', { name: /Entregues/ }));
    expect(screen.getByText('TT-9')).toBeInTheDocument();
    expect(screen.getByText('Ajuste do cashback')).toBeInTheDocument();
    expect(screen.queryByText('TT-1')).toBeNull();
  });

  it('conta as entregues no rótulo da aba', () => {
    render(
      <Panel
        delivered={{ data: [entregue({ key: 'TT-9' }), entregue({ key: 'TT-8' })], error: null }}
      />,
    );
    expect(screen.getByRole('tab', { name: 'Entregues, 2' })).toBeInTheDocument();
  });

  // O status é o que diz de relance que aquilo saiu; verde é a cor de
  // "não pede mais nada de você".
  it('marca o status da entregue como concluída', () => {
    render(<Panel delivered={{ data: [entregue({ key: 'TT-9' })], error: null }} />);
    fireEvent.click(screen.getByRole('tab', { name: /Entregues/ }));
    expect(screen.getByText('Resolvido', { ignore: NA_LISTA })).toHaveClass('jira-status-done');
  });

  // Mesma estrutura da outra aba: DAD e PDS não se misturam só porque
  // saíram no mesmo dia.
  it('separa os projetos em blocos e aninha a hierarquia', () => {
    render(
      <Panel
        delivered={{
          data: [
            entregue({ key: 'DAD-1', project: 'DAD', summary: 'Épico mãe' }),
            entregue({
              key: 'DAD-2',
              project: 'DAD',
              summary: 'História filha',
              parent: { key: 'DAD-1', summary: 'Épico mãe' },
            }),
            entregue({ key: 'PDS-1', project: 'PDS', summary: 'Chamado' }),
          ],
          error: null,
        }}
      />,
    );
    fireEvent.click(screen.getByRole('tab', { name: /Entregues/ }));

    expect(screen.getByRole('heading', { name: /DAD/ })).toBeInTheDocument();
    expect(screen.getByRole('heading', { name: /PDS/ })).toBeInTheDocument();

    // O ramo começa fechado, como na aba de abertas.
    expect(screen.queryByText('DAD-2')).toBeNull();
    fireEvent.click(screen.getByLabelText(/expandir a issue sob DAD-1/));
    expect(screen.getByText('DAD-2')).toBeInTheDocument();
  });

  it('diz quando não houve entrega hoje', () => {
    render(<Panel jira={{ data: [issue({})], error: null }} />);
    fireEvent.click(screen.getByRole('tab', { name: /Entregues/ }));
    expect(screen.getByText('Nenhuma issue entregue hoje.')).toBeInTheDocument();
  });

  it('mostra o erro da busca de entregues sem derrubar a aba', () => {
    render(<Panel delivered={{ data: null, error: 'jira recusou o token' }} />);
    fireEvent.click(screen.getByRole('tab', { name: /Entregues/ }));
    expect(screen.getByRole('alert').textContent).toContain('jira recusou o token');
  });
});

describe('aguardando a minha aprovação', () => {
  it('marca com APROV a issue que espera pela sua decisão', () => {
    render(
      <Panel
        jira={{ data: [issue({ key: 'PDS-2138', awaitingApproval: true })], error: null }}
      />,
    );

    expect(screen.getByText('APROV')).toBeInTheDocument();
  });

  it('não marca as demais issues', () => {
    render(<Panel jira={{ data: [issue({ key: 'A-1' })], error: null }} />);

    expect(screen.queryByText('APROV')).not.toBeInTheDocument();
  });

  // Aprovar não é ser responsável nem relator, então o filtro por papel não
  // pode esconder o que espera por você: some o resto, ela fica.
  it('continua visível quando o filtro por papel está ativo', () => {
    render(
      <Panel
        jira={{
          data: [
            issue({ key: 'A-1', role: 'assignee' }),
            issue({ key: 'PDS-2138', role: 'assignee', awaitingApproval: true }),
          ],
          error: null,
        }}
      />,
    );

    abrirFiltros();
    fireEvent.click(screen.getByRole('button', { name: /relator/i }));

    expect(screen.getByText('PDS-2138')).toBeInTheDocument();
    expect(screen.queryByText('A-1')).not.toBeInTheDocument();
  });
});

describe('tab Aprovados', () => {
  it('lista o que você aprovou', () => {
    render(
      <Panel approved={{ data: [dated({ key: 'PDS-2147', summary: 'Runbook' })], error: null }} />,
    );

    fireEvent.click(screen.getByRole('tab', { name: /aprovados/i }));

    expect(screen.getByText('PDS-2147')).toBeInTheDocument();
  });

  it('avisa quando não há nada aprovado no período', () => {
    render(<Panel approved={{ data: [], error: null }} />);

    fireEvent.click(screen.getByRole('tab', { name: /aprovados/i }));

    expect(screen.getByText(/nenhuma issue aprovada/i)).toBeInTheDocument();
  });

  it('mostra o erro do Jira sem derrubar a tab', () => {
    render(<Panel approved={{ data: null, error: 'Jira recusou o token' }} />);

    fireEvent.click(screen.getByRole('tab', { name: /aprovados/i }));

    expect(screen.getByText('Jira recusou o token')).toBeInTheDocument();
  });
});

describe('período de entregues e aprovados', () => {
  const listas = {
    delivered: {
      data: [dated({ key: 'A-HOJE' }), dated({ key: 'A-SEMANA', today: false })],
      error: null,
    },
    approved: {
      data: [dated({ key: 'B-HOJE' }), dated({ key: 'B-SEMANA', today: false })],
      error: null,
    },
  };

  it('começa em hoje, escondendo o resto da semana', () => {
    render(<Panel {...listas} />);

    fireEvent.click(screen.getByRole('tab', { name: /entregues/i }));

    expect(screen.getByText('A-HOJE')).toBeInTheDocument();
    expect(screen.queryByText('A-SEMANA')).not.toBeInTheDocument();
  });

  it('mostra a semana inteira ao trocar o período', () => {
    render(<Panel {...listas} />);

    fireEvent.click(screen.getByRole('tab', { name: /entregues/i }));
    fireEvent.click(screen.getByRole('button', { name: /7 dias/i }));

    expect(screen.getByText('A-HOJE')).toBeInTheDocument();
    expect(screen.getByText('A-SEMANA')).toBeInTheDocument();
  });

  // O período é um só: trocar numa tab e achar o recorte antigo na outra faria
  // as duas listas responderem a perguntas diferentes ao mesmo tempo.
  it('vale para as duas tabs', () => {
    render(<Panel {...listas} />);

    fireEvent.click(screen.getByRole('tab', { name: /entregues/i }));
    fireEvent.click(screen.getByRole('button', { name: /7 dias/i }));
    fireEvent.click(screen.getByRole('tab', { name: /aprovados/i }));

    expect(screen.getByText('B-SEMANA')).toBeInTheDocument();
  });

  it('o contador da tab acompanha o período', () => {
    render(<Panel {...listas} />);

    expect(screen.getByRole('tab', { name: /entregues, 1/i })).toBeInTheDocument();

    fireEvent.click(screen.getByRole('tab', { name: /entregues/i }));
    fireEvent.click(screen.getByRole('button', { name: /7 dias/i }));

    expect(screen.getByRole('tab', { name: /entregues, 2/i })).toBeInTheDocument();
  });
});

describe('aba Problemas', () => {
  const problema = (over: Partial<JiraProblemItem> = {}): JiraProblemItem => ({
    ...issue({ key: 'DAD-7', summary: 'Checkout novo', statusCategory: 'done', status: 'Resolvido' }),
    problems: ['story-done-without-start', 'story-without-epic'],
    ...over,
  });

  it('lista cada issue com todos os seus problemas e o link para o Jira', () => {
    render(<Panel problems={{ data: [problema()], error: null }} />);
    fireEvent.click(screen.getByRole('tab', { name: /Problemas/ }));

    expect(screen.getByRole('link', { name: 'DAD-7' })).toHaveAttribute('href', 'https://example/A-1');
    const lista = screen.getByRole('list', { name: 'problemas de DAD-7' });
    expect(within(lista).getAllByRole('listitem').map((li) => li.textContent)).toEqual([
      'concluída sem data de início',
      'sem épico',
    ]);
  });

  it('conta as issues com problema no rótulo da aba', () => {
    render(
      <Panel problems={{ data: [problema(), problema({ key: 'DAD-8' })], error: null }} />,
    );
    expect(screen.getByRole('tab', { name: 'Problemas, 2' })).toBeInTheDocument();
  });

  it('mostra o erro do Jira sem derrubar a aba', () => {
    render(<Panel problems={{ data: [], error: 'campo "Start date" não encontrado no Jira' }} />);
    fireEvent.click(screen.getByRole('tab', { name: /Problemas/ }));
    expect(screen.getByText(/Start date/)).toBeInTheDocument();
  });

  it('diz quando não há problema', () => {
    render(<Panel />);
    fireEvent.click(screen.getByRole('tab', { name: /Problemas/ }));
    expect(screen.getByText('Nenhuma história ou épico com problema.')).toBeInTheDocument();
  });

  it('não mostra o período, que é das listas fechadas', () => {
    render(<Panel problems={{ data: [problema()], error: null }} />);
    fireEvent.click(screen.getByRole('tab', { name: /Problemas/ }));
    expect(screen.queryByRole('button', { name: /7 dias/i })).toBeNull();
  });
});

describe('aba na URL', () => {
  it('grava a aba escolhida na URL', () => {
    render(<Panel />);
    fireEvent.click(screen.getByRole('tab', { name: /Problemas/ }));
    expect(nav.history).toEqual(['/?jira=problemas']);
  });

  it('abre na aba que veio na URL', () => {
    nav.search = 'jira=entregues';
    render(<Panel />);
    expect(screen.getByRole('tab', { name: /Entregues/ })).toHaveAttribute('aria-selected', 'true');
  });

  it('tira da URL a aba padrão e mantém os outros parâmetros', () => {
    nav.search = 'x=1&jira=problemas';
    render(<Panel />);
    fireEvent.click(screen.getByRole('tab', { name: /Em aberto/ }));
    expect(nav.history).toEqual(['/?x=1']);
  });

  it('cai na aba padrão quando a URL traz uma aba que não existe', () => {
    nav.search = 'jira=<script>';
    render(<Panel />);
    expect(screen.getByRole('tab', { name: /Em aberto/ })).toHaveAttribute('aria-selected', 'true');
  });
});

import { useJiraPersonView } from '@/lib/hooks/useJiraPersonView';

describe('Visão de Pessoa (pessoaAtiva)', () => {
  const people = [{ accountId: '123:abc', displayName: 'Ana Souza' }];

  beforeEach(() => {
    (useJiraPersonView as any).mockReturnValue({
      view: {
        jira: { data: [issue({ key: 'ANA-1', summary: 'Da Ana' })], error: null },
        delivered: { data: [], error: null },
        approved: { data: [], error: null },
        problems: { data: [], error: null },
        ancestors: [],
      },
      loading: false,
      error: null
    });
  });

  /** The person switcher is the panel title; Radix opens it on pointer down. */
  const abrirPessoas = (titulo: string | RegExp) => {
    fireEvent.pointerDown(screen.getByRole('button', { name: titulo }), {
      button: 0,
      ctrlKey: false,
      pointerType: 'mouse',
    });
    return screen.findByRole('menu');
  };

  it('starts on your own Jira and lists the followed people in the title menu', async () => {
    render(<Panel people={people} />);
    const menu = await abrirPessoas('Jira · Eu');
    expect(within(menu).getByRole('menuitemradio', { name: 'Eu' })).toHaveAttribute('aria-checked', 'true');
    expect(within(menu).getByRole('menuitemradio', { name: 'Ana Souza' })).toBeInTheDocument();
  });

  it('switching person from the title menu writes it to the URL', async () => {
    render(<Panel people={people} />);
    const menu = await abrirPessoas('Jira · Eu');
    fireEvent.click(within(menu).getByRole('menuitemradio', { name: 'Ana Souza' }));
    expect(nav.history.at(-1)).toBe('/?jiraPessoa=123%3Aabc');
  });

  it('takes no row of its own above the lists', () => {
    render(<Panel people={people} />);
    expect(screen.queryByRole('tablist', { name: 'de quem é o Jira' })).not.toBeInTheDocument();
  });

  it('opens the person search from the title menu', async () => {
    render(<Panel people={people} />);
    const menu = await abrirPessoas('Jira · Eu');
    fireEvent.click(within(menu).getByRole('menuitem', { name: 'Acompanhar pessoa' }));
    expect(await screen.findByLabelText('buscar pessoa no Jira')).toBeInTheDocument();
  });

  it('puts the focus in the person search, not back on the title', async () => {
    render(<Panel people={people} />);
    const menu = await abrirPessoas('Jira · Eu');
    fireEvent.click(within(menu).getByRole('menuitem', { name: 'Acompanhar pessoa' }));
    const campo = await screen.findByRole('textbox', { name: 'buscar pessoa no Jira' });
    await waitFor(() => expect(campo).toHaveFocus());
  });

  it('closes the person search from its own button', async () => {
    render(<Panel people={people} />);
    const menu = await abrirPessoas('Jira · Eu');
    fireEvent.click(within(menu).getByRole('menuitem', { name: 'Acompanhar pessoa' }));
    await screen.findByRole('textbox', { name: 'buscar pessoa no Jira' });
    fireEvent.click(screen.getByRole('button', { name: 'fechar busca de pessoa' }));
    expect(screen.queryByRole('textbox', { name: 'buscar pessoa no Jira' })).not.toBeInTheDocument();
  });

  it('offers to stop following only on a followed person', async () => {
    const { unmount } = render(<Panel people={people} />);
    const proprio = await abrirPessoas('Jira · Eu');
    expect(within(proprio).queryByRole('menuitem', { name: /Parar de acompanhar/ })).not.toBeInTheDocument();
    unmount();

    nav.search = 'jiraPessoa=123:abc';
    render(<Panel people={people} />);
    const seguido = await abrirPessoas('Jira · Ana Souza');
    expect(within(seguido).getByRole('menuitem', { name: 'Parar de acompanhar Ana Souza' })).toBeInTheDocument();
  });

  it('stops following the person on screen and goes back to your own Jira', async () => {
    nav.search = 'jiraPessoa=123:abc';
    const fetchMock = vi.fn().mockResolvedValue(new Response('{}', { status: 200 }));
    vi.stubGlobal('fetch', fetchMock);
    render(<Panel people={people} />);
    const menu = await abrirPessoas('Jira · Ana Souza');
    fireEvent.click(within(menu).getByRole('menuitem', { name: 'Parar de acompanhar Ana Souza' }));
    await waitFor(() => expect(nav.search).toBe(''));
    expect(fetchMock).toHaveBeenCalledWith(
      '/api/jira/people',
      expect.objectContaining({ method: 'DELETE', body: JSON.stringify({ accountId: '123:abc' }) }),
    );
  });

  it('usa a view da pessoa e não a do usuário local quando selecionada', () => {
    nav.search = 'jiraPessoa=123:abc';
    render(<Panel people={people} jira={{ data: [issue({ key: 'LOCAL-1' })], error: null }} />);
    
    expect(screen.getByText('ANA-1')).toBeInTheDocument();
    expect(screen.queryByText('LOCAL-1')).not.toBeInTheDocument();
    
    // Eyebrow alterado
    expect(screen.getByText('Jira · Ana Souza')).toBeInTheDocument();
  });

  it('esconde "Acompanhando" quando em visão de terceiro', () => {
    nav.search = 'jiraPessoa=123:abc';
    render(<Panel people={people} watched={{ data: [issue({ key: 'WATCH-1' })], error: null }} />);
    expect(screen.queryByText('WATCH-1')).not.toBeInTheDocument();
  });

  it('não oferece o resumo da daily na visão de terceiro', () => {
    nav.search = 'jiraPessoa=123:abc';
    render(<Panel people={people} />);
    expect(screen.queryByRole('button', { name: 'Resumo para a daily' })).not.toBeInTheDocument();
  });
});

describe('filtros do Jira', () => {
  // Uma iniciativa com um épico e duas histórias, e outra iniciativa com uma
  // história. Os níveis são os que a API desta instância devolve.
  const iniFidelidade = issue({ key: 'TT-10', summary: 'Programa de fidelidade', kind: 'Iniciativa', hierarchyLevel: 2 });
  const iniPagamentos = issue({ key: 'TT-20', summary: 'Pagamentos', kind: 'Iniciativa', hierarchyLevel: 2 });
  const epicPontos = issue({
    key: 'TT-11',
    summary: 'Pontos por aposta',
    kind: 'Epic',
    hierarchyLevel: 1,
    parent: { key: 'TT-10', summary: 'Programa de fidelidade' },
  });
  const epicPix = issue({
    key: 'TT-21',
    summary: 'Pix',
    kind: 'Epic',
    hierarchyLevel: 1,
    parent: { key: 'TT-20', summary: 'Pagamentos' },
  });
  const saldo = issue({
    key: 'TT-111',
    summary: 'Tela de saldo',
    hierarchyLevel: 0,
    status: 'Em Andamento',
    parent: { key: 'TT-11', summary: 'Pontos por aposta' },
  });
  const extrato = issue({
    key: 'TT-112',
    summary: 'API de extrato',
    hierarchyLevel: 0,
    status: 'Backlog',
    parent: { key: 'TT-11', summary: 'Pontos por aposta' },
  });
  const qr = issue({
    key: 'TT-211',
    summary: 'QR code',
    hierarchyLevel: 0,
    status: 'Em Andamento',
    parent: { key: 'TT-21', summary: 'Pix' },
  });

  function montar(props: Partial<ComponentProps<typeof JiraPanel>> = {}) {
    render(
      <Panel
        jira={{ data: [saldo, extrato, qr, epicPix], error: null }}
        ancestors={[epicPontos, iniFidelidade, iniPagamentos]}
        {...props}
      />,
    );
  }

  const escolher = (rotulo: string, valor: string) =>
    fireEvent.change(screen.getByLabelText(rotulo), { target: { value: valor } });

  const naTela = (chave: string) => screen.queryByRole('link', { name: chave }) !== null;
  const minhasNaTela = () =>
    ['TT-111', 'TT-112', 'TT-211', 'TT-21'].filter((chave) => naTela(chave));
  const params = () => new URLSearchParams(nav.search);
  const opcoesDe = (rotulo: string) =>
    within(screen.getByLabelText(rotulo))
      .getAllByRole('option')
      .map((o) => (o as HTMLOptionElement).value)
      .filter(Boolean);

  it('filtra por status e grava na URL', () => {
    montar();
    abrirFiltros();
    escolher('filtrar por status', 'Backlog');

    expect(params().get('jiraStatus')).toBe('Backlog');
    expect(minhasNaTela()).toEqual(['TT-112']);
  });

  it('permite alternar múltiplos status e alternar modo no dropdown interativo', () => {
    montar();
    abrirFiltros();
    fireEvent.click(screen.getByRole('button', { name: /abrir menu filtrar por status/i }));
    fireEvent.click(screen.getByRole('checkbox', { name: 'Backlog' }));
    expect(params().get('jiraStatus')).toBe('Backlog');

    fireEvent.click(screen.getByRole('checkbox', { name: 'Aberto' }));
    expect(params().get('jiraStatus')).toBe('Backlog,Aberto');

    fireEvent.click(screen.getByRole('button', { name: /modo não é igual a para filtrar por status/i }));
    expect(params().get('jiraStatusModo')).toBe('exclude');
  });

  it('remove um valor de uma seleção múltipla e mostra a dimensão com a contagem', () => {
    montar();
    abrirFiltros();
    fireEvent.click(screen.getByRole('button', { name: /abrir menu filtrar por status/i }));
    fireEvent.click(screen.getByRole('checkbox', { name: 'Backlog' }));
    fireEvent.click(screen.getByRole('checkbox', { name: 'Aberto' }));

    const gatilho = screen.getByRole('button', { name: /abrir menu filtrar por status/i });
    expect(gatilho).toHaveTextContent('Status (2)');
    expect(gatilho).toHaveAccessibleName('abrir menu filtrar por status, incluindo Status (2)');

    fireEvent.click(screen.getByRole('checkbox', { name: 'Backlog' }));
    expect(params().get('jiraStatus')).toBe('Aberto');
  });

  it('fecha o menu de filtro com Escape e devolve o foco ao gatilho', async () => {
    montar();
    abrirFiltros();
    const gatilho = screen.getByRole('button', { name: /abrir menu filtrar por status/i });
    gatilho.focus();
    fireEvent.click(gatilho);
    const marcar = screen.getByRole('checkbox', { name: 'Backlog' });

    fireEvent.keyDown(marcar, { key: 'Escape' });

    await waitFor(() =>
      expect(screen.queryByRole('checkbox', { name: 'Backlog' })).not.toBeInTheDocument(),
    );
    expect(gatilho).toHaveFocus();
  });

  it('deixa o trio da hierarquia quebrar linha em telas estreitas', () => {
    montar();
    abrirFiltros();
    expect(screen.getByRole('group', { name: 'hierarquia do Jira' })).toHaveClass('flex-wrap', 'max-w-full');
  });

  it('oferece só os status que existem na lista', () => {
    montar();
    abrirFiltros();
    expect(opcoesDe('filtrar por status')).toEqual(['Aberto', 'Backlog', 'Em Andamento']);
  });

  it('filtra pelo tipo, mantendo o caminho até o topo', () => {
    montar();
    abrirFiltros();
    escolher('filtrar por tipo', 'epic');

    expect(params().get('jiraTipo')).toBe('epic');
    expect(minhasNaTela()).toEqual(['TT-21']);
    // A iniciativa acima do épico continua desenhada, como caminho.
    expect(naTela('TT-20')).toBe(true);
  });

  it('escolher uma iniciativa mostra só o que está debaixo dela', () => {
    montar();
    abrirFiltros();
    escolher('filtrar por iniciativa', 'TT-10');

    expect(params().get('jiraIniciativa')).toBe('TT-10');
    expect(minhasNaTela()).toEqual(['TT-111', 'TT-112']);
  });

  it('os épicos e histórias oferecidos descem em cascata da iniciativa', () => {
    montar();
    abrirFiltros();
    expect(opcoesDe('filtrar por épico')).toEqual(['TT-21', 'TT-11']);

    escolher('filtrar por iniciativa', 'TT-10');
    expect(opcoesDe('filtrar por épico')).toEqual(['TT-11']);
    expect(opcoesDe('filtrar por história')).toEqual(['TT-112', 'TT-111']);
  });

  it('trocar a iniciativa solta o épico e a história escolhidos antes', () => {
    nav.search = 'jiraIniciativa=TT-10&jiraEpico=TT-11&jiraHistoria=TT-111';
    montar();
    abrirFiltros();
    escolher('filtrar por iniciativa', 'TT-20');

    expect(params().get('jiraIniciativa')).toBe('TT-20');
    expect(params().has('jiraEpico')).toBe(false);
    expect(params().has('jiraHistoria')).toBe(false);
    expect(minhasNaTela()).toEqual(['TT-211', 'TT-21']);
  });

  it('escolher uma história mostra só ela', () => {
    montar();
    abrirFiltros();
    escolher('filtrar por história', 'TT-112');
    expect(minhasNaTela()).toEqual(['TT-112']);
  });

  it('a busca acha pelo título da iniciativa', () => {
    montar();
    fireEvent.change(screen.getByLabelText('buscar issues'), { target: { value: 'fidelidade' } });

    expect(params().get('jiraBusca')).toBe('fidelidade');
    expect(minhasNaTela()).toEqual(['TT-111', 'TT-112']);
  });

  it('abre já filtrado quando o link traz os filtros', () => {
    nav.search = 'jiraStatus=Em+Andamento&jiraTipo=story';
    montar();
    // TT-21 continua na tela como caminho da TT-211; a TT-112 (Backlog) sai.
    expect(minhasNaTela()).toEqual(['TT-111', 'TT-211', 'TT-21']);
    expect(naTela('TT-112')).toBe(false);
  });

  it('mostra cada filtro ativo e limpa tudo de uma vez, sem mexer na aba', () => {
    nav.search = 'jira=abertas&jiraStatus=Backlog&jiraIniciativa=TT-10';
    montar();
    expect(screen.getByText('Status: Backlog')).toBeInTheDocument();
    expect(screen.getByText('Iniciativa: TT-10 Programa de fidelidade')).toBeInTheDocument();

    fireEvent.click(screen.getByRole('button', { name: /limpar/i }));

    expect(params().has('jiraStatus')).toBe(false);
    expect(params().has('jiraIniciativa')).toBe(false);
    expect(params().get('jira')).toBe('abertas');
    // De volta ao padrão: o épico que é seu nasce fechado, com a história dentro.
    expect(minhasNaTela()).toEqual(['TT-111', 'TT-112', 'TT-21']);
  });

  it('os mesmos filtros valem na aba Entregues', () => {
    nav.search = 'jira=entregues&jiraIniciativa=TT-20';
    montar({
      jira: { data: [], error: null },
      ancestors: [epicPontos, epicPix, iniFidelidade, iniPagamentos],
      delivered: {
        data: [
          { ...saldo, today: true },
          { ...qr, today: true },
        ],
        error: null,
      },
    });
    expect(naTela('TT-211')).toBe(true);
    expect(naTela('TT-111')).toBe(false);
  });

  // O servidor não busca como ancestral o que já está numa lista: o épico que
  // é seu em aberto não vem em `ancestors`. A árvore da aba Entregues precisa
  // achá-lo mesmo assim para desenhar o caminho da história entregue.
  it('usa o épico que está em aberto como caminho da história entregue', () => {
    nav.search = 'jira=entregues';
    montar({
      jira: { data: [epicPix], error: null },
      ancestors: [iniPagamentos],
      delivered: { data: [{ ...qr, today: true }], error: null },
    });
    const linhas = screen.getAllByRole('listitem').map((li) => li.textContent?.match(/TT-\d+/)?.[0]);
    expect(linhas).toEqual(['TT-20', 'TT-21', 'TT-211']);
  });

  it('diz que nada casa com os filtros, em vez de dizer que nada foi entregue', () => {
    nav.search = 'jira=entregues&jiraStatus=Backlog';
    montar({
      jira: { data: [], error: null },
      delivered: { data: [{ ...saldo, today: true }], error: null },
    });
    expect(screen.getByText('Nenhuma issue com esses filtros.')).toBeInTheDocument();
    expect(screen.queryByText('Nenhuma issue entregue hoje.')).toBeNull();
  });

  it('o papel também vai para a URL', () => {
    montar();
    abrirFiltros();
    fireEvent.click(screen.getByRole('button', { name: 'Relator' }));
    expect(params().get('jiraPapel')).toBe('reporter');
  });

  it('tem como padrão o papel Minhas e limpa jiraPapel ao selecioná-lo', () => {
    nav.search = 'jiraPapel=both';
    montar();
    abrirFiltros();
    fireEvent.click(screen.getByRole('button', { name: 'Minhas' }));
    expect(params().has('jiraPapel')).toBe(false);
  });

  it('conta no gatilho os filtros escondidos, sem a busca e sem o papel padrão', () => {
    nav.search = 'jiraBusca=x&jiraStatus=Backlog,Aberto&jiraIniciativa=TT-10';
    montar();
    expect(screen.getByRole('button', { name: 'Filtros, 2 ativos' })).toBeInTheDocument();
  });

  it('conta o papel quando ele sai do padrão', () => {
    montar();
    expect(screen.getByRole('button', { name: 'Filtros, nenhum ativo' })).toBeInTheDocument();
    abrirFiltros();
    fireEvent.click(screen.getByRole('button', { name: 'Relator' }));
    expect(screen.getByRole('button', { name: 'Filtros, 1 ativo' })).toBeInTheDocument();
  });

  it('organiza o painel de filtros em seções nomeadas', () => {
    montar();
    abrirFiltros();
    const painel = screen.getByRole('dialog', { name: 'filtros do Jira' });
    for (const secao of ['Papel', 'Exibição', 'Status', 'Tipo', 'Hierarquia']) {
      expect(within(painel).getByRole('region', { name: secao })).toBeInTheDocument();
    }
  });

  it('esconde papel e exibição fora de "Em aberto"', () => {
    nav.search = 'jira=entregues';
    montar();
    abrirFiltros();
    const painel = screen.getByRole('dialog', { name: 'filtros do Jira' });
    expect(within(painel).queryByRole('region', { name: 'Papel' })).toBeNull();
    expect(within(painel).queryByRole('region', { name: 'Exibição' })).toBeNull();
    expect(within(painel).getByRole('region', { name: 'Status' })).toBeInTheDocument();
  });

  it('suporta filtro composto de status na URL e exibe os itens correspondentes', () => {
    nav.search = 'jiraStatus=Backlog,Em+Andamento';
    montar();
    expect(screen.getByText('Status: Backlog, Em Andamento')).toBeInTheDocument();
    expect(minhasNaTela()).toEqual(['TT-111', 'TT-112', 'TT-211', 'TT-21']);
  });

  it('suporta filtro de exclusão de status na URL e esconde itens excluídos', () => {
    nav.search = 'jiraStatus=Backlog&jiraStatusModo=exclude';
    montar();
    expect(screen.getByText('Status ≠ Backlog')).toBeInTheDocument();
    expect(minhasNaTela()).toEqual(['TT-111', 'TT-211', 'TT-21']);
    expect(naTela('TT-112')).toBe(false);
  });

  it('suporta filtro de exclusão com prefixo ! na URL', () => {
    nav.search = 'jiraStatus=!Backlog';
    montar();
    expect(screen.getByText('Status ≠ Backlog')).toBeInTheDocument();
    expect(minhasNaTela()).toEqual(['TT-111', 'TT-211', 'TT-21']);
  });

  it('suporta exclusão de tipo na URL', () => {
    nav.search = 'jiraTipo=story&jiraTipoModo=exclude';
    montar();
    expect(screen.getByText('Tipo ≠ Histórias')).toBeInTheDocument();
    expect(minhasNaTela()).toEqual(['TT-21']);
  });

  it('suporta exclusão de iniciativa na URL', () => {
    nav.search = 'jiraIniciativa=TT-10&jiraIniciativaModo=exclude';
    montar();
    expect(screen.getByText('Iniciativa ≠ TT-10 Programa de fidelidade')).toBeInTheDocument();
    expect(minhasNaTela()).toEqual(['TT-211', 'TT-21']);
    expect(naTela('TT-111')).toBe(false);
    expect(naTela('TT-112')).toBe(false);
  });

  it('valor inventado na URL cai no padrão', () => {
    nav.search = 'jiraTipo=objetivo&jiraIniciativa=nada%20disso';
    montar();
    expect(screen.queryByText(/^Tipo:|^Iniciativa:/)).toBeNull();
    expect(minhasNaTela()).toEqual(['TT-111', 'TT-112', 'TT-21']);
  });
});

describe('prioridade e impedimento na linha', () => {
  it('mostra a bandeira de impedimento só na issue impedida', () => {
    render(
      <Panel
        jira={{
          data: [issue({ key: 'A-1', flag: 'impediment' }), issue({ key: 'A-2', flag: 'none' })],
          error: null,
        }}
      />,
    );
    const linhas = screen.getAllByRole('listitem').filter((li) => within(li).queryByText(/^A-\d$/));
    expect(within(linhas[0]).getByTitle('impedimento')).toBeInTheDocument();
    expect(within(linhas[1]).queryByTitle('impedimento')).toBeNull();
  });

  it('mostra a prioridade e pinta só as duas mais altas', () => {
    render(
      <Panel
        jira={{
          data: [
            issue({ key: 'A-1', priority: { name: 'Crítica', rank: 0 } }),
            issue({ key: 'A-2', priority: { name: 'Média', rank: 2 } }),
            issue({ key: 'A-3', priority: null }),
          ],
          error: null,
        }}
      />,
    );
    expect(screen.getByText('Crítica')).toHaveClass('text-danger');
    expect(screen.getByText('Média')).toHaveClass('text-ink-dim');
    expect(screen.getAllByTitle('prioridade')).toHaveLength(2);
  });
});

describe('ordenação', () => {
  const chavesNaTela = () =>
    screen
      .getAllByRole('link')
      .map((a) => a.textContent ?? '')
      .filter((t) => /^A-\d+$/.test(t));

  const lista = [
    issue({ key: 'A-1', updatedAt: '2026-10-15T10:00:00Z', priority: { name: 'Baixa', rank: 3 } }),
    issue({ key: 'A-2', updatedAt: '2026-10-01T10:00:00Z', priority: { name: 'Crítica', rank: 0 } }),
  ];

  /** O gatilho é um ícone; o nome diz a ordem atual. Radix abre o menu no pointer down. */
  const abrirOrdem = (atual: string) =>
    fireEvent.pointerDown(screen.getByRole('button', { name: `Ordenar: ${atual}` }), {
      button: 0,
      ctrlKey: false,
      pointerType: 'mouse',
    });
  const ordenarPor = async (atual: string, proxima: string) => {
    abrirOrdem(atual);
    fireEvent.click(await screen.findByRole('menuitemradio', { name: proxima }));
  };

  it('começa na ordem do Jira e grava a escolha na URL', async () => {
    render(<Panel jira={{ data: lista, error: null }} />);
    expect(chavesNaTela()).toEqual(['A-1', 'A-2']);

    await ordenarPor('Atualização', 'Prioridade');

    expect(new URLSearchParams(nav.search).get('jiraOrdem')).toBe('prioridade');
    expect(chavesNaTela()).toEqual(['A-2', 'A-1']);
    expect(screen.getByRole('button', { name: 'Ordenar: Prioridade' })).toBeInTheDocument();
  });

  it('marca a ordem atual no menu', async () => {
    nav.search = 'jiraOrdem=prazo';
    render(<Panel jira={{ data: lista, error: null }} />);
    abrirOrdem('Prazo');
    expect(await screen.findByRole('menuitemradio', { name: 'Prazo' })).toBeChecked();
    expect(screen.getByRole('menuitemradio', { name: 'Atualização' })).not.toBeChecked();
  });

  it('lê a ordem da URL e volta ao padrão tirando o parâmetro', async () => {
    nav.search = 'jiraOrdem=parado';
    render(<Panel jira={{ data: lista, error: null }} />);
    expect(chavesNaTela()).toEqual(['A-2', 'A-1']);

    await ordenarPor('Parado há mais tempo', 'Atualização');
    expect(nav.search).toBe('');
  });

  it('valor desconhecido na URL cai na ordem padrão', () => {
    nav.search = 'jiraOrdem=constructor';
    render(<Panel jira={{ data: lista, error: null }} />);
    expect(screen.getByRole('button', { name: 'Ordenar: Atualização' })).toBeInTheDocument();
  });
});

describe('corrigir pela aba Problemas', () => {
  const problema = (over: Partial<JiraProblemItem> = {}): JiraProblemItem => ({
    ...issue({ key: 'DAD-7', project: 'DAD', summary: 'Checkout novo' }),
    problems: ['story-in-progress-without-start'],
    ...over,
  });

  const abrir = (item: JiraProblemItem, onChanged = vi.fn()) => {
    nav.search = 'jira=problemas';
    render(<Panel problems={{ data: [item], error: null }} onChanged={onChanged} />);
    return onChanged;
  };

  const json = (status: number, body: unknown) => ({ ok: status < 400, status, json: async () => body });

  it('sugere a data, deixa conferir e só grava no Salvar', async () => {
    const fetchMock = vi.fn(async (_url: string, init?: RequestInit) =>
      init?.method === 'PUT' ? json(200, { ok: true }) : json(200, { date: '2026-10-20', basis: 'started' }),
    );
    vi.stubGlobal('fetch', fetchMock);
    const onChanged = abrir(problema());

    fireEvent.click(screen.getByRole('button', { name: 'Preencher início' }));
    const campo = await screen.findByLabelText('data de início de DAD-7');
    expect(campo).toHaveValue('2026-10-20');
    expect(screen.getByText('primeira passagem por andamento')).toBeInTheDocument();
    expect(fetchMock).toHaveBeenCalledTimes(1);

    fireEvent.change(campo, { target: { value: '2026-10-18' } });
    fireEvent.click(screen.getByRole('button', { name: 'Salvar' }));

    await screen.findByText('início gravado no Jira');
    const [url, init] = fetchMock.mock.calls[1];
    expect(url).toBe('/api/jira/issues/DAD-7/start-date');
    expect(JSON.parse(String(init?.body))).toEqual({ date: '2026-10-18' });
    expect(onChanged).toHaveBeenCalledTimes(1);
  });

  // O caso do Leo: a história foi de Backlog direto para Concluído.
  it('sem passagem por andamento, propõe o dia da conclusão e diz de onde veio', async () => {
    vi.stubGlobal('fetch', vi.fn(async () => json(200, { date: '2026-10-19', basis: 'finished' })));
    abrir(problema({ problems: ['story-done-without-start'] }));

    fireEvent.click(screen.getByRole('button', { name: 'Preencher início' }));
    expect(await screen.findByLabelText('data de início de DAD-7')).toHaveValue('2026-10-19');
    expect(screen.getByText('foi do Backlog direto para concluída: dia da conclusão')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Salvar' })).toBeEnabled();
  });

  it('criada já fora do Backlog, propõe o dia da criação', async () => {
    vi.stubGlobal('fetch', vi.fn(async () => json(200, { date: '2026-10-07', basis: 'created' })));
    abrir(problema());
    fireEvent.click(screen.getByRole('button', { name: 'Preencher início' }));
    expect(await screen.findByLabelText('data de início de DAD-7')).toHaveValue('2026-10-07');
    expect(screen.getByText('criada já fora do Backlog: dia da criação')).toBeInTheDocument();
  });

  it('sem nada no histórico, pede a data e não deixa salvar vazio', async () => {
    vi.stubGlobal('fetch', vi.fn(async () => json(200, { date: null, basis: null })));
    abrir(problema());

    fireEvent.click(screen.getByRole('button', { name: 'Preencher início' }));
    expect(await screen.findByLabelText('data de início de DAD-7')).toHaveValue('');
    expect(screen.getByText('o histórico não diz quando começou')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Salvar' })).toBeDisabled();
  });

  it('origem desconhecida na resposta não vira nota inventada', async () => {
    vi.stubGlobal('fetch', vi.fn(async () => json(200, { date: '2026-10-07', basis: 'constructor' })));
    abrir(problema());
    fireEvent.click(screen.getByRole('button', { name: 'Preencher início' }));
    expect(await screen.findByLabelText('data de início de DAD-7')).toHaveValue('2026-10-07');
    expect(screen.getByText('o histórico não diz quando começou')).toBeInTheDocument();
  });

  it('mostra o erro do Jira e mantém a data para tentar de novo', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn(async (_url: string, init?: RequestInit) =>
        init?.method === 'PUT'
          ? json(502, { error: 'o API token do Jira não tem permissão para isso' })
          : json(200, { date: '2026-10-20', basis: 'started' }),
      ),
    );
    const onChanged = abrir(problema());

    fireEvent.click(screen.getByRole('button', { name: 'Preencher início' }));
    await screen.findByLabelText('data de início de DAD-7');
    fireEvent.click(screen.getByRole('button', { name: 'Salvar' }));

    expect(await screen.findByText('o API token do Jira não tem permissão para isso')).toBeInTheDocument();
    expect(screen.getByLabelText('data de início de DAD-7')).toHaveValue('2026-10-20');
    expect(onChanged).not.toHaveBeenCalled();
  });

  it('escolhe o épico entre os abertos do projeto da história', async () => {
    const fetchMock = vi.fn(async (_url: string, init?: RequestInit) =>
      init?.method === 'PUT'
        ? json(200, { ok: true })
        : json(200, { epics: [{ key: 'DAD-1', summary: 'Pagamentos' }] }),
    );
    vi.stubGlobal('fetch', fetchMock);
    const onChanged = abrir(problema({ problems: ['story-without-epic'] }));

    fireEvent.click(screen.getByRole('button', { name: 'Escolher épico' }));
    const select = await screen.findByLabelText('épico de DAD-7');
    expect(fetchMock.mock.calls[0][0]).toBe('/api/jira/epics?project=DAD');
    expect(screen.getByRole('button', { name: 'Salvar' })).toBeDisabled();

    fireEvent.change(select, { target: { value: 'DAD-1' } });
    fireEvent.click(screen.getByRole('button', { name: 'Salvar' }));

    await screen.findByText('épico gravado no Jira');
    expect(fetchMock.mock.calls[1][0]).toBe('/api/jira/issues/DAD-7/parent');
    expect(JSON.parse(String(fetchMock.mock.calls[1][1]?.body))).toEqual({ epic: 'DAD-1' });
    expect(onChanged).toHaveBeenCalledTimes(1);
  });

  it('avisa quando o projeto não tem épico aberto', async () => {
    vi.stubGlobal('fetch', vi.fn(async () => json(200, { epics: [] })));
    abrir(problema({ problems: ['story-without-epic'] }));
    fireEvent.click(screen.getByRole('button', { name: 'Escolher épico' }));
    expect(await screen.findByText('nenhum épico aberto em DAD')).toBeInTheDocument();
  });

  it('não oferece correção para problema de épico', () => {
    abrir(problema({ problems: ['epic-without-stories'] }));
    expect(screen.queryByRole('button', { name: /Preencher início|Escolher épico/ })).toBeNull();
  });
});

describe('PRs sob a issue', () => {
  const pr = (over: Partial<PullRequestItem> = {}): PullRequestItem => ({
    repo: 'acme/app',
    number: 7,
    title: 'feat: login (A-1)',
    url: 'https://github.com/acme/app/pull/7',
    author: 'eu',
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
    updatedAt: '2026-10-20T10:00:00Z',
    jira: [{ key: 'A-1', url: 'https://acme.atlassian.net/browse/A-1', status: 'Em andamento', statusCategory: 'indeterminate' }],
    ...over,
  });

  it('mostra o PR que cita a issue, com link para o GitHub', () => {
    render(<Panel jira={{ data: [issue({ key: 'A-1' }), issue({ key: 'A-2' })], error: null }} pulls={[pr()]} />);
    const lista = screen.getByRole('list', { name: 'PRs de A-1' });
    const link = within(lista).getByRole('link');
    expect(link).toHaveAttribute('href', 'https://github.com/acme/app/pull/7');
    expect(link).toHaveTextContent('acme/app#7');
    expect(link).toHaveTextContent('feat: login (A-1)');
    expect(screen.queryByRole('list', { name: 'PRs de A-2' })).toBeNull();
  });

  it('o PR que está nas duas listas aparece uma vez', () => {
    render(<Panel jira={{ data: [issue({ key: 'A-1' })], error: null }} pulls={[pr(), pr({ awaitingYou: true })]} />);
    expect(within(screen.getByRole('list', { name: 'PRs de A-1' })).getAllByRole('link')).toHaveLength(1);
  });

  it('também aparece na aba Problemas', () => {
    nav.search = 'jira=problemas';
    render(
      <Panel
        problems={{ data: [{ ...issue({ key: 'A-1' }), problems: ['story-without-epic'] }], error: null }}
        pulls={[pr()]}
      />,
    );
    expect(screen.getByRole('list', { name: 'PRs de A-1' })).toBeInTheDocument();
  });

  it('sem PRs o painel não muda', () => {
    render(<Panel jira={{ data: [issue({ key: 'A-1' })], error: null }} />);
    expect(screen.queryByRole('list', { name: /^PRs de/ })).toBeNull();
  });

  it('monta o resumo da daily com as suas issues e os seus PRs', () => {
    render(
      <Panel
        jira={{ data: [issue({ key: 'A-1', summary: 'Andando', statusCategory: 'indeterminate' })], error: null }}
        myPulls={[pr({ repo: 'acme/api', number: 3, title: 'Travado', ci: 'failing' })]}
      />,
    );
    fireEvent.click(screen.getByRole('button', { name: 'Resumo para a daily' }));

    const texto = (screen.getByRole('textbox', { name: 'texto do resumo' }) as HTMLTextAreaElement).value;
    expect(texto).toContain('Hoje\n- A-1 — Andando');
    expect(texto).toContain('Bloqueios\n- acme/api#3 — Travado (CI falhou)');
  });
});
