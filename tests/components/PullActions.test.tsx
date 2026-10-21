import { afterEach, describe, expect, it, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import checkRuns from '../fixtures/github/check-runs.json';
import { PullActions } from '@/components/pulls/PullActions';
import { PullsActionsProvider } from '@/components/pulls/context';
import type { PullRequestItem } from '@/lib/types';

const SHA = '9fd7b84776d6e7cd1a3d25dd3b933e084d4045b4';
const BASE_URL = '/api/pulls/acme/repo-4/42';

function pull(over: Partial<PullRequestItem> = {}): PullRequestItem {
  return {
    id: 'PR_test',
    repo: 'acme/repo-4',
    number: 42,
    title: 'feat: TT-1 Change 1',
    url: 'https://github.com/acme/repo-4/pull/42',
    author: 'user-1',
    draft: false,
    awaitingYou: true,
    mine: false,
    isPullRequest: true,
    updatedAt: '2026-10-20T10:00:00Z',
    createdAt: '2026-10-19T10:00:00Z',
    ci: 'passing',
    failedChecks: [],
    review: 'pending',
    pendingReviewers: [],
    merge: 'unknown',
    size: { additions: 1, deletions: 1, files: 1 },
    headRef: 'feature/TT-1-branch-1',
    baseRef: 'main',
    headSha: SHA,
    ...over,
  };
}

function json(status: number, body: unknown) {
  return { ok: status >= 200 && status < 300, status, json: async () => body };
}

function stubFetch(...responses: unknown[]) {
  const fetchMock = vi.fn();
  for (const r of responses) fetchMock.mockResolvedValueOnce(r);
  vi.stubGlobal('fetch', fetchMock);
  return fetchMock;
}

function sent(fetchMock: ReturnType<typeof vi.fn>) {
  const [url, init] = fetchMock.mock.calls[0];
  return { url, method: init.method, body: JSON.parse(init.body) };
}

function renderActions(item: PullRequestItem, onChanged = vi.fn()) {
  render(
    <PullsActionsProvider value={{ onChanged }}>
      <PullActions item={item} />
    </PullsActionsProvider>,
  );
  return onChanged;
}

async function openMenu() {
  fireEvent.pointerDown(screen.getByRole('button', { name: 'ações de acme/repo-4#42' }), {
    button: 0,
    ctrlKey: false,
    pointerType: 'mouse',
  });
  return screen.findByRole('menu');
}

async function menuLabels(item: PullRequestItem) {
  renderActions(item);
  const menu = await openMenu();
  return within(menu)
    .getAllByRole('menuitem')
    .map((entry) => entry.textContent);
}

async function openDialog(item: PullRequestItem, entry: string, dialog: string, onChanged = vi.fn()) {
  renderActions(item, onChanged);
  await openMenu();
  fireEvent.click(await screen.findByRole('menuitem', { name: entry }));
  return screen.findByRole('dialog', { name: dialog });
}

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
});

describe('PullActions menu', () => {
  it('offers only "Comentar" on an issue', async () => {
    expect(await menuLabels(pull({ isPullRequest: false, ci: 'none', review: 'none', merge: 'none' }))).toEqual([
      'Comentar',
    ]);
  });

  it("offers approve and request changes on someone else's pull request", async () => {
    expect(await menuLabels(pull())).toEqual(['Aprovar', 'Pedir mudanças', 'Comentar']);
  });

  it('does not offer a review on your own pull request', async () => {
    expect(await menuLabels(pull({ mine: true, review: 'none' }))).toEqual(['Comentar']);
  });

  it.each(['changes-requested', 'pending'] as const)(
    'offers to re-request review on your own pull request when the review is %s',
    async (review) => {
      expect(await menuLabels(pull({ mine: true, review }))).toContain('Pedir revisão de novo');
    },
  );

  it('offers the merge only when GitHub says it is clean', async () => {
    expect(await menuLabels(pull({ merge: 'clean' }))).toContain('Fazer merge');
  });

  it.each(['conflict', 'blocked', 'unknown'] as const)('hides the merge when the state is %s', async (merge) => {
    expect(await menuLabels(pull({ merge }))).not.toContain('Fazer merge');
  });

  it('hides the merge on a draft', async () => {
    expect(await menuLabels(pull({ merge: 'clean', draft: true }))).not.toContain('Fazer merge');
  });

  it('offers to re-run CI only when it is failing', async () => {
    expect(await menuLabels(pull({ ci: 'failing' }))).toContain('Rodar CI de novo');
  });

  it('hides the CI re-run when CI is passing', async () => {
    expect(await menuLabels(pull())).not.toContain('Rodar CI de novo');
  });
});

describe('review dialogs', () => {
  it('approves with an optional comment', async () => {
    const fetchMock = stubFetch(json(200, { ok: true, review: { id: 1, state: 'APPROVED' } }));
    await openDialog(pull(), 'Aprovar', 'Aprovar acme/repo-4#42');
    fireEvent.click(screen.getByRole('button', { name: 'Aprovar' }));
    await screen.findByRole('status');
    expect(sent(fetchMock)).toEqual({ url: `${BASE_URL}/reviews`, method: 'POST', body: { event: 'APPROVE' } });
  });

  it('keeps "Pedir mudanças" disabled until a comment is written', async () => {
    await openDialog(pull(), 'Pedir mudanças', 'Pedir mudanças em acme/repo-4#42');
    expect(screen.getByRole('button', { name: 'Pedir mudanças' })).toBeDisabled();
  });

  it('requests changes with the trimmed comment', async () => {
    const fetchMock = stubFetch(json(200, { ok: true, review: { id: 1, state: 'CHANGES_REQUESTED' } }));
    await openDialog(pull(), 'Pedir mudanças', 'Pedir mudanças em acme/repo-4#42');
    fireEvent.change(screen.getByRole('textbox', { name: 'comentário em acme/repo-4#42' }), {
      target: { value: '  falta teste  ' },
    });
    fireEvent.click(screen.getByRole('button', { name: 'Pedir mudanças' }));
    await screen.findByRole('status');
    expect(sent(fetchMock).body).toEqual({ event: 'REQUEST_CHANGES', body: 'falta teste' });
  });

  it("shows GitHub's refusal inline and keeps the dialog open", async () => {
    stubFetch(json(502, { error: 'GitHub respondeu 422: Can not approve your own pull request' }));
    await openDialog(pull(), 'Aprovar', 'Aprovar acme/repo-4#42');
    fireEvent.click(screen.getByRole('button', { name: 'Aprovar' }));
    expect(await screen.findByRole('alert')).toHaveTextContent('Can not approve your own pull request');
  });

  it('refreshes the panel after the review is accepted', async () => {
    stubFetch(json(200, { ok: true, review: { id: 1, state: 'APPROVED' } }));
    const onChanged = vi.fn();
    await openDialog(pull(), 'Aprovar', 'Aprovar acme/repo-4#42', onChanged);
    fireEvent.click(screen.getByRole('button', { name: 'Aprovar' }));
    await waitFor(() => expect(onChanged).toHaveBeenCalledTimes(1));
  });

  it('disables the confirm button while the review is being sent', async () => {
    vi.stubGlobal('fetch', vi.fn(() => new Promise(() => {})));
    await openDialog(pull(), 'Aprovar', 'Aprovar acme/repo-4#42');
    fireEvent.click(screen.getByRole('button', { name: 'Aprovar' }));
    expect(await screen.findByRole('button', { name: 'Aprovando…' })).toBeDisabled();
  });
});

describe('comment dialog', () => {
  it('comments on an issue through the comments route', async () => {
    const fetchMock = stubFetch(json(200, { ok: true, comment: { id: 1, url: 'u' } }));
    await openDialog(pull({ isPullRequest: false }), 'Comentar', 'Comentar em acme/repo-4#42');
    fireEvent.change(screen.getByRole('textbox', { name: 'comentário em acme/repo-4#42' }), {
      target: { value: 'oi' },
    });
    fireEvent.click(screen.getByRole('button', { name: 'Comentar' }));
    await screen.findByRole('status');
    expect(sent(fetchMock)).toEqual({ url: `${BASE_URL}/comments`, method: 'POST', body: { body: 'oi' } });
  });

  it('refuses text over 10000 characters without calling the server', async () => {
    const fetchMock = stubFetch();
    await openDialog(pull(), 'Comentar', 'Comentar em acme/repo-4#42');
    fireEvent.change(screen.getByRole('textbox', { name: 'comentário em acme/repo-4#42' }), {
      target: { value: 'a'.repeat(10001) },
    });
    expect(screen.getByRole('alert')).toHaveTextContent('passou de 10000 caracteres');
    expect(fetchMock).not.toHaveBeenCalled();
  });
});

describe('re-request review dialog', () => {
  const mine = pull({ mine: true, review: 'changes-requested', pendingReviewers: ['user-2', 'team:team-1'] });

  it('re-requests the chosen pending reviewers and the typed logins', async () => {
    const fetchMock = stubFetch(json(200, { ok: true, requested: ['user-2', 'team:team-1', 'user-3'] }));
    await openDialog(mine, 'Pedir revisão de novo', 'Pedir revisão de novo em acme/repo-4#42');
    fireEvent.click(screen.getByRole('checkbox', { name: 'team:team-1' }));
    fireEvent.change(screen.getByRole('textbox', { name: 'outros logins (separados por vírgula)' }), {
      target: { value: 'user-3' },
    });
    fireEvent.click(screen.getByRole('button', { name: 'Pedir revisão' }));
    await screen.findByRole('status');
    expect(sent(fetchMock)).toEqual({
      url: `${BASE_URL}/reviewers`,
      method: 'POST',
      body: { reviewers: ['team:team-1', 'user-3'] },
    });
  });

  it('refuses a typed value that is not a GitHub login', async () => {
    await openDialog(mine, 'Pedir revisão de novo', 'Pedir revisão de novo em acme/repo-4#42');
    fireEvent.change(screen.getByRole('textbox', { name: 'outros logins (separados por vírgula)' }), {
      target: { value: 'user_3!' },
    });
    expect(screen.getByRole('alert')).toHaveTextContent('"user_3!" não é um login do GitHub');
  });

  it('keeps the confirm disabled with nobody chosen', async () => {
    await openDialog(mine, 'Pedir revisão de novo', 'Pedir revisão de novo em acme/repo-4#42');
    expect(screen.getByRole('button', { name: 'Pedir revisão' })).toBeDisabled();
  });
});

describe('merge dialog', () => {
  const clean = pull({ merge: 'clean' });

  it('shows the head and base branches', async () => {
    const dialog = await openDialog(clean, 'Fazer merge', 'Fazer merge de acme/repo-4#42');
    expect(dialog).toHaveTextContent('feature/TT-1-branch-1 → main');
  });

  it('defaults to squash', async () => {
    await openDialog(clean, 'Fazer merge', 'Fazer merge de acme/repo-4#42');
    expect(screen.getByRole('radio', { name: 'squash' })).toBeChecked();
  });

  it('sends the chosen method and the head sha the user saw', async () => {
    const fetchMock = stubFetch(json(200, { ok: true, sha: 'x' }));
    await openDialog(clean, 'Fazer merge', 'Fazer merge de acme/repo-4#42');
    fireEvent.click(screen.getByRole('radio', { name: 'rebase' }));
    fireEvent.click(screen.getByRole('button', { name: 'Fazer merge' }));
    await screen.findByRole('status');
    expect(sent(fetchMock)).toEqual({
      url: `${BASE_URL}/merge`,
      method: 'POST',
      body: { method: 'rebase', headSha: SHA },
    });
  });

  it('shows the refusal when the pull request changed since the user looked', async () => {
    stubFetch(json(409, { error: 'o PR recebeu commits novos desde que você olhou — atualize o painel e confira' }));
    await openDialog(clean, 'Fazer merge', 'Fazer merge de acme/repo-4#42');
    fireEvent.click(screen.getByRole('button', { name: 'Fazer merge' }));
    expect(await screen.findByRole('alert')).toHaveTextContent('o PR recebeu commits novos');
  });

  it('does not refresh the panel when the merge is refused', async () => {
    stubFetch(json(502, { error: 'GitHub respondeu 405: Pull Request is not mergeable' }));
    const onChanged = vi.fn();
    await openDialog(clean, 'Fazer merge', 'Fazer merge de acme/repo-4#42', onChanged);
    fireEvent.click(screen.getByRole('button', { name: 'Fazer merge' }));
    await screen.findByRole('alert');
    expect(onChanged).not.toHaveBeenCalled();
  });
});

describe('re-run CI dialog', () => {
  const failing = pull({
    ci: 'failing',
    failedChecks: checkRuns.check_runs.map((run) => ({ name: run.name, url: run.html_url })),
  });

  it('lists the failed checks before confirming', async () => {
    await openDialog(failing, 'Rodar CI de novo', 'Rodar CI de novo em acme/repo-4#42');
    const list = screen.getByRole('list', { name: 'checks com falha' });
    expect(within(list).getAllByRole('listitem').map((li) => li.textContent)).toEqual(['scan', 'check-1']);
  });

  it('sends the head sha and says how many workflows re-ran', async () => {
    const fetchMock = stubFetch(json(200, { ok: true, rerun: 2 }));
    await openDialog(failing, 'Rodar CI de novo', 'Rodar CI de novo em acme/repo-4#42');
    fireEvent.click(screen.getByRole('button', { name: 'Rodar de novo' }));
    expect(await screen.findByRole('status')).toHaveTextContent('2 workflow(s) rodando de novo');
    expect(sent(fetchMock)).toEqual({ url: `${BASE_URL}/rerun`, method: 'POST', body: { headSha: SHA } });
  });

  it('explains when no Actions workflow failed on the commit', async () => {
    stubFetch(json(200, { ok: true, rerun: 0 }));
    await openDialog(failing, 'Rodar CI de novo', 'Rodar CI de novo em acme/repo-4#42');
    fireEvent.click(screen.getByRole('button', { name: 'Rodar de novo' }));
    expect(await screen.findByRole('status')).toHaveTextContent(
      'nenhum workflow do GitHub Actions falhou neste commit (o check pode ser de outro serviço)',
    );
  });
});
