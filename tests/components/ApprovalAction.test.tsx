import { afterEach, describe, expect, it, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { ApprovalBadge } from '@/components/jira/actions/ApprovalAction';
import { JiraActionsProvider, type JiraViewer } from '@/components/jira/actions/context';
import type { JiraItem } from '@/lib/types';

const ISSUE: JiraItem = {
  key: 'TT-123',
  summary: 'Liberar acesso ao ambiente',
  status: 'Aguardando aprovação',
  statusCategory: 'indeterminate',
  project: 'TT',
  url: 'https://acme.atlassian.net/browse/TT-123',
  parent: null,
  role: 'assignee',
  awaitingApproval: true,
  kind: 'História',
  subtask: false,
  hierarchyLevel: 0,
  updatedAt: '2026-10-20T10:00:00.000Z',
  dueDate: '',
  priority: null,
  flag: 'none',
};

function json(status: number, body: unknown) {
  return { ok: status >= 200 && status < 300, status, json: async () => body };
}

function renderBadge(viewer: JiraViewer = { kind: 'self' }, onChanged = vi.fn()) {
  render(
    <JiraActionsProvider value={{ viewer, onChanged }}>
      <ApprovalBadge issue={ISSUE} className="badge" title="aguardando a sua aprovação" />
    </JiraActionsProvider>,
  );
  return onChanged;
}

function stubFetch(...responses: unknown[]) {
  const fetchMock = vi.fn();
  for (const r of responses) fetchMock.mockResolvedValueOnce(r);
  vi.stubGlobal('fetch', fetchMock);
  return fetchMock;
}

const PENDING = { approvals: [{ id: '3516', name: 'Aprovação do gestor' }] };

async function openAndChoose(label: 'Aprovar' | 'Recusar') {
  fireEvent.click(screen.getByRole('button', { name: 'aprovar ou recusar TT-123' }));
  fireEvent.click(await screen.findByRole('button', { name: label }));
}

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
});

describe('ApprovalBadge', () => {
  it('stays a plain mark when looking at another person', () => {
    renderBadge({ kind: 'person', name: 'Ana' });
    expect(screen.getByText('APROV')).toBeInTheDocument();
    expect(screen.queryByRole('button')).not.toBeInTheDocument();
  });

  it('opens a dialog with the issue and the approval to answer', async () => {
    const fetchMock = stubFetch(json(200, PENDING));
    renderBadge();
    fireEvent.click(screen.getByRole('button', { name: 'aprovar ou recusar TT-123' }));
    expect(await screen.findByText('Aprovação do gestor')).toBeInTheDocument();
    expect(screen.getByText(/Liberar acesso ao ambiente/)).toBeInTheDocument();
    expect(fetchMock).toHaveBeenCalledWith('/api/jira/issues/TT-123/approvals');
  });

  it('says there is nothing to answer and links to Jira when the list is empty', async () => {
    stubFetch(json(200, { approvals: [] }));
    renderBadge();
    fireEvent.click(screen.getByRole('button', { name: 'aprovar ou recusar TT-123' }));
    expect(await screen.findByText(/nenhuma aprovação sua pendente nesta issue/)).toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'abrir no Jira' })).toHaveAttribute('href', ISSUE.url);
  });

  it('shows the error when the approvals cannot be loaded', async () => {
    stubFetch(json(502, { error: 'Jira respondeu 500' }));
    renderBadge();
    fireEvent.click(screen.getByRole('button', { name: 'aprovar ou recusar TT-123' }));
    expect(await screen.findByRole('alert')).toHaveTextContent('Jira respondeu 500');
  });

  it('asks for confirmation before approving and writes nothing until then', async () => {
    const fetchMock = stubFetch(json(200, PENDING));
    renderBadge();
    await openAndChoose('Aprovar');
    expect(screen.getByRole('heading', { name: 'Confirmar aprovação de TT-123?' })).toBeInTheDocument();
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it('approves after confirmation and refreshes the panel', async () => {
    const fetchMock = stubFetch(json(200, PENDING), json(200, { ok: true }));
    const onChanged = renderBadge();
    await openAndChoose('Aprovar');
    fireEvent.click(screen.getByRole('button', { name: 'Confirmar aprovação' }));
    await waitFor(() => expect(onChanged).toHaveBeenCalledTimes(1));
    const [url, init] = fetchMock.mock.calls[1];
    expect(url).toBe('/api/jira/issues/TT-123/approvals');
    expect(init.method).toBe('POST');
    expect(JSON.parse(init.body)).toEqual({ approvalId: '3516', decision: 'approve' });
    await waitFor(() => expect(screen.queryByRole('dialog')).not.toBeInTheDocument());
  });

  it('declines through a destructive confirmation', async () => {
    const fetchMock = stubFetch(json(200, PENDING), json(200, { ok: true }));
    renderBadge();
    await openAndChoose('Recusar');
    expect(screen.getByRole('heading', { name: 'Confirmar recusa de TT-123?' })).toBeInTheDocument();
    const confirm = screen.getByRole('button', { name: 'Confirmar recusa' });
    expect(confirm).toHaveAttribute('data-variant', 'destructive');
    fireEvent.click(confirm);
    await waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(2));
    expect(JSON.parse(fetchMock.mock.calls[1][1].body)).toEqual({ approvalId: '3516', decision: 'decline' });
  });

  it('disables the confirmation while the decision is being sent', async () => {
    let finish: (value: unknown) => void = () => {};
    const fetchMock = stubFetch(json(200, PENDING));
    fetchMock.mockReturnValueOnce(new Promise((resolve) => (finish = resolve)));
    renderBadge();
    await openAndChoose('Aprovar');
    fireEvent.click(screen.getByRole('button', { name: 'Confirmar aprovação' }));
    expect(await screen.findByRole('button', { name: 'enviando…' })).toBeDisabled();
    finish(json(200, { ok: true }));
  });

  it('shows Jira’s refusal inline and keeps the panel as it was', async () => {
    stubFetch(json(200, PENDING), json(502, { error: 'Jira respondeu 400: você não pode responder' }));
    const onChanged = renderBadge();
    await openAndChoose('Aprovar');
    fireEvent.click(screen.getByRole('button', { name: 'Confirmar aprovação' }));
    expect(await screen.findByRole('alert')).toHaveTextContent('Jira respondeu 400: você não pode responder');
    expect(onChanged).not.toHaveBeenCalled();
  });

  it('reloads the approvals and goes back to the choice when the approval is no longer pending', async () => {
    const LEFT = { approvals: [{ id: '3517', name: 'Aprovação do diretor' }] };
    const fetchMock = stubFetch(
      json(200, PENDING),
      json(409, { error: 'essa aprovação não está mais pendente para você' }),
      json(200, LEFT),
    );
    const onChanged = renderBadge();
    await openAndChoose('Aprovar');
    fireEvent.click(screen.getByRole('button', { name: 'Confirmar aprovação' }));

    expect(await screen.findByText('Aprovação do diretor')).toBeInTheDocument();
    expect(screen.getByRole('alert')).toHaveTextContent('essa aprovação não está mais pendente para você');
    expect(screen.getByRole('heading', { name: 'Aprovação de TT-123' })).toBeInTheDocument();
    expect(fetchMock).toHaveBeenCalledTimes(3);
    expect(fetchMock.mock.calls[2][0]).toBe('/api/jira/issues/TT-123/approvals');
    expect(onChanged).not.toHaveBeenCalled();
  });
});
