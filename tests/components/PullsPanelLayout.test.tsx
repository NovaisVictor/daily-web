import { describe, expect, it, afterEach, beforeEach, vi } from 'vitest';
import { render, screen, cleanup } from '@testing-library/react';
import { PullsPanel } from '@/components/PullsPanel';
import { PanelFrame } from '@/components/data/Panel';
import type { PullRequestItem } from '@/lib/types';

vi.mock('next/navigation', () => ({
  usePathname: () => '/',
  useRouter: () => ({ push: () => {} }),
  useSearchParams: () => new URLSearchParams(''),
}));

beforeEach(() => {
  vi.spyOn(global, 'fetch').mockResolvedValue(
    new Response(JSON.stringify({ repos: [] }), { status: 200 }),
  );
});

afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
});

function pull(n: number): PullRequestItem {
  return {
    repo: 'joao/daily-web',
    number: n,
    title: `PR ${n}`,
    url: `https://github.com/joao/daily-web/pull/${n}`,
    author: 'joao',
    draft: false,
    awaitingYou: false,
    mine: true,
    isPullRequest: true,
    id: 'PR_test',
    createdAt: '',
    ci: 'none',
    failedChecks: [],
    review: 'none',
    pendingReviewers: [],
    merge: 'unknown',
    size: { additions: 1, deletions: 1, files: 1 },
    headRef: 'feature/x',
    baseRef: 'main',
    headSha: 'abc123',
    updatedAt: '2026-09-10T10:00:00Z',
  };
}

/** O painel como a grade o monta: dentro de uma moldura de altura fixa, onde
 *  o corpo é que precisa rolar. */
function montar(items: PullRequestItem[]) {
  return render(
    <PanelFrame>
      <PullsPanel pulls={{ data: { items, errors: [], defaultBranches: [], truncated: [] }, error: null }} />
    </PanelFrame>,
  );
}

describe('o corpo do painel do GitHub rola por dentro', () => {
  it('a lista fica dentro da área que rola', () => {
    montar([pull(1), pull(2)]);
    const scroller = document.querySelector('[data-slot="pulls-scroller"]')!;

    expect(scroller).toBeInTheDocument();
    expect(scroller.contains(screen.getByRole('link', { name: 'PR 1' }))).toBe(true);
  });

  it('as abas ficam fora dela, para não rolarem com a lista', () => {
    montar([pull(1)]);
    const scroller = document.querySelector('[data-slot="pulls-scroller"]')!;

    expect(scroller.contains(screen.getByRole('tablist'))).toBe(false);
  });

  it('a gaveta de repositórios também fica fora dela', () => {
    montar([pull(1)]);
    const scroller = document.querySelector('[data-slot="pulls-scroller"]')!;

    expect(scroller.contains(screen.getByText('Repositórios acompanhados'))).toBe(false);
  });

  // Sem altura definida o corpo cresce e quem rola passa a ser o cartão
  // inteiro — as abas sobem junto e somem.
  it('o corpo tem altura definida, em vez de crescer com o conteúdo', () => {
    montar([pull(1)]);
    const scroller = document.querySelector('[data-slot="pulls-scroller"]')!;
    const corpo = scroller.parentElement!;

    expect(corpo.className).toContain('h-full');
    expect(corpo.className).toContain('min-h-0');
    expect(scroller.className).toContain('overflow-y-auto');
    expect(scroller.className).toContain('min-h-0');
  });

  // A barra de rolagem já passou por cima dos controles uma vez, nas notas.
  it('a barra de rolagem tem faixa própria', () => {
    montar([pull(1)]);
    const scroller = document.querySelector('[data-slot="pulls-scroller"]')!;

    expect(scroller.className).toContain('[scrollbar-gutter:stable]');
  });

  // O painel entrava na moldura dentro de uma <div> sem altura, e era ela que
  // quebrava a corrente de alturas até o corpo.
  it('a moldura recebe a seção direto, sem embrulho sem altura', () => {
    const { container } = montar([pull(1)]);

    expect(container.firstElementChild?.tagName).toBe('SECTION');
  });
});
