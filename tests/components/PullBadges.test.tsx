import { afterEach, describe, expect, it, vi } from 'vitest';
import { cleanup, render, screen } from '@testing-library/react';
import { PullBadges } from '@/components/pulls/PullBadges';
import type { PullRequestItem } from '@/lib/types';

afterEach(() => {
  cleanup();
  vi.useRealTimers();
});

function pull(over: Partial<PullRequestItem> = {}): PullRequestItem {
  return {
    id: 'PR_1',
    repo: 'acme/repo-4',
    number: 12,
    title: 'fix: TT-1 Change 1',
    url: 'https://github.com/acme/repo-4/pull/12',
    author: 'user-1',
    draft: false,
    awaitingYou: false,
    mine: false,
    isPullRequest: true,
    createdAt: '',
    updatedAt: '2026-10-21T10:00:00Z',
    ci: 'none',
    failedChecks: [],
    review: 'none',
    pendingReviewers: [],
    reviewers: [],
    reviewRequestedAt: null,
    merge: 'clean',
    size: null,
    headRef: 'feature/TT-1-branch-1',
    baseRef: 'main',
    headSha: 'abc',
    ...over,
  };
}

function issue(over: Partial<PullRequestItem> = {}): PullRequestItem {
  return pull({
    isPullRequest: false,
    ci: 'none',
    review: 'none',
    merge: 'none',
    size: null,
    headRef: null,
    baseRef: null,
    headSha: null,
    ...over,
  });
}

describe('PullBadges — CI', () => {
  it('liga o CI que falhou ao primeiro check quebrado', () => {
    render(
      <PullBadges
        item={pull({ ci: 'failing', failedChecks: [{ name: 'checks (module-1)', url: 'https://github.com/acme/repo-4/runs/1' }] })}
      />,
    );
    expect(screen.getByRole('link', { name: 'CI falhou em acme/repo-4#12: checks (module-1)' })).toHaveAttribute(
      'href',
      'https://github.com/acme/repo-4/runs/1',
    );
  });

  it('abre o check quebrado em outra aba', () => {
    render(<PullBadges item={pull({ ci: 'failing', failedChecks: [{ name: 'check-1', url: 'https://x/1' }] })} />);
    expect(screen.getByRole('link', { name: /CI falhou/ })).toHaveAttribute('target', '_blank');
  });

  it('lista todos os checks quebrados no título', () => {
    render(
      <PullBadges
        item={pull({ ci: 'failing', failedChecks: [{ name: 'check-1', url: null }, { name: 'check-2', url: null }] })}
      />,
    );
    expect(screen.getByText('CI falhou')).toHaveAttribute('title', 'Falharam: check-1, check-2');
  });

  it('não vira link quando o check quebrado não tem endereço', () => {
    render(<PullBadges item={pull({ ci: 'failing', failedChecks: [{ name: 'check-1', url: null }] })} />);
    expect(screen.queryByRole('link')).toBeNull();
  });

  it('mostra o CI rodando', () => {
    render(<PullBadges item={pull({ ci: 'running' })} />);
    expect(screen.getByText('CI rodando')).toBeInTheDocument();
  });

  it('mostra o CI que passou', () => {
    render(<PullBadges item={pull({ ci: 'passing' })} />);
    expect(screen.getByText('CI ok')).toBeInTheDocument();
  });

  it.each(['none', 'unknown'] as const)('não diz nada do CI quando ele é %s', (ci) => {
    render(<PullBadges item={pull({ ci })} />);
    expect(screen.queryByText(/CI/)).toBeNull();
  });
});

describe('PullBadges — revisão', () => {
  it('avisa quando pediram mudanças', () => {
    render(<PullBadges item={pull({ review: 'changes-requested' })} />);
    expect(screen.getByText('pediram mudanças')).toBeInTheDocument();
  });

  it('mostra o aprovado', () => {
    render(<PullBadges item={pull({ review: 'approved' })} />);
    expect(screen.getByText('aprovado')).toBeInTheDocument();
  });

  it('diz de quem a revisão está esperando', () => {
    render(<PullBadges item={pull({ review: 'pending', pendingReviewers: ['user-2', 'team:team-1'] })} />);
    expect(screen.getByText('aguardando revisão')).toHaveAttribute('title', 'Aguardando: user-2, team:team-1');
  });

  it.each(['none', 'unknown'] as const)('não diz nada da revisão quando ela é %s', (review) => {
    render(<PullBadges item={pull({ review })} />);
    expect(screen.queryByText(/aprovado|mudanças|aguardando/)).toBeNull();
  });
});

describe('PullBadges — merge', () => {
  it('avisa do conflito', () => {
    render(<PullBadges item={pull({ merge: 'conflict' })} />);
    expect(screen.getByText('conflito')).toBeInTheDocument();
  });

  it.each(['clean', 'blocked', 'unknown'] as const)('não chama de conflito o merge %s', (merge) => {
    render(<PullBadges item={pull({ merge })} />);
    expect(screen.queryByText('conflito')).toBeNull();
  });
});

describe('PullBadges — tamanho', () => {
  it('mostra linhas adicionadas e removidas', () => {
    render(<PullBadges item={pull({ size: { additions: 120, deletions: 30, files: 4 } })} />);
    expect(screen.getByText('+120 −30')).toBeInTheDocument();
  });

  it('não mostra tamanho que não veio', () => {
    render(<PullBadges item={pull({ size: null })} />);
    expect(screen.queryByText(/^\+/)).toBeNull();
  });
});

describe('PullBadges — idade', () => {
  it('diz há quanto tempo o PR está aberto e parado', () => {
    vi.useFakeTimers({ now: new Date('2026-10-21T12:00:00Z'), toFake: ['Date'] });
    render(<PullBadges item={pull({ createdAt: '2026-10-12T12:00:00Z', updatedAt: '2026-10-17T11:00:00Z' })} />);
    expect(screen.getByText(/aberto há 9 dias/)).toHaveTextContent('aberto há 9 dias · parado há 4 dias');
  });

  it('não chama de parado o que mudou há pouco', () => {
    vi.useFakeTimers({ now: new Date('2026-10-21T12:00:00Z'), toFake: ['Date'] });
    render(<PullBadges item={pull({ createdAt: '2026-10-12T12:00:00Z', updatedAt: '2026-10-21T11:00:00Z' })} />);
    expect(screen.queryByText(/parado/)).toBeNull();
  });

  it('mostra a idade de uma issue', () => {
    vi.useFakeTimers({ now: new Date('2026-10-21T12:00:00Z'), toFake: ['Date'] });
    render(<PullBadges item={issue({ createdAt: '2026-10-12T12:00:00Z' })} />);
    expect(screen.getByText('aberto há 9 dias')).toBeInTheDocument();
  });

  it('não põe selo de PR numa issue', () => {
    render(<PullBadges item={issue({ ci: 'failing', review: 'approved', merge: 'conflict' })} />);
    expect(screen.queryByText(/CI|aprovado|conflito/)).toBeNull();
  });
});
