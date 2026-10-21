import { afterEach, describe, expect, it, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import type { JiraFlag, JiraItem } from '@/lib/types';
import { FlagDialog, FlagIndicator, FlagMenuItem } from '@/components/jira/actions/FlagAction';
import { JiraActionsProvider } from '@/components/jira/actions/context';
import { DropdownMenu, DropdownMenuContent, DropdownMenuTrigger } from '@/components/ui/dropdown-menu';

function issue(flag: JiraFlag): JiraItem {
  return {
    key: 'TT-5019',
    summary: 'Uma história',
    status: 'Em Andamento',
    statusCategory: 'indeterminate',
    updatedAt: '',
    dueDate: '',
    project: 'TT',
    url: 'https://example.atlassian.net/browse/TT-5019',
    parent: null,
    role: 'assignee',
    awaitingApproval: false,
    kind: 'História',
    subtask: false,
    hierarchyLevel: 0,
    priority: null,
    flag,
  };
}

function json(status: number, body: unknown) {
  return { ok: status < 400, status, json: async () => body };
}

function stubServer(response: unknown = json(200, { ok: true })) {
  const fetchMock = vi.fn(async () => response);
  vi.stubGlobal('fetch', fetchMock);
  return fetchMock;
}

const sentBody = (fetchMock: ReturnType<typeof stubServer>) => {
  const [url, init] = fetchMock.mock.calls[0] as unknown as [string, RequestInit];
  return { url, method: init.method, body: JSON.parse(String(init.body)) };
};

function withActions(ui: React.ReactNode, onChanged = vi.fn()) {
  render(<JiraActionsProvider value={{ viewer: { kind: 'self' }, onChanged }}>{ui}</JiraActionsProvider>);
  return onChanged;
}

function renderMenu(flag: JiraFlag, onOpen = vi.fn()) {
  render(
    <DropdownMenu open>
      <DropdownMenuTrigger>menu</DropdownMenuTrigger>
      <DropdownMenuContent>
        <FlagMenuItem issue={issue(flag)} onOpen={onOpen} />
      </DropdownMenuContent>
    </DropdownMenu>,
  );
  return onOpen;
}

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
});

describe('FlagIndicator', () => {
  it('shows nothing when the issue is not impeded', () => {
    withActions(<FlagIndicator issue={issue('none')} />);
    expect(screen.queryByRole('button', { name: 'impedimento' })).not.toBeInTheDocument();
  });

  it('opens the unflag dialog when the flag is clicked', () => {
    withActions(<FlagIndicator issue={issue('impediment')} />);
    fireEvent.click(screen.getByRole('button', { name: 'impedimento' }));
    expect(screen.getByRole('dialog', { name: 'Remover o impedimento de TT-5019?' })).toBeInTheDocument();
  });

  it('unflags without a note and refreshes the panel', async () => {
    const fetchMock = stubServer();
    const onChanged = withActions(<FlagIndicator issue={issue('impediment')} />);
    fireEvent.click(screen.getByRole('button', { name: 'impedimento' }));
    fireEvent.click(screen.getByRole('button', { name: 'Remover impedimento' }));

    await waitFor(() => expect(onChanged).toHaveBeenCalledTimes(1));
    expect(sentBody(fetchMock)).toEqual({
      url: '/api/jira/issues/TT-5019/flag',
      method: 'POST',
      body: { action: 'unflag' },
    });
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
  });

  it('sends the trimmed note when unflagging with one', async () => {
    const fetchMock = stubServer();
    withActions(<FlagIndicator issue={issue('impediment')} />);
    fireEvent.click(screen.getByRole('button', { name: 'impedimento' }));
    fireEvent.change(screen.getByRole('textbox', { name: 'Observação (opcional)' }), {
      target: { value: '  API liberada ' },
    });
    fireEvent.click(screen.getByRole('button', { name: 'Remover impedimento' }));

    await waitFor(() => expect(fetchMock).toHaveBeenCalled());
    expect(sentBody(fetchMock).body).toEqual({ action: 'unflag', note: 'API liberada' });
  });
});

describe('FlagIndicator after a partial write', () => {
  it('keeps the warning on screen when the refreshed row is no longer flagged', async () => {
    const warning = 'o impedimento foi removido, mas o comentário não foi gravado: recusado';
    stubServer(json(200, { ok: true, warning }));
    const wrap = (flag: JiraFlag) => (
      <JiraActionsProvider value={{ viewer: { kind: 'self' }, onChanged: vi.fn() }}>
        <FlagIndicator issue={issue(flag)} />
      </JiraActionsProvider>
    );
    const { rerender } = render(wrap('impediment'));
    fireEvent.click(screen.getByRole('button', { name: 'impedimento' }));
    fireEvent.change(screen.getByRole('textbox', { name: 'Observação (opcional)' }), { target: { value: 'ok' } });
    fireEvent.click(screen.getByRole('button', { name: 'Remover impedimento' }));
    await screen.findByRole('alert');

    rerender(wrap('none'));

    expect(screen.getByRole('alert')).toHaveTextContent(warning);
  });
});

describe('FlagMenuItem', () => {
  it('offers to flag an issue that is not impeded', () => {
    const onOpen = renderMenu('none');
    fireEvent.click(screen.getByRole('menuitem', { name: 'Marcar impedimento' }));
    expect(onOpen).toHaveBeenCalledWith('flag');
  });

  it('offers to remove the impediment of a flagged issue', () => {
    renderMenu('impediment');
    expect(screen.getByRole('menuitem', { name: 'Remover impedimento' })).toBeInTheDocument();
  });
});

describe('FlagDialog', () => {
  it('renders nothing while another dialog is open', () => {
    withActions(<FlagDialog issue={issue('none')} open="comment" onClose={vi.fn()} />);
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
  });

  it('requires a reason before flagging and says it becomes a comment', () => {
    withActions(<FlagDialog issue={issue('none')} open="flag" onClose={vi.fn()} />);
    const reason = screen.getByRole('textbox', { name: 'Motivo' });
    expect(reason).toHaveAccessibleDescription('o motivo vira um comentário na issue');
    const confirm = screen.getByRole('button', { name: 'Marcar impedimento' });
    expect(confirm).toBeDisabled();
    fireEvent.change(reason, { target: { value: '   ' } });
    expect(confirm).toBeDisabled();
  });

  it('flags with the trimmed reason, then refreshes and closes', async () => {
    const fetchMock = stubServer();
    const onClose = vi.fn();
    const onChanged = withActions(<FlagDialog issue={issue('none')} open="flag" onClose={onClose} />);
    fireEvent.change(screen.getByRole('textbox', { name: 'Motivo' }), { target: { value: ' aguardando API ' } });
    fireEvent.click(screen.getByRole('button', { name: 'Marcar impedimento' }));

    await waitFor(() => expect(onChanged).toHaveBeenCalledTimes(1));
    expect(sentBody(fetchMock).body).toEqual({ action: 'flag', reason: 'aguardando API' });
    expect(onClose).toHaveBeenCalled();
  });

  it('disables the confirm button while the request runs', async () => {
    let release: (value: unknown) => void = () => {};
    vi.stubGlobal('fetch', vi.fn(() => new Promise((resolve) => (release = resolve))));
    withActions(<FlagDialog issue={issue('none')} open="flag" onClose={vi.fn()} />);
    fireEvent.change(screen.getByRole('textbox', { name: 'Motivo' }), { target: { value: 'x' } });
    fireEvent.click(screen.getByRole('button', { name: 'Marcar impedimento' }));

    expect(await screen.findByRole('button', { name: 'enviando…' })).toBeDisabled();
    release(json(200, { ok: true }));
    await waitFor(() => expect(screen.getByRole('button', { name: 'Marcar impedimento' })).toBeEnabled());
  });

  it("shows Jira's refusal inline and does not refresh", async () => {
    stubServer(json(502, { error: 'Jira respondeu 400: campo Flagged não pode ser editado' }));
    const onClose = vi.fn();
    const onChanged = withActions(<FlagDialog issue={issue('none')} open="flag" onClose={onClose} />);
    fireEvent.change(screen.getByRole('textbox', { name: 'Motivo' }), { target: { value: 'x' } });
    fireEvent.click(screen.getByRole('button', { name: 'Marcar impedimento' }));

    expect(await screen.findByRole('alert')).toHaveTextContent(
      'Jira respondeu 400: campo Flagged não pode ser editado',
    );
    expect(onChanged).not.toHaveBeenCalled();
    expect(onClose).not.toHaveBeenCalled();
  });

  it('refreshes but stays open with the warning when only the comment failed', async () => {
    const warning = 'o impedimento foi marcado, mas o comentário não foi gravado: recusado';
    stubServer(json(200, { ok: true, warning }));
    const onClose = vi.fn();
    const onChanged = withActions(<FlagDialog issue={issue('none')} open="flag" onClose={onClose} />);
    fireEvent.change(screen.getByRole('textbox', { name: 'Motivo' }), { target: { value: 'x' } });
    fireEvent.click(screen.getByRole('button', { name: 'Marcar impedimento' }));

    expect(await screen.findByRole('alert')).toHaveTextContent(warning);
    expect(onChanged).toHaveBeenCalledTimes(1);
    expect(onClose).not.toHaveBeenCalled();
    fireEvent.click(screen.getByRole('button', { name: 'Fechar' }));
    expect(onClose).toHaveBeenCalled();
  });
});
