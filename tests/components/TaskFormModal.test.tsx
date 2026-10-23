import { describe, expect, it, vi, afterEach } from 'vitest';
import { useState } from 'react';
import { render, screen, cleanup, fireEvent, waitFor, within } from '@testing-library/react';
import { TaskFormModal } from '@/components/TaskFormModal';
import type { TodoTask } from '@/lib/types';

afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
  vi.useRealTimers();
});

const tarefa = (overrides: Partial<TodoTask> = {}): TodoTask => ({
  id: 'T1',
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
  ...overrides,
});

function renderModal(task: TodoTask | null = null, handlers: Partial<{ onClose: () => void; onSaved: (styleError?: string) => void; onDeleted: (id: string) => void }> = {}) {
  return render(
    <TaskFormModal
      task={task}
      onClose={handlers.onClose ?? (() => {})}
      onSaved={handlers.onSaved ?? (() => {})}
      onDeleted={handlers.onDeleted ?? (() => {})}
    />,
  );
}

function sentBody(fetchSpy: { mock: { calls: unknown[][] } }, call = 0): Record<string, unknown> {
  const init = fetchSpy.mock.calls[call][1] as RequestInit;
  return JSON.parse(String(init.body));
}

const okResponse = () => vi.spyOn(global, 'fetch').mockImplementation(async () => new Response('{}', { status: 200 }));

describe('TaskFormModal', () => {
  it('is a dialog named by its title', () => {
    renderModal();
    expect(screen.getByRole('dialog', { name: 'Nova tarefa' })).toBeInTheDocument();
  });

  it('cria uma tarefa nova ao salvar com título preenchido', async () => {
    const fetchSpy = okResponse();
    const onSaved = vi.fn();
    renderModal(null, { onSaved });
    fireEvent.change(screen.getByLabelText('Título'), { target: { value: 'Nova tarefa' } });
    fireEvent.click(screen.getByRole('button', { name: 'Salvar' }));
    await waitFor(() => expect(onSaved).toHaveBeenCalled());
    expect(fetchSpy).toHaveBeenCalledWith('/api/tasks', expect.objectContaining({ method: 'POST' }));
  });

  it('saves when Enter is pressed in the title field', async () => {
    const fetchSpy = okResponse();
    const onSaved = vi.fn();
    renderModal(null, { onSaved });
    const titulo = screen.getByLabelText('Título');
    fireEvent.change(titulo, { target: { value: 'Ligar para o banco' } });
    fireEvent.submit(titulo.closest('form')!);
    await waitFor(() => expect(onSaved).toHaveBeenCalled());
    expect(sentBody(fetchSpy).title).toBe('Ligar para o banco');
  });

  // The button used to be disabled with an empty title, so the reason never
  // showed: the person just saw a dead button.
  it('keeps Save enabled and reports an empty title on the field itself', () => {
    const fetchSpy = vi.spyOn(global, 'fetch');
    renderModal();
    const salvar = screen.getByRole('button', { name: 'Salvar' });
    expect(salvar).not.toBeDisabled();
    fireEvent.click(salvar);

    const titulo = screen.getByLabelText('Título');
    expect(fetchSpy).not.toHaveBeenCalled();
    expect(titulo).toHaveAttribute('aria-invalid', 'true');
    expect(titulo).toHaveAccessibleDescription('Dê um título à tarefa.');
    expect(titulo).toHaveFocus();

    fireEvent.change(titulo, { target: { value: 'x' } });
    expect(titulo).not.toHaveAttribute('aria-invalid');
  });

  it('limits the title to 255 characters', () => {
    renderModal();
    expect(screen.getByLabelText('Título')).toHaveAttribute('maxLength', '255');
  });

  it('mostra o erro devolvido pela API sem fechar o formulário', async () => {
    vi.spyOn(global, 'fetch').mockResolvedValue(
      new Response(JSON.stringify({ error: 'mstodo caiu' }), { status: 502 }),
    );
    const onSaved = vi.fn();
    renderModal(tarefa(), { onSaved });
    fireEvent.click(screen.getByRole('button', { name: 'Salvar' }));
    await waitFor(() => expect(screen.getByRole('alert').textContent).toContain('mstodo caiu'));
    expect(onSaved).not.toHaveBeenCalled();
  });

  it('sends the priority picked in the select', async () => {
    const fetchSpy = okResponse();
    renderModal();
    fireEvent.change(screen.getByLabelText('Título'), { target: { value: 'x' } });
    const prioridade = screen.getByRole('combobox', { name: 'Prioridade' });
    expect(within(prioridade).getAllByRole('option').map((o) => o.textContent)).toEqual(['Alta', 'Normal', 'Baixa']);
    fireEvent.change(prioridade, { target: { value: 'low' } });
    fireEvent.click(screen.getByRole('button', { name: 'Salvar' }));
    await waitFor(() => expect(fetchSpy).toHaveBeenCalled());
    expect(sentBody(fetchSpy).priority).toBe('low');
  });

  it('fecha com a tecla Escape quando nada mudou', () => {
    const onClose = vi.fn();
    renderModal(null, { onClose });
    fireEvent.keyDown(screen.getByRole('dialog'), { key: 'Escape' });
    expect(onClose).toHaveBeenCalled();
  });
});

// The modal has no DialogTrigger, so Radix had nowhere to send focus back and
// it fell to <body>: a keyboard user lost their place in the list.
it('returns focus to the button that opened it', async () => {
  function Opener() {
    const [open, setOpen] = useState(false);
    return (
      <>
        <button type="button" onClick={() => setOpen(true)}>Nova tarefa</button>
        {open && <TaskFormModal task={null} onClose={() => setOpen(false)} onSaved={() => {}} onDeleted={() => {}} />}
      </>
    );
  }
  render(<Opener />);
  const abrir = screen.getByRole('button', { name: 'Nova tarefa' });
  abrir.focus();
  fireEvent.click(abrir);
  await waitFor(() => expect(screen.getByLabelText('Título')).toHaveFocus());
  fireEvent.keyDown(screen.getByRole('dialog'), { key: 'Escape' });
  await waitFor(() => expect(abrir).toHaveFocus());
});

describe('recurrence', () => {
  // The local store writes 'monthly'; only Microsoft To Do's
  // 'absoluteMonthly' was recognised, so editing a local monthly task opened
  // it as "Não repete" and saving wiped the recurrence.
  it('keeps a local monthly recurrence when editing', async () => {
    const fetchSpy = okResponse();
    renderModal(tarefa({ due: '2026-11-05', recur: 'monthly' }));
    expect(screen.getByRole('combobox', { name: 'Repetição' })).toHaveValue('monthly');
    fireEvent.click(screen.getByRole('button', { name: 'Salvar' }));
    await waitFor(() => expect(fetchSpy).toHaveBeenCalled());
    expect(sentBody(fetchSpy).recur).toBe('monthly');
  });

  it('reads the Microsoft To Do monthly recurrence too', () => {
    renderModal(tarefa({ due: '2026-11-05', recur: 'absoluteMonthly' }));
    expect(screen.getByRole('combobox', { name: 'Repetição' })).toHaveValue('monthly');
  });

  // A recurring task without a date is completed for good instead of coming
  // back, so the form does not offer that combination.
  it('is disabled with a hint while there is no date', () => {
    renderModal();
    const repeticao = screen.getByRole('combobox', { name: 'Repetição' });
    expect(repeticao).toBeDisabled();
    expect(repeticao).toHaveAccessibleDescription('Defina uma data para repetir.');

    fireEvent.change(screen.getByLabelText('Dia'), { target: { value: '2026-11-05' } });
    expect(repeticao).not.toBeDisabled();
  });

  it('drops the recurrence when the date is cleared', async () => {
    const fetchSpy = okResponse();
    renderModal(tarefa({ due: '2026-11-05', recur: 'weekly' }));
    fireEvent.click(screen.getByRole('button', { name: 'Sem data' }));
    fireEvent.click(screen.getByRole('button', { name: 'Salvar' }));
    await waitFor(() => expect(fetchSpy).toHaveBeenCalled());
    expect(sentBody(fetchSpy)).toMatchObject({ due: '', recur: 'none' });
  });
});

describe('date', () => {
  it('builds the due from the date and time inputs', async () => {
    const fetchSpy = okResponse();
    renderModal();
    fireEvent.change(screen.getByLabelText('Título'), { target: { value: 'x' } });
    const hora = screen.getByLabelText('Hora');
    expect(hora).toBeDisabled();
    fireEvent.change(screen.getByLabelText('Dia'), { target: { value: '2026-11-05' } });
    expect(hora).not.toBeDisabled();
    fireEvent.change(hora, { target: { value: '09:30' } });
    fireEvent.click(screen.getByRole('button', { name: 'Salvar' }));
    await waitFor(() => expect(fetchSpy).toHaveBeenCalled());
    expect(sentBody(fetchSpy).due).toBe('2026-11-05 09:30');
  });

  it('shows a stored date and time in the inputs when editing', () => {
    renderModal(tarefa({ due: '2026-10-20', time: '14:00' }));
    expect(screen.getByLabelText('Dia')).toHaveValue('2026-10-20');
    expect(screen.getByLabelText('Hora')).toHaveValue('14:00');
  });

  it('fills tomorrow from the quick chip', async () => {
    vi.useFakeTimers({ toFake: ['Date'] });
    vi.setSystemTime(new Date(2026, 9, 23, 10, 0));
    const fetchSpy = okResponse();
    renderModal();
    fireEvent.change(screen.getByLabelText('Título'), { target: { value: 'x' } });
    fireEvent.click(screen.getByRole('button', { name: 'Amanhã' }));
    expect(screen.getByRole('button', { name: 'Amanhã' })).toHaveAttribute('aria-pressed', 'true');
    fireEvent.click(screen.getByRole('button', { name: 'Salvar' }));
    await waitFor(() => expect(fetchSpy).toHaveBeenCalled());
    expect(sentBody(fetchSpy).due).toBe('2026-10-24');
  });

  it('previews typed text and applies it to the date fields', () => {
    vi.useFakeTimers({ toFake: ['Date'] });
    vi.setSystemTime(new Date(2026, 9, 23, 10, 0));
    renderModal();
    fireEvent.click(screen.getByRole('button', { name: 'Digitar data' }));
    const texto = screen.getByLabelText('Data em texto');
    fireEvent.change(texto, { target: { value: 'amanhã 09:00' } });
    expect(texto).toHaveAccessibleDescription('→ sáb, 24/10 09:00');
    expect(screen.getByLabelText('Dia')).toHaveValue('2026-10-24');
    expect(screen.getByLabelText('Hora')).toHaveValue('09:00');
  });

  // The server used to be the first to say "data inválida: sexta", with no
  // link to the field and no hint of what would work.
  it('reports unreadable typed text inline and does not submit', () => {
    const fetchSpy = vi.spyOn(global, 'fetch');
    renderModal();
    fireEvent.change(screen.getByLabelText('Título'), { target: { value: 'x' } });
    fireEvent.click(screen.getByRole('button', { name: 'Digitar data' }));
    const texto = screen.getByLabelText('Data em texto');
    fireEvent.change(texto, { target: { value: 'sexta' } });
    expect(texto).toHaveAttribute('aria-invalid', 'true');
    expect(texto).toHaveAccessibleDescription(/Não reconheci "sexta"\. Exemplos: hoje, amanhã 14:30/);

    fireEvent.click(screen.getByRole('button', { name: 'Salvar' }));
    expect(fetchSpy).not.toHaveBeenCalled();
    expect(texto).toHaveFocus();
  });
});

describe('closing with unsaved changes', () => {
  it('asks before an outside click discards what was typed', async () => {
    const onClose = vi.fn();
    renderModal(null, { onClose });
    fireEvent.change(screen.getByLabelText('Título'), { target: { value: 'Rascunho' } });
    fireEvent.keyDown(screen.getByRole('dialog', { name: 'Nova tarefa' }), { key: 'Escape' });

    const pergunta = await screen.findByRole('dialog', { name: 'Descartar as alterações?' });
    expect(onClose).not.toHaveBeenCalled();
    fireEvent.click(within(pergunta).getByRole('button', { name: /Continuar editando/ }));
    await waitFor(() => expect(screen.queryByRole('dialog', { name: 'Descartar as alterações?' })).not.toBeInTheDocument());
    expect(onClose).not.toHaveBeenCalled();
    expect(screen.getByLabelText('Título')).toHaveValue('Rascunho');
  });

  it('does not close on an outside click while there are changes', async () => {
    const onClose = vi.fn();
    renderModal(null, { onClose });
    fireEvent.change(screen.getByLabelText('Título'), { target: { value: 'Rascunho' } });
    // Radix arms its outside-pointer listener on the next tick, and settles a
    // primary-button press outside only on the click that follows it.
    await new Promise((resolve) => setTimeout(resolve, 0));
    fireEvent.pointerDown(document.body);
    fireEvent.click(document.body);

    expect(await screen.findByRole('dialog', { name: 'Descartar as alterações?' })).toBeInTheDocument();
    expect(onClose).not.toHaveBeenCalled();
  });

  it('closes once the discard is confirmed', async () => {
    const onClose = vi.fn();
    renderModal(null, { onClose });
    fireEvent.change(screen.getByLabelText('Título'), { target: { value: 'Rascunho' } });
    fireEvent.keyDown(screen.getByRole('dialog', { name: 'Nova tarefa' }), { key: 'Escape' });
    const pergunta = await screen.findByRole('dialog', { name: 'Descartar as alterações?' });
    fireEvent.click(within(pergunta).getByRole('button', { name: /Descartar/ }));
    await waitFor(() => expect(onClose).toHaveBeenCalled());
  });
});

describe('delete', () => {
  it('is offered only when editing', () => {
    renderModal();
    expect(screen.queryByRole('button', { name: 'Apagar' })).not.toBeInTheDocument();
  });

  it('asks for confirmation and does not delete when cancelled', async () => {
    const fetchSpy = vi.spyOn(global, 'fetch');
    const onDeleted = vi.fn();
    renderModal(tarefa({ title: 'Pagar boleto' }), { onDeleted });
    fireEvent.click(screen.getByRole('button', { name: 'Apagar' }));

    const pergunta = await screen.findByRole('dialog', { name: 'Apagar a tarefa?' });
    expect(pergunta).toHaveTextContent('"Pagar boleto" será removida.');
    fireEvent.click(within(pergunta).getByRole('button', { name: /Cancelar/ }));
    await waitFor(() => expect(screen.queryByRole('dialog', { name: 'Apagar a tarefa?' })).not.toBeInTheDocument());
    expect(fetchSpy).not.toHaveBeenCalled();
    expect(onDeleted).not.toHaveBeenCalled();
  });

  it('deletes through the API once confirmed', async () => {
    const fetchSpy = okResponse();
    const onDeleted = vi.fn();
    renderModal(tarefa({ id: 'AQMk+/x==' }), { onDeleted });
    fireEvent.click(screen.getByRole('button', { name: 'Apagar' }));
    const pergunta = await screen.findByRole('dialog', { name: 'Apagar a tarefa?' });
    fireEvent.click(within(pergunta).getByRole('button', { name: /Apagar/ }));

    await waitFor(() => expect(onDeleted).toHaveBeenCalledWith('AQMk+/x=='));
    expect(fetchSpy).toHaveBeenCalledWith('/api/tasks/AQMk%2B%2Fx%3D%3D', { method: 'DELETE' });
  });

  it('keeps the form open with the error when the delete fails', async () => {
    vi.spyOn(global, 'fetch').mockResolvedValue(new Response(JSON.stringify({ error: 'mstodo caiu' }), { status: 502 }));
    const onDeleted = vi.fn();
    renderModal(tarefa(), { onDeleted });
    fireEvent.click(screen.getByRole('button', { name: 'Apagar' }));
    const pergunta = await screen.findByRole('dialog', { name: 'Apagar a tarefa?' });
    fireEvent.click(within(pergunta).getByRole('button', { name: /Apagar/ }));

    await waitFor(() => expect(screen.getByRole('alert').textContent).toContain('mstodo caiu'));
    expect(onDeleted).not.toHaveBeenCalled();
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

    renderModal();
    fireEvent.change(screen.getByLabelText('Título'), { target: { value: 'Ligar para o cara' } });

    const salvar = screen.getByRole('button', { name: 'Salvar' });
    fireEvent.click(salvar);

    const salvando = await screen.findByRole('button', { name: 'Salvando…' });
    expect(salvando).toBeDisabled();

    fireEvent.submit(salvando.closest('form')!);
    expect(fetchSpy).toHaveBeenCalledTimes(1);

    resolver(new Response('{}'));
  });

  it('libera o botão de novo quando o envio falha', async () => {
    vi.spyOn(global, 'fetch').mockImplementation(
      async () => new Response(JSON.stringify({ error: 'mstodo caiu' }), { status: 502 }),
    );
    renderModal();
    fireEvent.change(screen.getByLabelText('Título'), { target: { value: 'Tarefa' } });
    fireEvent.click(screen.getByRole('button', { name: 'Salvar' }));

    await waitFor(() => expect(screen.getByRole('alert').textContent).toContain('mstodo caiu'));
    expect(screen.getByRole('button', { name: 'Salvar' })).not.toBeDisabled();
  });

  // Um id base64 do Graph tem `=` e pode ter `/`; sem codificar, o `/`
  // quebraria o caminho da rota.
  it('codifica o id na URL ao editar', async () => {
    const fetchSpy = okResponse();
    renderModal(tarefa({ id: 'AQMk+ADAw/abc==', title: 'Existente' }));
    fireEvent.click(screen.getByRole('button', { name: 'Salvar' }));

    await waitFor(() => expect(fetchSpy).toHaveBeenCalled());
    expect(String(fetchSpy.mock.calls[0][0])).toBe('/api/tasks/AQMk%2BADAw%2Fabc%3D%3D');
  });
});

describe('cor da nota no formulário', () => {
  function urls(fetchSpy: { mock: { calls: unknown[][] } }) {
    return fetchSpy.mock.calls.map(([url]) => url);
  }

  it('oferece papel e alfinete ao criar, com Automático marcado', () => {
    renderModal();
    const paper = screen.getByRole('radiogroup', { name: 'Papel' });
    expect(within(paper).getByRole('radio', { name: 'Papel automático (amarelo)' })).toHaveAttribute('aria-checked', 'true');
    expect(within(screen.getByRole('radiogroup', { name: 'Alfinete' })).getByRole('radio', { name: 'Alfinete automático' })).toHaveAttribute('aria-checked', 'true');
  });

  // O automático acompanha a prioridade escolhida no próprio formulário.
  it('o Automático diz a cor que a prioridade dará', () => {
    renderModal();
    fireEvent.change(screen.getByLabelText('Prioridade'), { target: { value: 'low' } });
    expect(screen.getByRole('radio', { name: 'Papel automático (azul)' })).toBeInTheDocument();
  });

  it('ao editar, mostra a cor já escolhida', () => {
    renderModal(tarefa({ paper: 'white', pin: 'green' }));
    expect(screen.getByRole('radio', { name: 'Papel branco' })).toHaveAttribute('aria-checked', 'true');
    expect(screen.getByRole('radio', { name: 'Alfinete verde' })).toHaveAttribute('aria-checked', 'true');
  });

  it('sem mudar a cor, salvar não chama a rota do quadro', async () => {
    const fetchSpy = okResponse();
    const onSaved = vi.fn();
    renderModal(tarefa(), { onSaved });
    fireEvent.change(screen.getByLabelText('Título'), { target: { value: 'Outro título' } });
    fireEvent.click(screen.getByRole('button', { name: 'Salvar' }));
    await waitFor(() => expect(onSaved).toHaveBeenCalledWith());
    expect(urls(fetchSpy)).toEqual(['/api/tasks/T1']);
  });

  it('ao editar, grava a cor numa segunda chamada, depois de a tarefa ser salva', async () => {
    const fetchSpy = okResponse();
    const onSaved = vi.fn();
    renderModal(tarefa({ paper: 'white' }), { onSaved });
    fireEvent.click(screen.getByRole('radio', { name: 'Papel rosa' }));
    fireEvent.click(screen.getByRole('radio', { name: 'Alfinete azul' }));
    fireEvent.click(screen.getByRole('button', { name: 'Salvar' }));
    await waitFor(() => expect(onSaved).toHaveBeenCalledWith(undefined));
    expect(urls(fetchSpy)).toEqual(['/api/tasks/T1', '/api/tasks/T1/board']);
    expect(sentBody(fetchSpy, 1)).toEqual({ paper: 'pink', pin: 'blue' });
  });

  it('ao criar, grava a cor no id que a criação devolveu', async () => {
    const fetchSpy = vi.spyOn(global, 'fetch').mockImplementation(async (url) =>
      new Response(url === '/api/tasks' ? JSON.stringify({ id: 'NOVA' }) : '{}', { status: 200 }),
    );
    const onSaved = vi.fn();
    renderModal(null, { onSaved });
    fireEvent.change(screen.getByLabelText('Título'), { target: { value: 'Comprar café' } });
    fireEvent.click(screen.getByRole('radio', { name: 'Papel verde' }));
    fireEvent.click(screen.getByRole('button', { name: 'Salvar' }));
    await waitFor(() => expect(onSaved).toHaveBeenCalled());
    expect(urls(fetchSpy)).toEqual(['/api/tasks', '/api/tasks/NOVA/board']);
    expect(sentBody(fetchSpy, 1)).toEqual({ paper: 'green', pin: null });
  });

  it('se a tarefa não for salva, a cor nem é enviada', async () => {
    const fetchSpy = vi.spyOn(global, 'fetch').mockImplementation(
      async () => new Response(JSON.stringify({ error: 'mstodo falhou' }), { status: 502 }),
    );
    renderModal(tarefa());
    fireEvent.click(screen.getByRole('radio', { name: 'Papel cinza' }));
    fireEvent.click(screen.getByRole('button', { name: 'Salvar' }));
    expect(await screen.findByRole('alert')).toHaveTextContent('mstodo falhou');
    expect(urls(fetchSpy)).toEqual(['/api/tasks/T1']);
  });

  // A tarefa já existe: ficar aberto faria o próximo "Salvar" criá-la de novo.
  it('quando só a cor falha, fecha e diz que a tarefa foi salva sem a cor', async () => {
    vi.spyOn(global, 'fetch').mockImplementation(async (url) =>
      String(url).endsWith('/board')
        ? new Response(JSON.stringify({ error: 'cor de papel inválida' }), { status: 400 })
        : new Response(JSON.stringify({ id: 'NOVA' }), { status: 200 }),
    );
    const onSaved = vi.fn();
    renderModal(null, { onSaved });
    fireEvent.change(screen.getByLabelText('Título'), { target: { value: 'Comprar café' } });
    fireEvent.click(screen.getByRole('radio', { name: 'Papel rosa' }));
    fireEvent.click(screen.getByRole('button', { name: 'Salvar' }));
    await waitFor(() => expect(onSaved).toHaveBeenCalledWith('cor de papel inválida'));
  });

  it('mudar só a cor conta como alteração antes de descartar', async () => {
    const onClose = vi.fn();
    renderModal(tarefa(), { onClose });
    fireEvent.click(screen.getByRole('radio', { name: 'Papel azul' }));
    fireEvent.keyDown(screen.getByRole('dialog', { name: 'Editar tarefa' }), { key: 'Escape' });
    expect(await screen.findByRole('dialog', { name: 'Descartar as alterações?' })).toBeInTheDocument();
    expect(onClose).not.toHaveBeenCalled();
  });
});
