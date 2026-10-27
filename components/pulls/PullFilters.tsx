'use client';

import { useMemo } from 'react';
import { usePathname, useRouter, useSearchParams } from 'next/navigation';
import { JiraMultiFilterDropdown } from '@/components/JiraMultiFilterDropdown';
import { ActiveFilters } from '@/components/ui/ActiveFilters';
import { Checkbox } from '@/components/ui/checkbox';
import { FilterBar } from '@/components/ui/FilterBar';
import { FilterPopover, FilterPopoverSection } from '@/components/ui/FilterPopover';
import { SearchInput } from '@/components/ui/SearchInput';
import type { ActiveFilter } from '@/lib/filters';
import {
  EMPTY_PULL_FILTERS,
  PULL_STATE_LABEL,
  hasPullFilters,
  parsePullFilters,
  pullFilterOptions,
  pullFiltersToParams,
  type PullFilterGroup,
  type PullFilterOption,
  type PullFilterState,
  type PullState,
} from '@/lib/pullFilters';
import type { PullRequestItem } from '@/lib/types';

function groupLabel(name: string, group: PullFilterGroup): string {
  const sign = group.mode === 'exclude' ? ' ≠' : ':';
  return `${name}${sign} ${group.values.join(', ')}`;
}

// The seven states answer three different questions; grouped by question, a
// reader scans for the one they have instead of reading all seven.
const STATE_GROUPS: { title: string; states: PullState[] }[] = [
  { title: 'Revisão', states: ['approved', 'changes-requested', 'awaiting-you'] },
  { title: 'CI', states: ['ci-failing'] },
  { title: 'Situação', states: ['draft', 'conflict', 'stale'] },
];

const asOptions = (options: PullFilterOption[]) =>
  options.map((option) => ({
    value: option.value,
    label: `${option.value} (${option.count})`,
  }));

export function PullFilters({ items }: { items: PullRequestItem[] }) {
  const searchParams = useSearchParams();
  const router = useRouter();
  const pathname = usePathname();
  const filtros = useMemo(
    () => parsePullFilters(new URLSearchParams(searchParams.toString())),
    [searchParams],
  );
  const opcoes = useMemo(() => pullFilterOptions(items), [items]);

  // Filtro é refinamento, não navegação: substitui a URL para o voltar não
  // refazer cada tecla da busca.
  const setFiltros = (next: Partial<PullFilterState>) => {
    const params = pullFiltersToParams(
      new URLSearchParams(searchParams.toString()),
      { ...filtros, ...next },
    );
    const query = params.toString();
    router.replace(query ? `${pathname}?${query}` : pathname, { scroll: false });
  };

  const toggleState = (state: PullState) =>
    setFiltros({
      state: filtros.state.includes(state)
        ? filtros.state.filter((s) => s !== state)
        : [...filtros.state, state],
    });

  if (items.length === 0 && !hasPullFilters(filtros)) return null;

  const activeFilters: ActiveFilter[] = [
    ...(filtros.query.trim() ? [{ id: 'query', label: `Busca: ${filtros.query.trim()}` }] : []),
    ...(filtros.repo.values.length > 0
      ? [{ id: 'repo', label: groupLabel('Repositório', filtros.repo) }]
      : []),
    ...(filtros.author.values.length > 0
      ? [{ id: 'author', label: groupLabel('Autor', filtros.author) }]
      : []),
    ...filtros.state.map((state) => ({ id: `state:${state}`, label: PULL_STATE_LABEL[state] })),
  ];

  // The search is in plain sight; the badge counts only what the panel hides.
  const secondaryCount = activeFilters.filter((f) => f.id !== 'query').length;

  const clearFilter = (id: string) => {
    if (id === 'query') return setFiltros({ query: '' });
    if (id === 'repo') return setFiltros({ repo: EMPTY_PULL_FILTERS.repo });
    if (id === 'author') return setFiltros({ author: EMPTY_PULL_FILTERS.author });
    if (id.startsWith('state:')) {
      setFiltros({ state: filtros.state.filter((s) => `state:${s}` !== id) });
    }
  };

  return (
    <div className="pt-3">
      <FilterBar label="filtrar pull requests">
        <SearchInput
          value={filtros.query}
          onChange={(query) => setFiltros({ query })}
          label="buscar pull requests"
          placeholder="título, repo#número, autor, card"
        />
        {/* Repo and author keep their own dropdown inside the panel: it brings
            the include/exclude mode and the option search, and Radix stacks
            the nested popover as a child layer, so picking an option does not
            close the panel around it. */}
        <FilterPopover label="filtros de pull requests" count={secondaryCount}>
          <FilterPopoverSection title="Repositório">
            <JiraMultiFilterDropdown
              label="filtrar por repositório"
              title="Filtrar por repositório"
              placeholder="Todos os repositórios"
              filter={filtros.repo}
              options={asOptions(opcoes.repos)}
              onChange={(repo) => setFiltros({ repo })}
            />
          </FilterPopoverSection>
          <FilterPopoverSection title="Autor">
            <JiraMultiFilterDropdown
              label="filtrar por autor"
              title="Filtrar por autor"
              placeholder="Todos os autores"
              filter={filtros.author}
              options={asOptions(opcoes.authors)}
              onChange={(author) => setFiltros({ author })}
            />
          </FilterPopoverSection>
          {STATE_GROUPS.map((group) => (
            <FilterPopoverSection key={group.title} title={group.title} className="flex-col items-start gap-1">
              {group.states.map((state) => (
                <label key={state} className="flex cursor-pointer items-center gap-2 text-sm text-ink">
                  <Checkbox
                    checked={filtros.state.includes(state)}
                    onCheckedChange={() => toggleState(state)}
                  />
                  {PULL_STATE_LABEL[state]}
                </label>
              ))}
            </FilterPopoverSection>
          ))}
        </FilterPopover>
      </FilterBar>
      <ActiveFilters
        filters={activeFilters}
        onRemove={clearFilter}
        onClearAll={() => setFiltros(EMPTY_PULL_FILTERS)}
      />
    </div>
  );
}
