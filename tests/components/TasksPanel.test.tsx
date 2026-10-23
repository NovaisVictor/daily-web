import { describe, expect, it, vi, afterEach } from 'vitest';
import type { ComponentProps } from 'react';
import { render, screen, cleanup, fireEvent, waitFor, within } from '@testing-library/react';
import { TasksPanel, formatDue } from '@/components/TasksPanel';
import type { TodoTask } from '@/lib/types';
import { FocusBlockProvider } from '@/components/FocusBlockProvider';

function task(over: Partial<TodoTask>): TodoTask {
  return {
    id: '1',
    title: 'Tarefa',
    completed: false,
    due: '',
    priority: 'normal',
    time: '',
    recur: '',
    notes: '',
    subtasks: [],
    doing: false,
    ...over,
  };
}

afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
});

describe('formatDue', () => {
  it('mostra dia/mês sem o ano', () => {
    expect(formatDue('2026-08-11', '')).toBe('11/08');
  });

  it('acrescenta a hora quando existe', () => {
    expect(formatDue('2026-08-11', '14:00')).toBe('11/08 14:00');
  });

  it('devolve o valor original quando não é uma data reconhecível', () => {
    expect(formatDue('sem data', '')).toBe('sem data');
  });
});

describe('TasksPanel', () => {
  it('mostra agendar foco só quando há agenda Google', () => {
    const props = {
      onCompletedChanged: () => {}, onRemoved: () => {}, onSubtaskChanged: () => {},
      tasks: { data: [task({ title: 'Planejar entrega' })], error: null }, onChanged: () => {},
    };
    const { rerender } = render(<TasksPanel {...props} />);
    expect(screen.queryByLabelText('agendar foco para Planejar entrega')).not.toBeInTheDocument();
    rerender(
      <FocusBlockProvider calendars={[{ id: 'c', label: 'Google', account: 'a@b.com', canWrite: true }]} onCreated={() => {}}>
        <TasksPanel {...props} />
      </FocusBlockProvider>,
    );
    expect(screen.getByLabelText('agendar foco para Planejar entrega')).toBeInTheDocument();
  });

  it('lista as tarefas agrupadas por faixa de prazo', () => {
    render(
      <TasksPanel
        onCompletedChanged={() => {}}
        onRemoved={() => {}}
        onSubtaskChanged={() => {}}
        tasks={{ data: [task({ id: '1', title: 'Tarefa solta' })], error: null }}
        onChanged={() => {}}
      />,
    );
    expect(screen.getByText('Tarefa solta')).toBeInTheDocument();
    expect(screen.getByRole('heading', { name: 'SEM DATA' })).toBeInTheDocument();
  });

  it('filtra por busca textual', () => {
    render(
      <TasksPanel
        onCompletedChanged={() => {}}
        onRemoved={() => {}}
        onSubtaskChanged={() => {}}
        tasks={{
          data: [task({ id: '1', title: 'Comprar pão' }), task({ id: '2', title: 'Revisar PR' })],
          error: null,
        }}
        onChanged={() => {}}
      />,
    );
    fireEvent.change(screen.getByLabelText('buscar tarefas'), { target: { value: 'pão' } });
    expect(screen.getByText('Comprar pão')).toBeInTheDocument();
    expect(screen.queryByText('Revisar PR')).toBeNull();
  });

  it('filtra por prioridade alta', () => {
    render(
      <TasksPanel
        onCompletedChanged={() => {}}
        onRemoved={() => {}}
        onSubtaskChanged={() => {}}
        tasks={{
          data: [
            task({ id: '1', title: 'Urgente', priority: 'high' }),
            task({ id: '2', title: 'Comum' }),
          ],
          error: null,
        }}
        onChanged={() => {}}
      />,
    );
    fireEvent.click(screen.getByRole('button', { name: 'Alta' }));
    expect(screen.getByText('Urgente')).toBeInTheDocument();
    expect(screen.queryByText('Comum')).toBeNull();
  });

  it('conclui uma tarefa e avisa onChanged', async () => {
    const fetchSpy = vi.spyOn(global, 'fetch').mockResolvedValue(new Response('{}'));
    const onChanged = vi.fn();
    render(<TasksPanel onCompletedChanged={() => {}} onRemoved={() => {}} onSubtaskChanged={() => {}} tasks={{ data: [task({})], error: null }} onChanged={onChanged} />);
    fireEvent.click(screen.getByLabelText('concluir Tarefa'));
    await waitFor(() =>
      expect(fetchSpy).toHaveBeenCalledWith(
        '/api/tasks/1',
        expect.objectContaining({ method: 'PATCH' }),
      ),
    );
    await waitFor(() => expect(onChanged).toHaveBeenCalled());
  });

  // Ao falhar, a marcação otimista precisa ser desfeita — e a fonte da
  // verdade é o servidor, então recarregar é justamente o certo a fazer.
  it('mostra o erro e recarrega para desfazer quando concluir falha', async () => {
    vi.spyOn(global, 'fetch').mockImplementation(
      async () => new Response(JSON.stringify({ error: 'mstodo falhou' }), { status: 502 }),
    );
    const onChanged = vi.fn();
    const onCompletedChanged = vi.fn();
    render(
      <TasksPanel
        onCompletedChanged={onCompletedChanged}
        onRemoved={() => {}}
        onSubtaskChanged={() => {}}
        tasks={{ data: [task({})], error: null }}
        onChanged={onChanged}
      />,
    );
    fireEvent.click(screen.getByLabelText('concluir Tarefa'));

    // A tela reage antes da resposta.
    expect(onCompletedChanged).toHaveBeenCalledWith('1', true);
    await waitFor(() => expect(screen.getByRole('alert').textContent).toContain('mstodo falhou'));
    await waitFor(() => expect(onChanged).toHaveBeenCalled());
  });

  it('conclui na tela antes de o servidor responder', () => {
    vi.spyOn(global, 'fetch').mockImplementation(() => new Promise(() => {}));
    const onCompletedChanged = vi.fn();
    render(
      <TasksPanel
        onCompletedChanged={onCompletedChanged}
        onRemoved={() => {}}
        onSubtaskChanged={() => {}}
        tasks={{ data: [task({})], error: null }}
        onChanged={() => {}}
      />,
    );
    fireEvent.click(screen.getByLabelText('concluir Tarefa'));
    expect(onCompletedChanged).toHaveBeenCalledWith('1', true);
  });

  // Recorrente não vira "feita": ela pula para a próxima data. Antecipar o
  // risco seria mostrar um estado que o servidor vai desmentir.
  it('não antecipa a conclusão de uma tarefa que repete', () => {
    vi.spyOn(global, 'fetch').mockImplementation(() => new Promise(() => {}));
    const onCompletedChanged = vi.fn();
    render(
      <TasksPanel
        onCompletedChanged={onCompletedChanged}
        onRemoved={() => {}}
        onSubtaskChanged={() => {}}
        tasks={{ data: [task({ recur: 'weekly' })], error: null }}
        onChanged={() => {}}
      />,
    );
    fireEvent.click(screen.getByLabelText('concluir Tarefa'));
    expect(onCompletedChanged).not.toHaveBeenCalled();
  });

  it('marca uma subtarefa pela API certa', async () => {
    const fetchSpy = vi.spyOn(global, 'fetch').mockResolvedValue(new Response('{}'));
    render(
      <TasksPanel
        onCompletedChanged={() => {}}
        onRemoved={() => {}}
        onSubtaskChanged={() => {}}
        tasks={{
          data: [task({ subtasks: [{ id: 's1', title: 'Etapa', completed: false }] })],
          error: null,
        }}
        onChanged={() => {}}
      />,
    );
    fireEvent.click(screen.getByRole('button', { name: 'expandir subtarefas de Tarefa' }));
    fireEvent.click(screen.getByLabelText('concluir subtarefa Etapa'));
    await waitFor(() =>
      expect(fetchSpy).toHaveBeenCalledWith(
        '/api/tasks/1/subtasks/s1',
        expect.objectContaining({ method: 'PATCH', body: JSON.stringify({ completed: true }) }),
      ),
    );
  });

  it('o campo de subtarefa só aparece depois de clicar no +', () => {
    render(<TasksPanel onCompletedChanged={() => {}} onRemoved={() => {}} onSubtaskChanged={() => {}} tasks={{ data: [task({})], error: null }} onChanged={() => {}} />);
    expect(screen.queryByLabelText('nova subtarefa de Tarefa')).toBeNull();
    fireEvent.click(screen.getByRole('button', { name: 'adicionar subtarefa em Tarefa' }));
    expect(screen.getByLabelText('nova subtarefa de Tarefa')).toBeInTheDocument();
  });

  it('adiciona uma subtarefa pela API certa', async () => {
    const fetchSpy = vi.spyOn(global, 'fetch').mockResolvedValue(new Response('{}'));
    render(<TasksPanel onCompletedChanged={() => {}} onRemoved={() => {}} onSubtaskChanged={() => {}} tasks={{ data: [task({})], error: null }} onChanged={() => {}} />);
    fireEvent.click(screen.getByRole('button', { name: 'adicionar subtarefa em Tarefa' }));
    fireEvent.change(screen.getByLabelText('nova subtarefa de Tarefa'), {
      target: { value: 'Etapa nova' },
    });
    fireEvent.click(screen.getByRole('button', { name: 'Adicionar subtarefa' }));
    await waitFor(() =>
      expect(fetchSpy).toHaveBeenCalledWith(
        '/api/tasks/1/subtasks',
        expect.objectContaining({ method: 'POST', body: JSON.stringify({ title: 'Etapa nova' }) }),
      ),
    );
  });

  it('esconde tarefas concluídas por padrão', () => {
    render(
      <TasksPanel
        onCompletedChanged={() => {}}
        onRemoved={() => {}}
        onSubtaskChanged={() => {}}
        tasks={{
          data: [
            task({ id: '1', title: 'Pendente' }),
            task({ id: '2', title: 'Já feita', completed: true }),
          ],
          error: null,
        }}
        onChanged={() => {}}
      />,
    );
    expect(screen.getByText('Pendente')).toBeInTheDocument();
    expect(screen.queryByText('Já feita')).toBeNull();
  });

  it('mostra as concluídas quando o filtro é ligado', () => {
    render(
      <TasksPanel
        onCompletedChanged={() => {}}
        onRemoved={() => {}}
        onSubtaskChanged={() => {}}
        tasks={{
          data: [
            task({ id: '1', title: 'Pendente' }),
            task({ id: '2', title: 'Já feita', completed: true }),
          ],
          error: null,
        }}
        onChanged={() => {}}
      />,
    );
    fireEvent.click(screen.getByRole('button', { name: 'Concluídas' }));
    expect(screen.getByText('Já feita')).toBeInTheDocument();
  });

  it('mantém as subtarefas escondidas até clicarem na seta', () => {
    render(
      <TasksPanel
        onCompletedChanged={() => {}}
        onRemoved={() => {}}
        onSubtaskChanged={() => {}}
        tasks={{
          data: [task({ subtasks: [{ id: 's1', title: 'Etapa', completed: false }] })],
          error: null,
        }}
        onChanged={() => {}}
      />,
    );
    expect(screen.queryByText('Etapa')).toBeNull();

    fireEvent.click(screen.getByRole('button', { name: 'expandir subtarefas de Tarefa' }));
    expect(screen.getByText('Etapa')).toBeInTheDocument();

    fireEvent.click(screen.getByRole('button', { name: 'recolher subtarefas de Tarefa' }));
    expect(screen.queryByText('Etapa')).toBeNull();
  });

  // O contador mantém a subtarefa visível como informação mesmo recolhida:
  // dá para saber que existe e quanto falta sem abrir.
  it('mostra o quanto das subtarefas já foi feito mesmo recolhido', () => {
    render(
      <TasksPanel
        onCompletedChanged={() => {}}
        onRemoved={() => {}}
        onSubtaskChanged={() => {}}
        tasks={{
          data: [
            task({
              subtasks: [
                { id: 's1', title: 'Etapa', completed: true },
                { id: 's2', title: 'Outra', completed: false },
              ],
            }),
          ],
          error: null,
        }}
        onChanged={() => {}}
      />,
    );
    expect(screen.getByTitle('subtarefas concluídas').textContent).toBe('1/2');
  });

  it('não oferece seta em tarefa sem subtarefa', () => {
    render(<TasksPanel onCompletedChanged={() => {}} onRemoved={() => {}} onSubtaskChanged={() => {}} tasks={{ data: [task({})], error: null }} onChanged={() => {}} />);
    expect(screen.queryByRole('button', { name: /subtarefas de Tarefa/ })).toBeNull();
  });

  // Quem clica no "+" quer ver o campo — e o que já existe ali junto.
  it('o + abre o campo e revela as subtarefas existentes', () => {
    render(
      <TasksPanel
        onCompletedChanged={() => {}}
        onRemoved={() => {}}
        onSubtaskChanged={() => {}}
        tasks={{
          data: [task({ subtasks: [{ id: 's1', title: 'Etapa', completed: false }] })],
          error: null,
        }}
        onChanged={() => {}}
      />,
    );
    fireEvent.click(screen.getByRole('button', { name: 'adicionar subtarefa em Tarefa' }));
    expect(screen.getByLabelText('nova subtarefa de Tarefa')).toBeInTheDocument();
    expect(screen.getByText('Etapa')).toBeInTheDocument();
  });

  it('mostra o estado vazio quando não há tarefas', () => {
    render(<TasksPanel onCompletedChanged={() => {}} onRemoved={() => {}} onSubtaskChanged={() => {}} tasks={{ data: [], error: null }} onChanged={() => {}} />);
    expect(screen.getByText(/nenhuma tarefa/i)).toBeInTheDocument();
  });
});

describe('TasksPanel em quadro', () => {
  function renderBoard(over: Partial<ComponentProps<typeof TasksPanel>> = {}) {
    const props: ComponentProps<typeof TasksPanel> = {
      onCompletedChanged: vi.fn(),
      onRemoved: () => {},
      onSubtaskChanged: () => {},
      onDoingChanged: vi.fn(),
      onChanged: vi.fn(),
      view: 'board',
      tasks: {
        data: [
          task({ id: '1', title: 'Escrever proposta' }),
          task({ id: '2', title: 'Revisar PR', doing: true }),
          task({ id: '3', title: 'Pagar boleto', completed: true }),
        ],
        error: null,
      },
      ...over,
    };
    render(<TasksPanel {...props} />);
    return props;
  }

  function column(name: string) {
    return screen.getByRole('region', { name: new RegExp(`^${name}`) });
  }

  function okFetch() {
    return vi.spyOn(global, 'fetch').mockImplementation(async () => new Response('{}'));
  }

  function sentBodies(spy: ReturnType<typeof okFetch>) {
    return spy.mock.calls.map(([url, init]) => [url, JSON.parse(String(init?.body))]);
  }

  it('a lista continua sendo a visualização padrão', () => {
    render(
      <TasksPanel
        onCompletedChanged={() => {}}
        onRemoved={() => {}}
        onSubtaskChanged={() => {}}
        tasks={{ data: [task({ title: 'Escrever proposta' })], error: null }}
        onChanged={() => {}}
      />,
    );
    expect(screen.getByRole('button', { name: 'Lista' })).toHaveAttribute('aria-pressed', 'true');
    expect(screen.queryByRole('region', { name: /^A fazer/ })).toBeNull();
  });

  it('trocar para Quadro mostra as colunas e guarda a escolha', async () => {
    const fetchSpy = okFetch();
    const onViewChanged = vi.fn();
    renderBoard({ view: 'list', onViewChanged });

    fireEvent.click(screen.getByRole('button', { name: 'Quadro' }));

    expect(screen.getByRole('button', { name: 'Quadro' })).toHaveAttribute('aria-pressed', 'true');
    expect(column('A fazer')).toBeInTheDocument();
    expect(column('Fazendo')).toBeInTheDocument();
    expect(column('Feito')).toBeInTheDocument();
    expect(onViewChanged).toHaveBeenCalledWith('board');
    await waitFor(() =>
      expect(sentBodies(fetchSpy)).toEqual([['/api/preferences', { tasksView: 'board' }]]),
    );
  });

  it('avisa quando a escolha da visualização não foi guardada, sem desfazê-la', async () => {
    vi.spyOn(global, 'fetch').mockImplementation(
      async () => new Response(JSON.stringify({ error: 'banco travado' }), { status: 500 }),
    );
    renderBoard({ view: 'list' });
    fireEvent.click(screen.getByRole('button', { name: 'Quadro' }));
    await waitFor(() => expect(screen.getByRole('alert').textContent).toContain('banco travado'));
    expect(column('Feito')).toBeInTheDocument();
  });

  it('cada tarefa aparece na coluna dela, e as colunas mostram quantas têm', () => {
    renderBoard();
    expect(within(column('A fazer')).getByRole('button', { name: 'Escrever proposta' })).toBeInTheDocument();
    expect(within(column('Fazendo')).getByRole('button', { name: 'Revisar PR' })).toBeInTheDocument();
    // Feito aparece sem precisar do filtro de concluídas, que a lista usa.
    expect(within(column('Feito')).getByRole('button', { name: 'Pagar boleto' })).toBeInTheDocument();
    expect(column('A fazer')).toHaveAccessibleName('A fazer, 1 tarefa');
  });

  it('mostra prazo, prioridade e progresso das subtarefas na nota', () => {
    renderBoard({
      tasks: {
        data: [
          task({
            id: '1',
            title: 'Escrever proposta',
            priority: 'high',
            due: '2026-10-24',
            subtasks: [
              { id: 's1', title: 'a', completed: true },
              { id: 's2', title: 'b', completed: false },
            ],
          }),
        ],
        error: null,
      },
    });
    const note = within(column('A fazer'));
    expect(note.getByText('Alta')).toBeInTheDocument();
    expect(note.getByText('24/10')).toBeInTheDocument();
    expect(note.getByText('1/2', { exact: false })).toBeInTheDocument();
  });

  it('pelo teclado, move a nota para Fazendo e anuncia a mudança', async () => {
    const fetchSpy = okFetch();
    const props = renderBoard();

    fireEvent.click(screen.getByRole('button', { name: 'mover Escrever proposta para Fazendo' }));

    expect(props.onDoingChanged).toHaveBeenCalledWith('1', true);
    await waitFor(() =>
      expect(sentBodies(fetchSpy)).toEqual([['/api/tasks/1/board', { status: 'doing' }]]),
    );
    await waitFor(() =>
      expect(screen.getByRole('status')).toHaveTextContent('Escrever proposta movida para Fazendo.'),
    );
    expect(props.onChanged).toHaveBeenCalled();
  });

  it('mover para Feito conclui a tarefa pelo mesmo caminho do checkbox', async () => {
    const fetchSpy = okFetch();
    const props = renderBoard();

    fireEvent.click(screen.getByRole('button', { name: 'mover Revisar PR para Feito' }));

    expect(props.onCompletedChanged).toHaveBeenCalledWith('2', true);
    await waitFor(() =>
      expect(sentBodies(fetchSpy)).toEqual([['/api/tasks/2', { completed: true }]]),
    );
  });

  it('tirar de Feito reabre a tarefa antes de pô-la em Fazendo', async () => {
    const fetchSpy = okFetch();
    const props = renderBoard();

    fireEvent.click(screen.getByRole('button', { name: 'mover Pagar boleto para Fazendo' }));

    expect(props.onCompletedChanged).toHaveBeenCalledWith('3', false);
    await waitFor(() =>
      expect(sentBodies(fetchSpy)).toEqual([
        ['/api/tasks/3', { completed: false }],
        ['/api/tasks/3/board', { status: 'doing' }],
      ]),
    );
  });

  it('arrastar a nota para outra coluna faz o mesmo movimento', async () => {
    const fetchSpy = okFetch();
    renderBoard();
    const store = new Map<string, string>();
    const dataTransfer = {
      setData: (type: string, value: string) => store.set(type, value),
      getData: (type: string) => store.get(type) ?? '',
      get types() {
        return [...store.keys()];
      },
      effectAllowed: 'none',
      dropEffect: 'none',
    };

    const note = within(column('A fazer')).getByRole('listitem');
    fireEvent.dragStart(note, { dataTransfer });
    fireEvent.dragOver(column('Feito'), { dataTransfer });
    fireEvent.drop(column('Feito'), { dataTransfer });

    await waitFor(() =>
      expect(sentBodies(fetchSpy)).toEqual([['/api/tasks/1', { completed: true }]]),
    );
  });

  it('quando mover falha, mostra o erro e recarrega para a nota voltar', async () => {
    vi.spyOn(global, 'fetch').mockImplementation(
      async () => new Response(JSON.stringify({ error: 'mstodo falhou' }), { status: 502 }),
    );
    const props = renderBoard();

    fireEvent.click(screen.getByRole('button', { name: 'mover Escrever proposta para Fazendo' }));

    await waitFor(() => expect(screen.getByRole('alert').textContent).toContain('mstodo falhou'));
    expect(screen.getByRole('status')).toHaveTextContent('Não foi possível mover Escrever proposta');
    expect(props.onChanged).toHaveBeenCalled();
  });
});
