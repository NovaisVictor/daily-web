import { afterEach, describe, expect, it, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { PullJiraSync } from '@/components/pulls/PullJiraSync';
import { PullsActionsProvider } from '@/components/pulls/context';
import type { PullJiraRef, PullRequestItem } from '@/lib/types';
import type { JiraTransition } from '@/lib/integrations/jira/transitions';

const CARD: PullJiraRef = {
  key: 'TT-5019',
  url: 'https://example.atlassian.net/browse/TT-5019',
  status: 'Backlog',
  statusCategory: 'new',
};

const PR: PullRequestItem = {
  id: 'PR_1',
  repo: 'acme/repo-1',
  number: 1,
  title: 'feat: TT-5019 Change 1',
  url: 'https://github.com/acme/repo-1/pull/1',
  author: 'viewer',
  draft: false,
  awaitingYou: false,
  mine: true,
  isPullRequest: true,
  updatedAt: '2026-10-21T10:00:00Z',
  createdAt: '2026-10-20T10:00:00Z',
  ci: 'passing',
  failedChecks: [],
  review: 'pending',
  pendingReviewers: [],
  reviewers: [],
  reviewRequestedAt: null,
  merge: 'clean',
  size: null,
  headRef: 'feature/TT-5019-branch-1',
  baseRef: 'main',
  headSha: 'abc',
  jira: [CARD],
};

const REVIEW: JiraTransition = {
  id: '7',
  name: 'Code Review PR',
  to: { name: 'Code Review PR', category: 'indeterminate' },
  requires: 'nothing',
};

function json(status: number, body: unknown) {
  return { ok: status < 400, status, json: async () => body };
}

function stubServer(get: unknown = json(200, { transition: REVIEW }), post: unknown = json(200, { ok: true })) {
  const fetchMock = vi.fn(async (_url: string, init?: RequestInit) => (init?.method === 'POST' ? post : get));
  vi.stubGlobal('fetch', fetchMock);
  return fetchMock;
}

const posts = (fetchMock: ReturnType<typeof stubServer>) => fetchMock.mock.calls.filter(([, init]) => init?.method === 'POST');

function renderSync(item: PullRequestItem = PR, onChanged = vi.fn()) {
  render(
    <PullsActionsProvider value={{ onChanged }}>
      <PullJiraSync item={item} />
    </PullsActionsProvider>,
  );
  return onChanged;
}

function openMove(name = 'mover TT-5019 para revisão') {
  fireEvent.click(screen.getByRole('button', { name }));
}

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
});

describe('PullJiraSync', () => {
  it('offers moving a backlog card to review on a ready PR', () => {
    renderSync();
    expect(screen.getByRole('button', { name: 'mover TT-5019 para revisão' })).toHaveTextContent('TT-5019 → revisão');
  });

  it('offers moving a backlog card to in progress on a draft PR', () => {
    renderSync({ ...PR, draft: true });
    expect(screen.getByRole('button', { name: 'mover TT-5019 para em andamento' })).toBeInTheDocument();
  });

  it('offers nothing when the card is already in progress', () => {
    renderSync({ ...PR, jira: [{ ...CARD, statusCategory: 'indeterminate' }] });
    expect(screen.queryByRole('button')).not.toBeInTheDocument();
  });

  it('warns without a button when the card is done and the PR is open', () => {
    renderSync({ ...PR, jira: [{ ...CARD, statusCategory: 'done', status: 'Concluído' }] });
    expect(screen.getByText(/card concluído com/)).toBeInTheDocument();
    expect(screen.queryByRole('button')).not.toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'PR aberto' })).toHaveAttribute('href', PR.url);
    expect(screen.getByRole('link', { name: 'TT-5019' })).toHaveAttribute('href', CARD.url);
  });

  it('asks the server for the review transition of that card', async () => {
    const fetchMock = stubServer();
    renderSync();
    openMove();
    await screen.findByText('Mover TT-5019 de Backlog para Code Review PR?');
    expect(fetchMock.mock.calls[0][0]).toBe('/api/pulls/jira-sync?key=TT-5019&intent=review');
  });

  it('writes nothing before the confirmation', async () => {
    const fetchMock = stubServer();
    renderSync();
    openMove();
    await screen.findByRole('button', { name: 'Confirmar' });
    expect(posts(fetchMock)).toHaveLength(0);
  });

  it('posts the chosen transition to the Jira transitions route and refreshes on confirmation', async () => {
    const fetchMock = stubServer();
    const onChanged = renderSync();
    openMove();
    fireEvent.click(await screen.findByRole('button', { name: 'Confirmar' }));
    await waitFor(() => expect(onChanged).toHaveBeenCalledTimes(1));
    const [url, init] = posts(fetchMock)[0];
    expect(url).toBe('/api/jira/issues/TT-5019/transitions');
    expect(JSON.parse(String(init?.body))).toEqual({ transitionId: '7' });
  });

  it('disables the buttons while the move is pending', async () => {
    stubServer(json(200, { transition: REVIEW }), new Promise(() => {}));
    renderSync();
    openMove();
    fireEvent.click(await screen.findByRole('button', { name: 'Confirmar' }));
    expect(await screen.findByRole('button', { name: 'Movendo…' })).toBeDisabled();
  });

  it("shows Jira's refusal inline and does not refresh", async () => {
    stubServer(json(200, { transition: REVIEW }), json(409, { error: 'essa transição não está mais disponível' }));
    const onChanged = renderSync();
    openMove();
    fireEvent.click(await screen.findByRole('button', { name: 'Confirmar' }));
    expect(await screen.findByRole('alert')).toHaveTextContent('essa transição não está mais disponível');
    expect(onChanged).not.toHaveBeenCalled();
  });

  it('sends to Jira when no transition is available', async () => {
    stubServer(json(404, { error: 'nenhuma transição para revisão disponível — abrir no Jira' }));
    renderSync();
    openMove();
    const alert = await screen.findByRole('alert');
    expect(alert).toHaveTextContent('nenhuma transição para revisão disponível');
    expect(screen.getByRole('link', { name: 'abrir no Jira' })).toHaveAttribute('href', CARD.url);
  });

  it('sends a transition that needs fields to Jira instead of offering the write', async () => {
    stubServer(json(200, { transition: { ...REVIEW, requires: 'screen' } }));
    renderSync();
    openMove();
    const link = await screen.findByRole('link', { name: 'pede campos — abrir no Jira' });
    expect(link).toHaveAttribute('href', CARD.url);
    expect(screen.queryByRole('button', { name: 'Confirmar' })).not.toBeInTheDocument();
  });

  it('fails visibly on an unexpected server answer', async () => {
    stubServer(json(200, { transition: { id: 7 } }));
    renderSync();
    openMove();
    expect(await screen.findByRole('alert')).toHaveTextContent('resposta inesperada do servidor');
  });
});
