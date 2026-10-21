import { describe, expect, it, afterEach, vi } from 'vitest';
import { render, screen, cleanup, fireEvent, waitFor } from '@testing-library/react';
import type { JiraItem } from '@/lib/types';
import type { IssueDialog } from '@/components/jira/IssueActions';
import { DropdownMenu, DropdownMenuContent, DropdownMenuTrigger } from '@/components/ui/dropdown-menu';
import { EditDialogs, EditMenuItems } from '@/components/jira/actions/EditActions';
import { JiraActionsProvider, type JiraViewer } from '@/components/jira/actions/context';

function issue(over: Partial<JiraItem> = {}): JiraItem {
  return {
    key: 'TT-123',
    summary: 'Resumo',
    status: 'Aberto',
    statusCategory: 'new',
    project: 'TT',
    url: 'https://example/browse/TT-123',
    parent: null,
    role: 'reporter',
    awaitingApproval: false,
    kind: 'História',
    subtask: false,
    hierarchyLevel: 0,
    priority: null,
    flag: 'none',
    updatedAt: new Date().toISOString(),
    dueDate: '2026-10-21',
    ...over,
  };
}

function reply(status: number, body: unknown) {
  return { ok: status < 400, status, json: async () => body } as Response;
}

function Menu({ item, viewer = { kind: 'self' } }: { item: JiraItem; viewer?: JiraViewer }) {
  return (
    <JiraActionsProvider value={{ viewer, onChanged: () => {} }}>
      <DropdownMenu open>
        <DropdownMenuTrigger>abrir</DropdownMenuTrigger>
        <DropdownMenuContent>
          <EditMenuItems issue={item} onOpen={() => {}} />
        </DropdownMenuContent>
      </DropdownMenu>
    </JiraActionsProvider>
  );
}

function renderDialog(open: IssueDialog, item = issue()) {
  const onChanged = vi.fn();
  const onClose = vi.fn();
  render(
    <JiraActionsProvider value={{ viewer: { kind: 'self' }, onChanged }}>
      <EditDialogs issue={item} open={open} onClose={onClose} />
    </JiraActionsProvider>,
  );
  return { onChanged, onClose };
}

function sentBody(fetchMock: ReturnType<typeof vi.fn>, call = 0) {
  const [url, init] = fetchMock.mock.calls[call];
  return { url, method: (init as RequestInit).method, body: JSON.parse(String((init as RequestInit).body)) };
}

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
});

describe('EditMenuItems', () => {
  it('offers due date, priority and assign on a story, without create story', () => {
    render(<Menu item={issue()} />);
    expect(screen.getByRole('menuitem', { name: 'Alterar prazo' })).toBeTruthy();
    expect(screen.getByRole('menuitem', { name: 'Alterar prioridade' })).toBeTruthy();
    expect(screen.getByRole('menuitem', { name: 'Atribuir a mim' })).toBeTruthy();
    expect(screen.queryByRole('menuitem', { name: 'Criar história neste épico' })).toBeNull();
  });

  it('offers create story on an epic', () => {
    render(<Menu item={issue({ kind: 'Epic', hierarchyLevel: 1 })} />);
    expect(screen.getByRole('menuitem', { name: 'Criar história neste épico' })).toBeTruthy();
  });

  it('offers assign whatever the row role says, since role does not name the assignee', () => {
    render(<Menu item={issue({ role: 'both' })} />);
    expect(screen.getByRole('menuitem', { name: 'Atribuir a mim' })).toBeTruthy();
  });

  it('offers assign on an approval-only row, whose neutral role is not the assignee', () => {
    render(<Menu item={issue({ role: 'assignee', awaitingApproval: true })} />);
    expect(screen.getByRole('menuitem', { name: 'Atribuir a mim' })).toBeTruthy();
  });

  it("keeps assign when looking at someone else's issue", () => {
    render(<Menu item={issue({ role: 'assignee' })} viewer={{ kind: 'person', name: 'Ana' }} />);
    expect(screen.getByRole('menuitem', { name: 'Atribuir a mim' })).toBeTruthy();
  });
});

describe('due date dialog', () => {
  it('shows the change and saves the new date', async () => {
    const fetchMock = vi.fn().mockResolvedValue(reply(200, { ok: true }));
    vi.stubGlobal('fetch', fetchMock);
    const { onChanged } = renderDialog('due');

    fireEvent.change(screen.getByLabelText('Novo prazo'), { target: { value: '2026-10-31' } });
    expect(screen.getByText('de 21/10/2026 para 31/10/2026')).toBeTruthy();
    fireEvent.click(screen.getByRole('button', { name: 'Salvar' }));

    await waitFor(() => expect(onChanged).toHaveBeenCalled());
    expect(sentBody(fetchMock)).toEqual({
      url: '/api/jira/issues/TT-123/fields',
      method: 'PUT',
      body: { change: 'due', dueDate: '2026-10-31' },
    });
  });

  it('removes the due date', async () => {
    const fetchMock = vi.fn().mockResolvedValue(reply(200, { ok: true }));
    vi.stubGlobal('fetch', fetchMock);
    renderDialog('due');

    fireEvent.click(screen.getByRole('button', { name: 'Remover prazo' }));
    expect(screen.getByText('de 21/10/2026 para sem prazo')).toBeTruthy();
    fireEvent.click(screen.getByRole('button', { name: 'Salvar' }));

    await waitFor(() => expect(fetchMock).toHaveBeenCalled());
    expect(sentBody(fetchMock).body).toEqual({ change: 'due', dueDate: null });
  });

  it("shows Jira's refusal and does not report a change", async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(reply(502, { error: 'Jira respondeu 400: duedate: Data inválida.' })));
    const { onChanged } = renderDialog('due');

    fireEvent.change(screen.getByLabelText('Novo prazo'), { target: { value: '2026-10-31' } });
    fireEvent.click(screen.getByRole('button', { name: 'Salvar' }));

    expect((await screen.findByRole('alert')).textContent).toContain('Jira respondeu 400: duedate: Data inválida.');
    expect(onChanged).not.toHaveBeenCalled();
  });

  it('cannot save without a change', () => {
    renderDialog('due');
    expect((screen.getByRole('button', { name: 'Salvar' }) as HTMLButtonElement).disabled).toBe(true);
  });
});

describe('priority dialog', () => {
  const options = {
    priorities: [
      { id: '1', name: 'Crítica' },
      { id: '2', name: 'Alta' },
      { id: '5', name: 'Trivial' },
    ],
    current: { id: '5', name: 'Trivial' },
  };

  it('lists priorities with the current one checked, then saves the chosen one', async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(reply(200, options))
      .mockResolvedValueOnce(reply(200, { ok: true }));
    vi.stubGlobal('fetch', fetchMock);
    const { onChanged } = renderDialog('priority');

    expect(((await screen.findByRole('radio', { name: 'Trivial' })) as HTMLInputElement).checked).toBe(true);
    expect(fetchMock.mock.calls[0][0]).toBe('/api/jira/issues/TT-123/fields?options=priority');
    fireEvent.click(screen.getByRole('radio', { name: 'Alta' }));
    expect(screen.getByText('de Trivial para Alta')).toBeTruthy();
    fireEvent.click(screen.getByRole('button', { name: 'Salvar' }));

    await waitFor(() => expect(onChanged).toHaveBeenCalled());
    expect(sentBody(fetchMock, 1).body).toEqual({ change: 'priority', priorityId: '2' });
  });

  it('shows the load error with a retry', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(reply(502, { error: 'resposta inesperada do Jira: lista de prioridades ausente' })));
    renderDialog('priority');
    expect((await screen.findByRole('alert')).textContent).toContain('lista de prioridades ausente');
    expect(screen.getByRole('button', { name: 'Tentar de novo' })).toBeTruthy();
  });
});

describe('assign dialog', () => {
  it('confirms before assigning to you', async () => {
    const fetchMock = vi.fn().mockResolvedValue(reply(200, { ok: true }));
    vi.stubGlobal('fetch', fetchMock);
    const { onChanged } = renderDialog('assign');

    expect(screen.getByText('TT-123 passa a ter você como responsável')).toBeTruthy();
    fireEvent.click(screen.getByRole('button', { name: 'Atribuir' }));

    await waitFor(() => expect(onChanged).toHaveBeenCalled());
    expect(sentBody(fetchMock).body).toEqual({ change: 'assign-self' });
  });

  it('disables the buttons while the request runs', async () => {
    let resolve: (value: Response) => void = () => {};
    vi.stubGlobal('fetch', vi.fn(() => new Promise<Response>((r) => (resolve = r))));
    renderDialog('assign');

    fireEvent.click(screen.getByRole('button', { name: 'Atribuir' }));
    const pending = await screen.findByRole('button', { name: 'Atribuindo…' });
    expect((pending as HTMLButtonElement).disabled).toBe(true);
    resolve(reply(200, { ok: true }));
  });
});

describe('create story dialog', () => {
  const epic = issue({ key: 'TT-2376', kind: 'Epic', hierarchyLevel: 1 });

  it('creates the story and links to it', async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValue(reply(200, { ok: true, key: 'TT-9999', url: 'https://example/browse/TT-9999' }));
    vi.stubGlobal('fetch', fetchMock);
    const { onChanged } = renderDialog('create-story', epic);

    expect(screen.getByText('nova história em TT dentro de TT-2376')).toBeTruthy();
    expect((screen.getByRole('button', { name: 'Criar' }) as HTMLButtonElement).disabled).toBe(true);
    fireEvent.change(screen.getByLabelText('Resumo'), { target: { value: '  Nova história ' } });
    fireEvent.change(screen.getByLabelText('Descrição (opcional)'), { target: { value: 'detalhe' } });
    fireEvent.click(screen.getByRole('button', { name: 'Criar' }));

    expect((await screen.findByRole('status')).textContent).toContain('TT-9999 criada');
    expect(screen.getByRole('link', { name: 'TT-9999' }).getAttribute('href')).toBe('https://example/browse/TT-9999');
    expect(onChanged).toHaveBeenCalled();
    expect(sentBody(fetchMock)).toEqual({
      url: '/api/jira/issues/TT-2376/stories',
      method: 'POST',
      body: { summary: 'Nova história', description: 'detalhe' },
    });
  });

  it("shows Jira's refusal near the form", async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(reply(400, { error: 'TT-2376 não é um épico' })));
    const { onChanged } = renderDialog('create-story', epic);

    fireEvent.change(screen.getByLabelText('Resumo'), { target: { value: 'Nova' } });
    fireEvent.click(screen.getByRole('button', { name: 'Criar' }));

    expect((await screen.findByRole('alert')).textContent).toContain('TT-2376 não é um épico');
    expect(onChanged).not.toHaveBeenCalled();
  });
});
