import { describe, expect, it, vi, afterEach, beforeAll } from 'vitest';
import { useState, type ComponentProps } from 'react';
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
    paper: null,
    pin: null,
    ...over,
  };
}

// The actions menu hands the focus back to its trigger, an IconAction, and
// that opens its tooltip, which Radix measures with ResizeObserver. jsdom has
// none.
beforeAll(() => {
  vi.stubGlobal(
    'ResizeObserver',
    class {
      observe() {}
      unobserve() {}
      disconnect() {}
    },
  );
});

afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
});

// Radix opens its menus on pointerdown, not click.
async function openActions(title: string) {
  fireEvent.pointerDown(screen.getByRole('button', { name: `ações de ${title}` }), {
    button: 0,
    ctrlKey: false,
    pointerType: 'mouse',
  });
  return screen.findByRole('menu');
}

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
    const { rerender } = render(<TasksPanel view="list" {...props} />);
    expect(screen.queryByLabelText('agendar foco para Planejar entrega')).not.toBeInTheDocument();
    rerender(
      <FocusBlockProvider calendars={[{ id: 'c', label: 'Google', account: 'a@b.com', canWrite: true }]} onCreated={() => {}}>
        <TasksPanel view="list" {...props} />
      </FocusBlockProvider>,
    );
    expect(screen.getByLabelText('agendar foco para Planejar entrega')).toBeInTheDocument();
  });

  it('lista as tarefas agrupadas por faixa de prazo', () => {
    render(
      <TasksPanel
        view="list"
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
        view="list"
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
        view="list"
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
    render(<TasksPanel view="list" onCompletedChanged={() => {}} onRemoved={() => {}} onSubtaskChanged={() => {}} tasks={{ data: [task({})], error: null }} onChanged={onChanged} />);
    fireEvent.click(screen.getByLabelText('concluir Tarefa'));
    await waitFor(() =>
      expect(fetchSpy).toHaveBeenCalledWith(
        '/api/tasks/1',
        expect.objectContaining({ method: 'PATCH' }),
      ),
    );
    await waitFor(() => expect(onChanged).toHaveBeenCalled());
  });

  it('apagar pede confirmação e só apaga depois do sim', async () => {
    const fetchSpy = vi.spyOn(global, 'fetch').mockResolvedValue(new Response('{}', { status: 200 }));
    const onRemoved = vi.fn();
    render(<TasksPanel view="list" onCompletedChanged={() => {}} onRemoved={onRemoved} onSubtaskChanged={() => {}} tasks={{ data: [task({})], error: null }} onChanged={() => {}} />);

    fireEvent.click(within(await openActions('Tarefa')).getByRole('menuitem', { name: 'Apagar' }));
    const dialog = await screen.findByRole('dialog', { name: 'Apagar a tarefa?' });
    expect(fetchSpy).not.toHaveBeenCalled();
    expect(onRemoved).not.toHaveBeenCalled();

    fireEvent.click(within(dialog).getByRole('button', { name: 'Apagar' }));
    await waitFor(() =>
      expect(fetchSpy).toHaveBeenCalledWith('/api/tasks/1', expect.objectContaining({ method: 'DELETE' })),
    );
    expect(onRemoved).toHaveBeenCalledWith('1');
  });

  it('cancelar a confirmação não apaga', async () => {
    const fetchSpy = vi.spyOn(global, 'fetch').mockResolvedValue(new Response('{}', { status: 200 }));
    render(<TasksPanel view="list" onCompletedChanged={() => {}} onRemoved={() => {}} onSubtaskChanged={() => {}} tasks={{ data: [task({})], error: null }} onChanged={() => {}} />);

    fireEvent.click(within(await openActions('Tarefa')).getByRole('menuitem', { name: 'Apagar' }));
    const dialog = await screen.findByRole('dialog', { name: 'Apagar a tarefa?' });
    fireEvent.click(within(dialog).getByRole('button', { name: 'Cancelar' }));
    await waitFor(() => expect(screen.queryByRole('dialog')).not.toBeInTheDocument());
    expect(fetchSpy).not.toHaveBeenCalled();
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
        view="list"
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
        view="list"
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
        view="list"
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
        view="list"
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

  // The always-visible red "Apagar" and the 18px "+" read as "new task" and
  // sat right next to the title; both live in the row's menu now.
  it('apagar e adicionar subtarefa ficam no menu da linha, não soltos nela', () => {
    render(<TasksPanel view="list" onCompletedChanged={() => {}} onRemoved={() => {}} onSubtaskChanged={() => {}} tasks={{ data: [task({})], error: null }} onChanged={() => {}} />);
    expect(screen.queryByRole('button', { name: 'apagar Tarefa' })).toBeNull();
    expect(screen.queryByRole('button', { name: 'adicionar subtarefa em Tarefa' })).toBeNull();
    expect(screen.getByRole('button', { name: 'ações de Tarefa' })).toBeInTheDocument();
  });

  it('o campo de subtarefa só aparece depois de pedir pelo menu', async () => {
    render(<TasksPanel view="list" onCompletedChanged={() => {}} onRemoved={() => {}} onSubtaskChanged={() => {}} tasks={{ data: [task({})], error: null }} onChanged={() => {}} />);
    expect(screen.queryByLabelText('nova subtarefa de Tarefa')).toBeNull();
    fireEvent.click(within(await openActions('Tarefa')).getByRole('menuitem', { name: 'Adicionar subtarefa' }));
    expect(await screen.findByLabelText('nova subtarefa de Tarefa')).toBeInTheDocument();
  });

  it('adiciona uma subtarefa pela API certa', async () => {
    const fetchSpy = vi.spyOn(global, 'fetch').mockResolvedValue(new Response('{}'));
    render(<TasksPanel view="list" onCompletedChanged={() => {}} onRemoved={() => {}} onSubtaskChanged={() => {}} tasks={{ data: [task({})], error: null }} onChanged={() => {}} />);
    fireEvent.click(within(await openActions('Tarefa')).getByRole('menuitem', { name: 'Adicionar subtarefa' }));
    fireEvent.change(await screen.findByLabelText('nova subtarefa de Tarefa'), {
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
        view="list"
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
        view="list"
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
        view="list"
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
        view="list"
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
    render(<TasksPanel view="list" onCompletedChanged={() => {}} onRemoved={() => {}} onSubtaskChanged={() => {}} tasks={{ data: [task({})], error: null }} onChanged={() => {}} />);
    expect(screen.queryByRole('button', { name: /subtarefas de Tarefa/ })).toBeNull();
  });

  // Quem pede para adicionar quer ver o campo — e o que já existe ali junto.
  it('adicionar subtarefa abre o campo e revela as subtarefas existentes', async () => {
    render(
      <TasksPanel
        view="list"
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
    fireEvent.click(within(await openActions('Tarefa')).getByRole('menuitem', { name: 'Adicionar subtarefa' }));
    expect(await screen.findByLabelText('nova subtarefa de Tarefa')).toBeInTheDocument();
    expect(screen.getByText('Etapa')).toBeInTheDocument();
  });

  // "Fazendo" is a board column; without the tag, a task someone is working
  // on looks in the list exactly like one nobody started.
  it('marca na lista a tarefa que está em Fazendo', () => {
    render(
      <TasksPanel
        view="list"
        onCompletedChanged={() => {}}
        onRemoved={() => {}}
        onSubtaskChanged={() => {}}
        tasks={{ data: [task({ id: '1', title: 'Revisar PR', doing: true }), task({ id: '2', title: 'Comum' })], error: null }}
        onChanged={() => {}}
      />,
    );
    expect(screen.getAllByText('Fazendo')).toHaveLength(1);
  });

  it('pelo menu da linha, move a tarefa para Fazendo pelo mesmo caminho do quadro', async () => {
    const fetchSpy = vi.spyOn(global, 'fetch').mockImplementation(async () => new Response('{}'));
    const onDoingChanged = vi.fn();
    render(
      <TasksPanel
        view="list"
        onCompletedChanged={() => {}}
        onRemoved={() => {}}
        onSubtaskChanged={() => {}}
        onDoingChanged={onDoingChanged}
        tasks={{ data: [task({ title: 'Escrever proposta' })], error: null }}
        onChanged={() => {}}
      />,
    );
    const menu = await openActions('Escrever proposta');
    expect(within(menu).getByRole('menuitemradio', { name: 'A fazer' })).toHaveAttribute('aria-checked', 'true');
    fireEvent.click(within(menu).getByRole('menuitemradio', { name: 'Fazendo' }));
    expect(onDoingChanged).toHaveBeenCalledWith('1', true);
    await waitFor(() =>
      expect(fetchSpy).toHaveBeenCalledWith(
        '/api/tasks/1/board',
        expect.objectContaining({ method: 'PATCH', body: JSON.stringify({ status: 'doing' }) }),
      ),
    );
  });

  it('diz que a tarefa está atrasada com glifo e texto, não só com cor', () => {
    render(
      <TasksPanel
        view="list"
        onCompletedChanged={() => {}}
        onRemoved={() => {}}
        onSubtaskChanged={() => {}}
        tasks={{ data: [task({ title: 'Pagar fatura', due: '2020-01-10' })], error: null }}
        onChanged={() => {}}
      />,
    );
    expect(screen.getByText('atrasada, prazo', { exact: false })).toBeInTheDocument();
    expect(screen.getByText('▲')).toBeInTheDocument();
  });

  it('o menu só oferece agendar foco quando há agenda Google e a tarefa está aberta', async () => {
    render(
      <FocusBlockProvider calendars={[{ id: 'c', label: 'Google', account: 'a@b.com', canWrite: true }]} onCreated={() => {}}>
        <TasksPanel
          view="list"
          onCompletedChanged={() => {}}
          onRemoved={() => {}}
          onSubtaskChanged={() => {}}
          tasks={{ data: [task({ id: '1', title: 'Aberta' }), task({ id: '2', title: 'Feita', completed: true })], error: null }}
          onChanged={() => {}}
        />
      </FocusBlockProvider>,
    );
    expect(within(await openActions('Aberta')).getByRole('menuitem', { name: 'Agendar foco' })).toBeInTheDocument();
  });

  it('o estado vazio da lista oferece criar a primeira tarefa', () => {
    render(<TasksPanel view="list" onCompletedChanged={() => {}} onRemoved={() => {}} onSubtaskChanged={() => {}} tasks={{ data: [], error: null }} onChanged={() => {}} />);
    // The header's "+" carries the same name; the empty state's is the second.
    const [, fromEmptyState] = screen.getAllByRole('button', { name: 'Nova tarefa' });
    fireEvent.click(fromEmptyState);
    expect(screen.getByRole('dialog')).toBeInTheDocument();
  });

  it('mostra o estado vazio quando não há tarefas', () => {
    render(<TasksPanel view="list" onCompletedChanged={() => {}} onRemoved={() => {}} onSubtaskChanged={() => {}} tasks={{ data: [], error: null }} onChanged={() => {}} />);
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

  it('o quadro é a visualização padrão', () => {
    render(
      <TasksPanel
        onCompletedChanged={() => {}}
        onRemoved={() => {}}
        onSubtaskChanged={() => {}}
        tasks={{ data: [task({ title: 'Escrever proposta' })], error: null }}
        onChanged={() => {}}
      />,
    );
    expect(screen.getByRole('button', { name: 'Quadro' })).toHaveAttribute('aria-pressed', 'true');
    expect(column('A fazer')).toBeInTheDocument();
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

  // The board used to have no columns at all with zero tasks, which left no
  // way to add a note to a column.
  it('mostra as três colunas mesmo sem nenhuma tarefa', () => {
    renderBoard({ tasks: { data: [], error: null } });
    expect(column('A fazer')).toHaveTextContent('Arraste uma nota para cá ou adicione');
    expect(column('Fazendo')).toBeInTheDocument();
    expect(column('Feito')).toBeInTheDocument();
  });

  it('adicionar em Fazendo cria a tarefa já em Fazendo, numa só requisição, e deixa o campo aberto', async () => {
    const fetchSpy = okFetch();
    const props = renderBoard();

    fireEvent.click(within(column('Fazendo')).getByRole('button', { name: 'adicionar tarefa em Fazendo' }));
    const field = screen.getByRole('textbox', { name: 'nova tarefa em Fazendo' });
    expect(field).toHaveFocus();
    fireEvent.change(field, { target: { value: 'Testar deploy' } });
    fireEvent.keyDown(field, { key: 'Enter' });

    await waitFor(() =>
      expect(sentBodies(fetchSpy)).toEqual([['/api/tasks', { title: 'Testar deploy', status: 'doing' }]]),
    );
    await waitFor(() => expect(field).toHaveValue(''));
    expect(screen.getByRole('textbox', { name: 'nova tarefa em Fazendo' })).toHaveFocus();
    expect(props.onChanged).toHaveBeenCalled();
  });

  it('Feito não oferece adicionar: uma tarefa não nasce concluída', () => {
    renderBoard();
    expect(within(column('A fazer')).getByRole('button', { name: 'adicionar tarefa em A fazer' })).toBeInTheDocument();
    expect(within(column('Feito')).queryByRole('button', { name: /adicionar/ })).toBeNull();
  });

  it('Esc fecha o campo sem criar e devolve o foco ao botão Adicionar', async () => {
    const fetchSpy = okFetch();
    renderBoard();
    fireEvent.click(screen.getByRole('button', { name: 'adicionar tarefa em A fazer' }));
    const field = screen.getByRole('textbox', { name: 'nova tarefa em A fazer' });
    fireEvent.change(field, { target: { value: 'Rascunho' } });
    fireEvent.keyDown(field, { key: 'Escape' });

    expect(screen.queryByRole('textbox', { name: 'nova tarefa em A fazer' })).toBeNull();
    expect(screen.getByRole('button', { name: 'adicionar tarefa em A fazer' })).toHaveFocus();
    expect(fetchSpy).not.toHaveBeenCalled();
  });

  it('quando criar falha, mostra o erro e mantém o texto no campo', async () => {
    vi.spyOn(global, 'fetch').mockImplementation(
      async () => new Response(JSON.stringify({ error: 'mstodo falhou' }), { status: 502 }),
    );
    renderBoard();
    fireEvent.click(screen.getByRole('button', { name: 'adicionar tarefa em A fazer' }));
    const field = screen.getByRole('textbox', { name: 'nova tarefa em A fazer' });
    fireEvent.change(field, { target: { value: 'Comprar café' } });
    fireEvent.keyDown(field, { key: 'Enter' });

    await waitFor(() => expect(screen.getByRole('alert').textContent).toContain('mstodo falhou'));
    expect(field).toHaveValue('Comprar café');
  });

  it('a nota tem o mesmo menu da lista, com a coluna atual marcada', async () => {
    renderBoard();
    const menu = await openActions('Revisar PR');
    expect(within(menu).getByRole('menuitem', { name: 'Editar' })).toBeInTheDocument();
    expect(within(menu).getByRole('menuitem', { name: 'Adicionar subtarefa' })).toBeInTheDocument();
    expect(within(menu).getByRole('menuitemradio', { name: 'Fazendo' })).toHaveAttribute('aria-checked', 'true');
    expect(within(menu).getByRole('menuitem', { name: 'Apagar' })).toBeInTheDocument();
  });

  it('apagar uma nota pede confirmação antes', async () => {
    const fetchSpy = okFetch();
    renderBoard();
    fireEvent.click(within(await openActions('Escrever proposta')).getByRole('menuitem', { name: 'Apagar' }));
    const dialog = await screen.findByRole('dialog', { name: 'Apagar a tarefa?' });
    expect(fetchSpy).not.toHaveBeenCalled();
    fireEvent.click(within(dialog).getByRole('button', { name: 'Apagar' }));
    await waitFor(() =>
      expect(fetchSpy).toHaveBeenCalledWith('/api/tasks/1', expect.objectContaining({ method: 'DELETE' })),
    );
  });

  it('o progresso das subtarefas abre a lista delas dentro da nota', async () => {
    const fetchSpy = okFetch();
    renderBoard({
      tasks: {
        data: [task({ id: '1', title: 'Escrever proposta', subtasks: [{ id: 's1', title: 'Rascunho', completed: false }] })],
        error: null,
      },
    });
    const progress = screen.getByRole('button', { name: 'subtarefas de Escrever proposta: 0 de 1 concluídas' });
    expect(progress).toHaveAttribute('aria-expanded', 'false');
    expect(screen.queryByLabelText('concluir subtarefa Rascunho')).toBeNull();

    fireEvent.click(progress);
    expect(progress).toHaveAttribute('aria-expanded', 'true');
    fireEvent.click(screen.getByLabelText('concluir subtarefa Rascunho'));
    await waitFor(() =>
      expect(sentBodies(fetchSpy)).toEqual([['/api/tasks/1/subtasks/s1', { completed: true }]]),
    );
  });

  it('adiciona subtarefa numa nota que ainda não tem nenhuma', async () => {
    const fetchSpy = okFetch();
    renderBoard();
    fireEvent.click(within(await openActions('Escrever proposta')).getByRole('menuitem', { name: 'Adicionar subtarefa' }));
    const field = await screen.findByRole('textbox', { name: 'nova subtarefa de Escrever proposta' });
    fireEvent.change(field, { target: { value: 'Levantar números' } });
    fireEvent.keyDown(field, { key: 'Enter' });
    await waitFor(() =>
      expect(sentBodies(fetchSpy)).toEqual([['/api/tasks/1/subtasks', { title: 'Levantar números' }]]),
    );
  });

  it('a nota atrasada diz que está atrasada', () => {
    renderBoard({ tasks: { data: [task({ id: '1', title: 'Pagar fatura', due: '2020-01-10' })], error: null } });
    expect(within(column('A fazer')).getByText('atrasada, prazo', { exact: false })).toBeInTheDocument();
  });

  it('Feito mostra só as 10 primeiras notas até pedirem todas', () => {
    const done = Array.from({ length: 12 }, (_, i) =>
      task({ id: `d${i}`, title: `Feita ${i + 1}`, completed: true }),
    );
    renderBoard({ tasks: { data: done, error: null } });
    expect(within(column('Feito')).getAllByRole('listitem')).toHaveLength(10);
    // The column still counts everything, hidden or not.
    expect(column('Feito')).toHaveAccessibleName('Feito, 12 tarefas');

    fireEvent.click(screen.getByRole('button', { name: 'Mostrar todas (12)' }));
    expect(within(column('Feito')).getAllByRole('listitem')).toHaveLength(12);
  });

  it('no painel estreito, as abas dizem quantas notas há em cada coluna e escolhem qual mostrar', () => {
    renderBoard();
    const tabs = within(screen.getByRole('tablist', { name: 'Colunas do quadro' })).getAllByRole('tab');
    expect(tabs.map((t) => t.textContent)).toEqual(['A fazer1', 'Fazendo1', 'Feito1']);
    expect(tabs[0]).toHaveAttribute('aria-selected', 'true');

    fireEvent.click(tabs[1]);
    expect(tabs[1]).toHaveAttribute('aria-selected', 'true');
    expect(tabs[0]).toHaveAttribute('aria-selected', 'false');

    fireEvent.keyDown(tabs[1], { key: 'ArrowRight' });
    expect(tabs[2]).toHaveAttribute('aria-selected', 'true');
    expect(tabs[2]).toHaveFocus();
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

describe('foco ao mover uma nota', () => {
  // The page applies the optimistic move to its state; this stands in for it,
  // so the note really is drawn again in its new column, as in the app.
  function Board() {
    const [tasks, setTasks] = useState<TodoTask[]>([
      task({ id: '1', title: 'Escrever proposta' }),
      task({ id: '2', title: 'Revisar PR', doing: true }),
    ]);
    const update = (id: string, change: Partial<TodoTask>) =>
      setTasks((all) => all.map((t) => (t.id === id ? { ...t, ...change } : t)));
    return (
      <TasksPanel
        view="board"
        tasks={{ data: tasks, error: null }}
        onChanged={() => {}}
        onRemoved={() => {}}
        onSubtaskChanged={() => {}}
        onDoingChanged={(id, doing) => update(id, { doing })}
        onCompletedChanged={(id, completed) => update(id, { completed })}
      />
    );
  }

  function column(name: string) {
    return screen.getByRole('region', { name: new RegExp(`^${name}`) });
  }

  // The note is unmounted and drawn again in the other column; the focus used
  // to fall to the page, and the person lost their place on the board.
  it('pelo botão, o foco vai para o título da nota na coluna nova', async () => {
    vi.spyOn(global, 'fetch').mockImplementation(async () => new Response('{}'));
    render(<Board />);
    fireEvent.click(screen.getByRole('button', { name: 'mover Escrever proposta para Fazendo' }));

    const title = within(column('Fazendo')).getByRole('button', { name: 'Escrever proposta' });
    await waitFor(() => expect(title).toHaveFocus());
  });

  it('pelo menu, o foco também vai para o título da nota na coluna nova', async () => {
    vi.spyOn(global, 'fetch').mockImplementation(async () => new Response('{}'));
    render(<Board />);
    const menu = await openActions('Revisar PR');
    fireEvent.click(within(menu).getByRole('menuitemradio', { name: 'Feito' }));

    const title = await within(column('Feito')).findByRole('button', { name: 'Revisar PR' });
    await waitFor(() => expect(title).toHaveFocus());
  });
});

describe('cor da nota', () => {
  // Stands in for the page, which applies the optimistic change to its state,
  // so the note and the picker really redraw with the new colour.
  function Panel({ view = 'board', onChanged = () => {} }: { view?: 'board' | 'list'; onChanged?: () => void }) {
    const [tasks, setTasks] = useState<TodoTask[]>([
      task({ id: '1', title: 'Escrever proposta' }),
      task({ id: '2', title: 'Revisar PR', priority: 'high', paper: 'grey' }),
    ]);
    return (
      <TasksPanel
        view={view}
        tasks={{ data: tasks, error: null }}
        onChanged={onChanged}
        onRemoved={() => {}}
        onSubtaskChanged={() => {}}
        onCompletedChanged={() => {}}
        onStyleChanged={(id, patch) =>
          setTasks((all) => all.map((t) => (t.id === id ? { ...t, ...patch } : t)))
        }
      />
    );
  }

  async function openColours(title: string) {
    const menu = await openActions(title);
    fireEvent.click(within(menu).getByRole('menuitem', { name: 'Cor da nota…' }));
    return screen.findByRole('dialog', { name: `cor da nota de ${title}` });
  }

  function paperOf(title: string) {
    return screen.getByRole('button', { name: title }).closest('.postit')?.getAttribute('data-paper');
  }

  it('o menu abre a escolha de cor, com Automático marcado quando nada foi escolhido', async () => {
    render(<Panel />);
    const dialog = await openColours('Escrever proposta');
    const paper = within(dialog).getByRole('radiogroup', { name: 'Papel' });
    const pin = within(dialog).getByRole('radiogroup', { name: 'Alfinete' });
    expect(within(paper).getByRole('radio', { name: 'Papel automático (amarelo)' })).toHaveAttribute('aria-checked', 'true');
    expect(within(paper).getAllByRole('radio')).toHaveLength(7);
    expect(within(pin).getByRole('radio', { name: 'Alfinete automático' })).toHaveAttribute('aria-checked', 'true');
    expect(within(pin).getAllByRole('radio')).toHaveLength(5);
  });

  it('escolher um papel muda a nota na hora, grava pela rota do quadro e anuncia', async () => {
    const fetchSpy = vi.spyOn(global, 'fetch').mockImplementation(
      async () => new Response(JSON.stringify({ ok: true, paper: 'pink', pin: null })),
    );
    render(<Panel />);
    const dialog = await openColours('Escrever proposta');
    fireEvent.click(within(dialog).getByRole('radio', { name: 'Papel rosa' }));

    expect(within(dialog).getByRole('radio', { name: 'Papel rosa' })).toHaveAttribute('aria-checked', 'true');
    expect(paperOf('Escrever proposta')).toBe('pink');
    expect(fetchSpy).toHaveBeenCalledWith(
      '/api/tasks/1/board',
      expect.objectContaining({ method: 'PATCH', body: JSON.stringify({ paper: 'pink' }) }),
    );
    await waitFor(() =>
      expect(screen.getByRole('status')).toHaveTextContent('Papel rosa em Escrever proposta.'),
    );
  });

  it('quando gravar falha, a cor volta, o erro aparece e o painel recarrega', async () => {
    vi.spyOn(global, 'fetch').mockImplementation(
      async () => new Response(JSON.stringify({ error: 'banco travado' }), { status: 502 }),
    );
    const onChanged = vi.fn();
    render(<Panel onChanged={onChanged} />);
    const dialog = await openColours('Revisar PR');
    fireEvent.click(within(dialog).getByRole('radio', { name: 'Papel branco' }));
    expect(paperOf('Revisar PR')).toBe('white');

    await waitFor(() => expect(screen.getByRole('alert')).toHaveTextContent('banco travado'));
    expect(paperOf('Revisar PR')).toBe('grey');
    expect(within(dialog).getByRole('radio', { name: 'Papel cinza' })).toHaveAttribute('aria-checked', 'true');
    expect(screen.getByRole('status')).toHaveTextContent('Não foi possível mudar a cor de Revisar PR');
    expect(onChanged).toHaveBeenCalled();
  });

  it('avisa qual alfinete pode sumir no papel da nota, sem impedir a escolha', async () => {
    const fetchSpy = vi.spyOn(global, 'fetch').mockImplementation(async () => new Response('{}'));
    render(<Panel />);
    const dialog = await openColours('Revisar PR');
    // Papel cinza: o amarelo quase não se destaca dele.
    const yellow = within(dialog).getByRole('radio', { name: 'Alfinete amarelo, pode sumir neste papel' });
    fireEvent.click(yellow);
    expect(yellow).toHaveAttribute('aria-checked', 'true');
    expect(within(dialog).getByText('O alfinete amarelo pode sumir neste papel.')).toBeInTheDocument();
    expect(fetchSpy).toHaveBeenCalledWith('/api/tasks/2/board', expect.objectContaining({ body: JSON.stringify({ pin: 'yellow' }) }));
  });

  it('pelas setas, o grupo anda entre as cores e escolhe a que recebe o foco', async () => {
    vi.spyOn(global, 'fetch').mockImplementation(async () => new Response('{}'));
    render(<Panel />);
    const dialog = await openColours('Escrever proposta');
    const automatic = within(dialog).getByRole('radio', { name: 'Papel automático (amarelo)' });
    expect(automatic).toHaveAttribute('tabindex', '0');
    fireEvent.keyDown(automatic, { key: 'ArrowRight' });
    const yellow = within(dialog).getByRole('radio', { name: 'Papel amarelo' });
    expect(yellow).toHaveAttribute('aria-checked', 'true');
    expect(yellow).toHaveFocus();
  });

  it('Automático devolve a nota à cor da prioridade', async () => {
    const fetchSpy = vi.spyOn(global, 'fetch').mockImplementation(async () => new Response('{}'));
    render(<Panel />);
    const dialog = await openColours('Revisar PR');
    fireEvent.click(within(dialog).getByRole('radio', { name: 'Papel automático (rosa)' }));
    expect(paperOf('Revisar PR')).toBe('pink');
    expect(fetchSpy).toHaveBeenCalledWith('/api/tasks/2/board', expect.objectContaining({ body: JSON.stringify({ paper: null }) }));
  });

  // Paridade: o que o quadro mostra, a lista também mostra.
  it('na lista, a cor escolhida aparece ao lado do título e o menu também a oferece', async () => {
    render(<Panel view="list" />);
    expect(screen.getByRole('img', { name: 'nota cinza' })).toBeInTheDocument();
    expect(screen.queryByRole('img', { name: /^nota amarelo/ })).not.toBeInTheDocument();
    const dialog = await openColours('Escrever proposta');
    expect(within(dialog).getByRole('radiogroup', { name: 'Papel' })).toBeInTheDocument();
  });

  // O tachado é de quem terminou, não de quem tem papel verde.
  it('o tachado segue a conclusão, não a cor do papel', () => {
    render(
      <TasksPanel
        view="board"
        tasks={{
          data: [
            task({ id: '1', title: 'Aberta verde', paper: 'green' }),
            task({ id: '2', title: 'Feita rosa', completed: true, paper: 'pink' }),
          ],
          error: null,
        }}
        onChanged={() => {}}
        onRemoved={() => {}}
        onSubtaskChanged={() => {}}
        onCompletedChanged={() => {}}
      />,
    );
    const open = screen.getByRole('button', { name: 'Aberta verde' }).closest('.postit');
    const done = screen.getByRole('button', { name: 'Feita rosa' }).closest('.postit');
    expect(open).toHaveAttribute('data-paper', 'green');
    expect(open).not.toHaveAttribute('data-done');
    expect(done).toHaveAttribute('data-paper', 'pink');
    expect(done).toHaveAttribute('data-done');
  });
});
