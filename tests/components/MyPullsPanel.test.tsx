import { afterEach, describe, expect, it } from 'vitest';
import { cleanup, render, screen, within } from '@testing-library/react';
import { MyPullsPanel } from '@/components/pulls/MyPullsPanel';
import type { MyPullsDigest, PanelResult, PullRequestItem } from '@/lib/types';

afterEach(cleanup);

function pull(over: Partial<PullRequestItem> = {}): PullRequestItem {
  return {
    id: 'PR_1',
    repo: 'acme/repo-1',
    number: 1,
    title: 'feat: Change 1',
    url: 'https://github.com/acme/repo-1/pull/1',
    author: 'viewer',
    draft: false,
    awaitingYou: false,
    mine: true,
    isPullRequest: true,
    updatedAt: '2026-10-20T10:00:00Z',
    createdAt: '2026-10-19T10:00:00Z',
    ci: 'passing',
    failedChecks: [],
    review: 'pending',
    pendingReviewers: [],
    reviewers: [],
    reviewRequestedAt: null,
    merge: 'clean',
    size: null,
    headRef: 'feature/x',
    baseRef: 'main',
    headSha: 'abc',
    ...over,
  };
}

function digest(items: PullRequestItem[], over: Partial<MyPullsDigest> = {}): PanelResult<MyPullsDigest> {
  return { data: { items, truncated: false, total: items.length, ...over }, error: null };
}

function renderPanel(items: PullRequestItem[], over: Partial<MyPullsDigest> = {}) {
  render(<MyPullsPanel myPulls={digest(items, over)} items={items} loading={false} />);
}

describe('MyPullsPanel', () => {
  it('shows each group heading with its count', () => {
    renderPanel([
      pull({ number: 1, ci: 'failing', title: 'fix: A' }),
      pull({ number: 2, title: 'fix: B' }),
      pull({ number: 3, title: 'fix: C' }),
      pull({ number: 4, review: 'approved', title: 'fix: D' }),
      pull({ number: 5, draft: true, title: 'fix: E' }),
    ]);

    expect(screen.getAllByRole('heading').map((heading) => heading.textContent)).toEqual([
      'Precisa de você 1',
      'Esperando os outros 2',
      'Pronto para merge 1',
      'Rascunho 1',
    ]);
  });

  it('places each PR under its group', () => {
    renderPanel([pull({ number: 1, review: 'approved', title: 'fix: pronto' })]);

    const ready = screen.getByRole('region', { name: /Pronto para merge/ });
    expect(within(ready).getByRole('link', { name: 'fix: pronto' })).toBeInTheDocument();
  });

  it('omits groups without PRs', () => {
    renderPanel([pull({ draft: true })]);

    expect(screen.queryByRole('heading', { name: /Precisa de você/ })).not.toBeInTheDocument();
  });

  it('says why a PR needs you, joining every reason', () => {
    renderPanel([pull({ ci: 'failing', review: 'changes-requested', merge: 'conflict' })]);

    const needsYou = screen.getByRole('region', { name: /Precisa de você/ });
    expect(within(needsYou).getByText('CI falhou, pediram mudanças, conflito')).toBeInTheDocument();
  });

  it('never calls a not-yet-computed mergeability a conflict', () => {
    renderPanel([pull({ review: 'approved', merge: 'unknown' })]);

    expect(screen.queryByText(/conflito/)).not.toBeInTheDocument();
  });

  it('warns when the search page cut the list', () => {
    renderPanel([pull()], { truncated: true, total: 80 });

    expect(screen.getByText(/Mostrando 1 de 80/)).toBeInTheDocument();
  });

  it('does not warn when the list is complete', () => {
    renderPanel([pull()]);

    expect(screen.queryByText(/Mostrando/)).not.toBeInTheDocument();
  });

  it('says there is no open PR when the list is empty', () => {
    renderPanel([]);

    expect(screen.getByText('Nenhum PR seu aberto.')).toBeInTheDocument();
  });

  it('shows the panel error', () => {
    render(<MyPullsPanel myPulls={{ data: null, error: 'Token recusado' }} items={[]} loading={false} />);

    expect(screen.getByText('Token recusado')).toBeInTheDocument();
  });
});
