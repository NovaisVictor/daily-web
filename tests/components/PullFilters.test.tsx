import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, within } from '@testing-library/react';
import { PullFilters } from '@/components/pulls/PullFilters';
import type { PullRequestItem } from '@/lib/types';

const nav = vi.hoisted(() => ({
  search: '',
  replaced: [] as { url: string; options: unknown }[],
  pushed: [] as string[],
  listeners: new Set<() => void>(),
}));

vi.mock('next/navigation', async () => {
  const { useSyncExternalStore } = await import('react');
  const subscribe = (listener: () => void) => {
    nav.listeners.add(listener);
    return () => nav.listeners.delete(listener);
  };
  const go = (url: string) => {
    nav.search = url.split('?')[1] ?? '';
    nav.listeners.forEach((listener) => listener());
  };
  return {
    usePathname: () => '/',
    useRouter: () => ({
      replace: (url: string, options: unknown) => {
        nav.replaced.push({ url, options });
        go(url);
      },
      push: (url: string) => {
        nav.pushed.push(url);
        go(url);
      },
    }),
    useSearchParams: () =>
      new URLSearchParams(useSyncExternalStore(subscribe, () => nav.search)),
  };
});

beforeEach(() => {
  nav.search = '';
  nav.replaced = [];
  nav.pushed = [];
});

afterEach(cleanup);

function pull(over: Partial<PullRequestItem>): PullRequestItem {
  return {
    id: 'PR_1',
    repo: 'joao/daily-web',
    number: 3,
    title: 'Arrumar o build',
    url: 'https://github.com/joao/daily-web/pull/3',
    author: 'joao',
    draft: false,
    awaitingYou: false,
    mine: false,
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
    headRef: null,
    baseRef: null,
    headSha: null,
    ...over,
  };
}

const ITEMS = [
  pull({ repo: 'joao/zeta', number: 1, author: 'maria' }),
  pull({ repo: 'joao/alpha', number: 2, author: 'joao' }),
  pull({ repo: 'joao/alpha', number: 3, author: 'maria' }),
];

const params = () => new URLSearchParams(nav.search);

/** Repo, author and state live behind the "Filtros" trigger. */
const openFilters = () => fireEvent.click(screen.getByRole('button', { name: /^Filtros/ }));

function optionsOf(label: string): string[] {
  const select = screen.getByRole('combobox', { name: label });
  return within(select)
    .getAllByRole('option')
    .map((option) => option.getAttribute('value') ?? '')
    .filter(Boolean);
}

describe('PullFilters', () => {
  it('renders nothing when there is nothing to filter', () => {
    const { container } = render(<PullFilters items={[]} />);
    expect(container).toBeEmptyDOMElement();
  });

  it('keeps the bar when a filter is active over an empty list', () => {
    nav.search = 'pr_state=draft';
    render(<PullFilters items={[]} />);
    expect(screen.getByRole('search', { name: 'filtrar pull requests' })).toBeInTheDocument();
  });

  it('writes the search into the URL', () => {
    render(<PullFilters items={ITEMS} />);
    fireEvent.change(screen.getByRole('searchbox', { name: 'buscar pull requests' }), {
      target: { value: 'TT-42' },
    });
    expect(params().get('pr_q')).toBe('TT-42');
  });

  it('replaces the URL without scrolling instead of pushing history', () => {
    render(<PullFilters items={ITEMS} />);
    openFilters();
    fireEvent.click(screen.getByRole('checkbox', { name: 'Rascunho' }));
    expect(nav.replaced).toEqual([{ url: '/?pr_state=draft', options: { scroll: false } }]);
  });

  it('keeps params owned by other panels', () => {
    nav.search = 'pulls=meus&jiraBusca=x';
    render(<PullFilters items={ITEMS} />);
    openFilters();
    fireEvent.click(screen.getByRole('checkbox', { name: 'Conflito' }));
    expect(nav.search).toBe('pulls=meus&jiraBusca=x&pr_state=conflict');
  });

  it('offers the repos of the items sorted', () => {
    render(<PullFilters items={ITEMS} />);
    openFilters();
    expect(optionsOf('filtrar por repositório')).toEqual(['joao/alpha', 'joao/zeta']);
  });

  it('offers the authors of the items sorted', () => {
    render(<PullFilters items={ITEMS} />);
    openFilters();
    expect(optionsOf('filtrar por autor')).toEqual(['joao', 'maria']);
  });

  it('shows how many pull requests each repo has', () => {
    render(<PullFilters items={ITEMS} />);
    openFilters();
    fireEvent.click(screen.getByRole('button', { name: 'abrir menu filtrar por repositório' }));
    expect(screen.getByRole('checkbox', { name: 'joao/alpha (2)' })).toBeInTheDocument();
  });

  it('adds a second repo to the selection', () => {
    render(<PullFilters items={ITEMS} />);
    openFilters();
    fireEvent.click(screen.getByRole('button', { name: 'abrir menu filtrar por repositório' }));
    fireEvent.click(screen.getByRole('checkbox', { name: 'joao/alpha (2)' }));
    fireEvent.click(screen.getByRole('checkbox', { name: 'joao/zeta (1)' }));
    expect(params().get('pr_repo')).toBe('joao/alpha,joao/zeta');
  });

  it('writes the author selection into the URL', () => {
    render(<PullFilters items={ITEMS} />);
    openFilters();
    fireEvent.change(screen.getByRole('combobox', { name: 'filtrar por autor' }), {
      target: { value: 'maria' },
    });
    expect(params().get('pr_author')).toBe('maria');
  });

  it('turns a state off on the second click', () => {
    nav.search = 'pr_state=draft,stale';
    render(<PullFilters items={ITEMS} />);
    openFilters();
    fireEvent.click(screen.getByRole('checkbox', { name: 'Rascunho' }));
    expect(params().get('pr_state')).toBe('stale');
  });

  it('toggles a state checkbox into the URL', () => {
    render(<PullFilters items={ITEMS} />);
    openFilters();
    fireEvent.click(screen.getByRole('checkbox', { name: 'Aguardando você' }));
    expect(params().get('pr_state')).toBe('awaiting-you');
    expect(screen.getByRole('checkbox', { name: 'Aguardando você' })).toBeChecked();
  });

  it('marks the states read from the URL as checked', () => {
    nav.search = 'pr_state=ci-failing';
    render(<PullFilters items={ITEMS} />);
    openFilters();
    expect(screen.getByRole('checkbox', { name: 'CI falhando' })).toBeChecked();
  });

  it('groups the states by the question they answer', () => {
    render(<PullFilters items={ITEMS} />);
    openFilters();
    const expectStates = (section: string, names: string[]) => {
      const boxes = within(screen.getByRole('region', { name: section })).getAllByRole('checkbox');
      expect(boxes).toHaveLength(names.length);
      boxes.forEach((box, i) => expect(box).toHaveAccessibleName(names[i]));
    };
    expectStates('Revisão', ['Aprovado', 'Mudanças pedidas', 'Aguardando você']);
    expectStates('CI', ['CI falhando']);
    expectStates('Situação', ['Rascunho', 'Conflito', 'Parado há 3+ dias']);
  });

  it('counts the hidden filters on the trigger, leaving the search out', () => {
    nav.search = 'pr_q=x&pr_repo=joao/alpha&pr_state=draft,stale';
    render(<PullFilters items={ITEMS} />);
    expect(screen.getByRole('button', { name: 'Filtros, 3 ativos' })).toBeInTheDocument();
  });

  it('names the trigger without a count when nothing is hidden', () => {
    nav.search = 'pr_q=x';
    render(<PullFilters items={ITEMS} />);
    expect(screen.getByRole('button', { name: 'Filtros, nenhum ativo' })).toBeInTheDocument();
  });

  it('removes one active filter', () => {
    nav.search = 'pr_repo=joao/alpha&pr_state=draft';
    render(<PullFilters items={ITEMS} />);
    fireEvent.click(screen.getByRole('button', { name: 'remover filtro Repositório: joao/alpha' }));
    expect(nav.search).toBe('pr_state=draft');
  });

  it('clears every pull filter and keeps the rest of the URL', () => {
    nav.search = 'pulls=revisoes&pr_q=x&pr_author=maria&pr_state=draft';
    render(<PullFilters items={ITEMS} />);
    fireEvent.click(screen.getByRole('button', { name: /limpar tudo/i }));
    expect(nav.search).toBe('pulls=revisoes');
  });
});
