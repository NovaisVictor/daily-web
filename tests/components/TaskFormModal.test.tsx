import { describe, expect, it, vi, afterEach } from 'vitest';
import { render, screen, cleanup, fireEvent, waitFor } from '@testing-library/react';
import { TaskFormModal } from '@/components/TaskFormModal';

afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
});

describe('TaskFormModal', () => {
  // O botão fica desabilitado sem título, então o estado inválido é impedido
  // em vez de reportado depois do clique.
  it('não salva sem título', () => {
    const fetchSpy = vi.spyOn(global, 'fetch');
    render(<TaskFormModal task={null} onClose={() => {}} onSaved={() => {}} />);
    fireEvent.click(screen.getByRole('button', { name: 'Salvar' }));
    expect(fetchSpy).not.toHaveBeenCalled();
  });

  it('cria uma tarefa nova ao salvar com título preenchido', async () => {
    const fetchSpy = vi.spyOn(global, 'fetch').mockResolvedValue(new Response('{}', { status: 200 }));
    const onSaved = vi.fn();
    render(<TaskFormModal task={null} onClose={() => {}} onSaved={onSaved} />);
    fireEvent.change(screen.getByLabelText(/Título/), { target: { value: 'Nova tarefa' } });
    fireEvent.click(screen.getByText('Salvar'));
    await waitFor(() => expect(onSaved).toHaveBeenCalled());
    expect(fetchSpy).toHaveBeenCalledWith('/api/tasks', expect.objectContaining({ method: 'POST' }));
  });

  it('mostra o erro devolvido pela API sem fechar o formulário', async () => {
    vi.spyOn(global, 'fetch').mockResolvedValue(
      new Response(JSON.stringify({ error: 'data inválida: 32/13' }), { status: 400 }),
    );
    const onSaved = vi.fn();
    render(
      <TaskFormModal
        task={{ id: 'T1', title: 'Tarefa', completed: false, due: '', priority: 'normal', time: '', recur: '', notes: '', subtasks: [], doing: false }}
        onClose={() => {}}
        onSaved={onSaved}
      />,
    );
    fireEvent.click(screen.getByText('Salvar'));
    await waitFor(() => expect(screen.getByRole('alert').textContent).toContain('data inválida'));
    expect(onSaved).not.toHaveBeenCalled();
  });

  it('ciclar a prioridade avança normal -> alta -> baixa', () => {
    render(<TaskFormModal task={null} onClose={() => {}} onSaved={() => {}} />);
    fireEvent.click(screen.getByText(/prioridade: Normal/));
    expect(screen.getByText(/prioridade: Alta/)).toBeInTheDocument();
    fireEvent.click(screen.getByText(/prioridade: Alta/));
    expect(screen.getByText(/prioridade: Baixa/)).toBeInTheDocument();
  });

  it('ciclar a repetição avança pelos quatro valores em português', () => {
    render(<TaskFormModal task={null} onClose={() => {}} onSaved={() => {}} />);
    fireEvent.click(screen.getByText(/repetição: Não repete/));
    expect(screen.getByText(/repetição: Diária/)).toBeInTheDocument();
    fireEvent.click(screen.getByText(/repetição: Diária/));
    expect(screen.getByText(/repetição: Semanal/)).toBeInTheDocument();
    fireEvent.click(screen.getByText(/repetição: Semanal/));
    expect(screen.getByText(/repetição: Mensal/)).toBeInTheDocument();
  });

  it('fecha com a tecla Escape', () => {
    const onClose = vi.fn();
    render(<TaskFormModal task={null} onClose={onClose} onSaved={() => {}} />);
    fireEvent.keyDown(window, { key: 'Escape' });
    expect(onClose).toHaveBeenCalled();
  });
});

describe('proteção contra envio duplicado', () => {
  // Foi assim que uma tarefa nasceu em duplicata: o botão continuava
  // clicável enquanto o POST estava em voo.
  it('trava o botão durante o envio e não dispara duas vezes', async () => {
    let resolver: (r: Response) => void = () => {};
    const fetchSpy = vi
      .spyOn(global, 'fetch')
      .mockReturnValue(new Promise<Response>((r) => { resolver = r; }));

    render(<TaskFormModal task={null} onClose={() => {}} onSaved={() => {}} />);
    fireEvent.change(screen.getByLabelText('Título'), { target: { value: 'Ligar para o cara' } });

    const salvar = screen.getByRole('button', { name: 'Salvar' });
    fireEvent.click(salvar);

    const salvando = await screen.findByRole('button', { name: 'Salvando…' });
    expect(salvando).toBeDisabled();

    fireEvent.click(salvando);
    expect(fetchSpy).toHaveBeenCalledTimes(1);

    resolver(new Response('{}'));
  });

  it('libera o botão de novo quando o envio falha', async () => {
    vi.spyOn(global, 'fetch').mockImplementation(
      async () => new Response(JSON.stringify({ error: 'mstodo caiu' }), { status: 502 }),
    );
    render(<TaskFormModal task={null} onClose={() => {}} onSaved={() => {}} />);
    fireEvent.change(screen.getByLabelText('Título'), { target: { value: 'Tarefa' } });
    fireEvent.click(screen.getByRole('button', { name: 'Salvar' }));

    await waitFor(() => expect(screen.getByRole('alert').textContent).toContain('mstodo caiu'));
    expect(screen.getByRole('button', { name: 'Salvar' })).not.toBeDisabled();
  });

  it('mantém o botão desabilitado enquanto o título está vazio', () => {
    render(<TaskFormModal task={null} onClose={() => {}} onSaved={() => {}} />);
    expect(screen.getByRole('button', { name: 'Salvar' })).toBeDisabled();

    fireEvent.change(screen.getByLabelText('Título'), { target: { value: 'x' } });
    expect(screen.getByRole('button', { name: 'Salvar' })).not.toBeDisabled();
  });

  // Um id base64 do Graph tem `=` e pode ter `/`; sem codificar, o `/`
  // quebraria o caminho da rota.
  it('codifica o id na URL ao editar', async () => {
    const fetchSpy = vi.spyOn(global, 'fetch').mockResolvedValue(new Response('{}'));
    const tarefa = {
      id: 'AQMk+ADAw/abc==', title: 'Existente', completed: false, due: '', priority: 'normal' as const,
      time: '', recur: '', notes: '', subtasks: [], doing: false,
    };
    render(<TaskFormModal task={tarefa} onClose={() => {}} onSaved={() => {}} />);
    fireEvent.click(screen.getByRole('button', { name: 'Salvar' }));

    await waitFor(() => expect(fetchSpy).toHaveBeenCalled());
    expect(String(fetchSpy.mock.calls[0][0])).toBe('/api/tasks/AQMk%2BADAw%2Fabc%3D%3D');
  });
});
