import { afterEach, describe, expect, it, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { TransitionAction } from '@/components/jira/actions/TransitionAction';
import { JiraActionsProvider } from '@/components/jira/actions/context';
import type { JiraItem } from '@/lib/types';
import type { JiraTransition } from '@/lib/integrations/jira/transitions';

const ISSUE: JiraItem = {
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
  impediment: 'none',
};

const DONE: JiraTransition = {
  id: '41',
  name: 'Itens concluídos',
  to: { name: 'Concluído', category: 'done' },
  requires: 'nothing',
};
const REVIEW: JiraTransition = {
  id: '7',
  name: 'Code Review PR',
  to: { name: 'Code Review PR', category: 'indeterminate' },
  requires: 'screen',
};

function json(status: number, body: unknown) {
  return { ok: status < 400, status, json: async () => body };
}

function stubServer(post: unknown = json(200, { ok: true }), get: unknown = json(200, { transitions: [DONE, REVIEW] })) {
  const fetchMock = vi.fn(async (_url: string, init?: RequestInit) => (init?.method === 'POST' ? post : get));
  vi.stubGlobal('fetch', fetchMock);
  return fetchMock;
}

function renderAction(onChanged = vi.fn()) {
  render(
    <JiraActionsProvider value={{ viewer: { kind: 'self' }, onChanged }}>
      <TransitionAction issue={ISSUE}>
        <span>Em Andamento</span>
      </TransitionAction>
    </JiraActionsProvider>,
  );
  fireEvent.click(screen.getByRole('button', { name: 'mudar status de TT-5019 (Em Andamento)' }));
  return onChanged;
}

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
});

describe('TransitionAction', () => {
  it('lists the transitions with the target status when it differs from the name', async () => {
    stubServer();
    renderAction();
    const option = await screen.findByRole('button', { name: /Itens concluídos/ });
    expect(option).toHaveTextContent('→ Concluído');
    expect(screen.getByRole('link', { name: /Code Review PR/ })).not.toHaveTextContent('→');
  });

  it('sends a transition that needs fields to Jira instead of writing', async () => {
    const fetchMock = stubServer();
    renderAction();
    const link = await screen.findByRole('link', { name: /Code Review PR.*pede campos — abrir no Jira/ });
    expect(link).toHaveAttribute('href', ISSUE.url);
    expect(link).toHaveAttribute('target', '_blank');
    fireEvent.click(link);
    expect(fetchMock.mock.calls.some(([, init]) => init?.method === 'POST')).toBe(false);
  });

  it('asks for confirmation before moving, and cancelling writes nothing', async () => {
    const fetchMock = stubServer();
    renderAction();
    fireEvent.click(await screen.findByRole('button', { name: /Itens concluídos/ }));
    expect(screen.getByText('Mover TT-5019 de Em Andamento para Concluído?')).toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: 'Cancelar' }));
    expect(await screen.findByRole('button', { name: /Itens concluídos/ })).toBeInTheDocument();
    expect(fetchMock.mock.calls.some(([, init]) => init?.method === 'POST')).toBe(false);
  });

  it('moves the issue on confirm and asks the panel to refresh', async () => {
    const fetchMock = stubServer();
    const onChanged = renderAction();
    fireEvent.click(await screen.findByRole('button', { name: /Itens concluídos/ }));
    fireEvent.click(screen.getByRole('button', { name: 'Confirmar' }));
    await waitFor(() => expect(onChanged).toHaveBeenCalledTimes(1));
    const post = fetchMock.mock.calls.find(([, init]) => init?.method === 'POST');
    expect(post?.[0]).toBe('/api/jira/issues/TT-5019/transitions');
    expect(JSON.parse(String(post?.[1]?.body))).toEqual({ transitionId: '41' });
    await waitFor(() => expect(screen.queryByText(/Mover TT-5019/)).not.toBeInTheDocument());
  });

  it("shows Jira's refusal with a link to open the issue in Jira", async () => {
    stubServer(json(502, { error: 'Jira respondeu 400: O campo Resolução é obrigatório' }));
    const onChanged = renderAction();
    fireEvent.click(await screen.findByRole('button', { name: /Itens concluídos/ }));
    fireEvent.click(screen.getByRole('button', { name: 'Confirmar' }));
    const alert = await screen.findByRole('alert');
    expect(alert).toHaveTextContent('O campo Resolução é obrigatório');
    expect(screen.getByRole('link', { name: 'abrir no Jira' })).toHaveAttribute('href', ISSUE.url);
    expect(onChanged).not.toHaveBeenCalled();
  });

  it('disables the buttons while the move is running', async () => {
    let release: (value: unknown) => void = () => {};
    const pending = new Promise((resolve) => (release = resolve));
    vi.stubGlobal(
      'fetch',
      vi.fn(async (_url: string, init?: RequestInit) =>
        init?.method === 'POST' ? pending : json(200, { transitions: [DONE] }),
      ),
    );
    renderAction();
    fireEvent.click(await screen.findByRole('button', { name: /Itens concluídos/ }));
    fireEvent.click(screen.getByRole('button', { name: 'Confirmar' }));
    expect(await screen.findByRole('button', { name: 'Movendo…' })).toBeDisabled();
    expect(screen.getByRole('button', { name: 'Cancelar' })).toBeDisabled();
    release(json(200, { ok: true }));
  });

  it('shows the loading error with a retry that loads again', async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(json(502, { error: 'Jira recusou o e-mail ou o API token' }))
      .mockResolvedValueOnce(json(200, { transitions: [DONE] }));
    vi.stubGlobal('fetch', fetchMock);
    renderAction();
    expect(await screen.findByRole('alert')).toHaveTextContent('Jira recusou o e-mail ou o API token');
    fireEvent.click(screen.getByRole('button', { name: 'Tentar de novo' }));
    expect(await screen.findByRole('button', { name: /Itens concluídos/ })).toBeInTheDocument();
  });

  it('shows the loading state while the transitions arrive', async () => {
    vi.stubGlobal('fetch', vi.fn(() => new Promise(() => {})));
    renderAction();
    expect(await screen.findByRole('status')).toHaveTextContent('carregando transições…');
  });

  it('keeps the latest load when an older one answers after it', async () => {
    let releaseFirst: (value: unknown) => void = () => {};
    const fetchMock = vi
      .fn()
      .mockReturnValueOnce(new Promise((resolve) => (releaseFirst = resolve)))
      .mockResolvedValueOnce(json(200, { transitions: [DONE] }));
    vi.stubGlobal('fetch', fetchMock);
    renderAction();
    const trigger = screen.getByRole('button', { name: 'mudar status de TT-5019 (Em Andamento)' });
    fireEvent.click(trigger);
    fireEvent.click(trigger);
    expect(await screen.findByRole('button', { name: /Itens concluídos/ })).toBeInTheDocument();

    releaseFirst(json(502, { error: 'resposta antiga' }));

    await waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(2));
    await new Promise((resolve) => setTimeout(resolve, 0));
    expect(screen.queryByText('resposta antiga')).not.toBeInTheDocument();
    expect(screen.getByRole('button', { name: /Itens concluídos/ })).toBeInTheDocument();
  });
});
