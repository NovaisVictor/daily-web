'use client';

import { useId, useMemo, useState } from 'react';
import { ChevronDown, Search, X } from 'lucide-react';
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover';
import { Checkbox } from '@/components/ui/checkbox';
import { selectClass } from '@/lib/theme';
import { cn } from '@/lib/utils';
import type { FilterMode, JiraFilterGroup } from '@/lib/jiraFilters';

export interface JiraMultiFilterOption<T extends string = string> {
  value: T;
  label: string;
  secondary?: string;
}

interface Props<T extends string = string> {
  label: string;
  title: string;
  placeholder: string;
  filter: JiraFilterGroup<T>;
  options: JiraMultiFilterOption<T>[];
  onChange: (next: JiraFilterGroup<T>) => void;
  formatLabel?: (value: T) => string;
  className?: string;
}

export function JiraMultiFilterDropdown<T extends string = string>({
  label,
  title,
  placeholder,
  filter,
  options,
  onChange,
  formatLabel,
  className,
}: Props<T>) {
  const [open, setOpen] = useState(false);
  const [search, setSearch] = useState('');
  const selectId = useId();

  // Garante que valores já selecionados apareçam na lista mesmo que o conjunto
  // de opções da aba no momento não os inclua.
  const allOptions = useMemo(() => {
    const list = [...options];
    for (const val of filter.values) {
      if (!list.some((o) => o.value === val)) {
        list.unshift({
          value: val,
          label: formatLabel ? formatLabel(val) : val,
        });
      }
    }
    return list;
  }, [options, filter.values, formatLabel]);

  const filteredOptions = useMemo(() => {
    const q = search.trim().toLowerCase();
    if (!q) return allOptions;
    return allOptions.filter(
      (o) => o.label.toLowerCase().includes(q) || (o.secondary && o.secondary.toLowerCase().includes(q)),
    );
  }, [allOptions, search]);

  const toggle = (val: T) => {
    const exists = filter.values.includes(val);
    const nextValues = exists
      ? filter.values.filter((v) => v !== val)
      : [...filter.values, val];
    onChange({ values: nextValues, mode: filter.mode });
  };

  const setMode = (mode: FilterMode) => {
    onChange({ values: filter.values, mode });
  };

  const clear = () => {
    onChange({ values: [], mode: filter.mode });
  };

  const isExclude = filter.mode === 'exclude';
  const hasValues = filter.values.length > 0;

  // Texto resumido do gatilho
  let triggerText = placeholder;
  if (filter.values.length === 1) {
    const opt = allOptions.find((o) => o.value === filter.values[0]);
    triggerText = opt?.label ?? (formatLabel ? formatLabel(filter.values[0]) : filter.values[0]);
  } else if (filter.values.length > 1) {
    triggerText = `${filter.values.length} selecionados`;
  }

  return (
    <div className={cn('relative inline-flex items-center', className)}>
      {/* Controle nativo acessível em segundo plano: mantém compatibilidade
          completa com testes e leitores de tela sem exigir cliques adicionais */}
      <select
        id={selectId}
        aria-label={label}
        className="sr-only"
        tabIndex={-1}
        value={filter.values[0] ?? ''}
        onChange={(e) => {
          const val = e.target.value as T;
          if (!val) {
            onChange({ values: [], mode: filter.mode });
          } else {
            onChange({ values: [val], mode: filter.mode });
          }
        }}
      >
        <option value="">{placeholder}</option>
        {allOptions.map((opt) => (
          <option key={opt.value} value={opt.value}>
            {opt.label}
          </option>
        ))}
      </select>

      <Popover open={open} onOpenChange={setOpen}>
        <PopoverTrigger asChild>
          <button
            type="button"
            aria-label={`abrir menu ${label}`}
            className={cn(
              selectClass,
              'inline-flex items-center gap-1.5 text-left transition-colors cursor-pointer',
              hasValues && (isExclude ? 'border-danger/40 bg-danger-tint/30 text-ink' : 'border-brand/40 bg-brand-tint/30 text-ink'),
            )}
          >
            {hasValues && (
              <span
                className={cn(
                  'rounded px-1 text-[11px] font-bold leading-none shrink-0',
                  isExclude ? 'bg-danger text-white' : 'bg-brand text-brand-ink',
                )}
                title={isExclude ? 'Modo: não é igual a (exclusão)' : 'Modo: é igual a (inclusão)'}
              >
                {isExclude ? '≠' : '='}
              </span>
            )}
            <span className={cn('truncate max-w-44 text-xs', !hasValues && 'text-ink-dim')}>
              {triggerText}
            </span>
            <ChevronDown className="size-3.5 shrink-0 text-ink-dim" />
          </button>
        </PopoverTrigger>

        <PopoverContent align="start" className="w-72 p-3 text-xs" sideOffset={6}>
          <div className="flex items-center justify-between pb-2 mb-2 border-b border-line-soft">
            <span className="font-semibold text-ink">{title}</span>
            {hasValues && (
              <button
                type="button"
                className="text-[11px] text-ink-dim hover:text-danger cursor-pointer transition-colors"
                onClick={clear}
                aria-label={`limpar opções de ${label}`}
              >
                Limpar
              </button>
            )}
          </div>

          {/* Seletor de Modo: É igual a (inclusão) vs Não é igual a (exclusão) */}
          <div className="flex items-center rounded-lg bg-muted/40 p-1 mb-2.5 gap-1 border border-line-soft/50">
            <button
              type="button"
              className={cn(
                'flex-1 py-1 px-2 rounded-md transition-colors text-center font-medium text-[11px] cursor-pointer',
                !isExclude ? 'bg-surface-2 text-ink shadow-sm' : 'text-ink-dim hover:text-ink',
              )}
              onClick={() => setMode('include')}
              aria-label={`modo é igual a para ${label}`}
            >
              É igual a (=)
            </button>
            <button
              type="button"
              className={cn(
                'flex-1 py-1 px-2 rounded-md transition-colors text-center font-medium text-[11px] cursor-pointer',
                isExclude ? 'bg-danger text-white shadow-sm' : 'text-ink-dim hover:text-danger',
              )}
              onClick={() => setMode('exclude')}
              aria-label={`modo não é igual a para ${label}`}
            >
              Não é igual a (≠)
            </button>
          </div>

          {/* Busca rápida se houver mais de 5 itens */}
          {allOptions.length > 5 && (
            <div className="relative mb-2">
              <Search className="absolute left-2.5 top-2 size-3 text-ink-dim" />
              <input
                className="w-full rounded-md border border-line-soft bg-surface-1 py-1 pl-7 pr-2 text-xs text-ink outline-none focus:border-brand"
                placeholder="Buscar opção..."
                value={search}
                onChange={(e) => setSearch(e.target.value)}
              />
            </div>
          )}

          {/* Lista de opções com checkboxes */}
          <div className="max-h-52 overflow-y-auto space-y-0.5 pr-0.5">
            {filteredOptions.length === 0 ? (
              <p className="py-3 text-center text-ink-dim text-[11px]">Nenhuma opção encontrada</p>
            ) : (
              filteredOptions.map((opt) => {
                const isSelected = filter.values.includes(opt.value);
                return (
                  <label
                    key={opt.value}
                    className={cn(
                      'flex items-center gap-2 px-2 py-1.5 rounded-md hover:bg-muted/60 cursor-pointer transition-colors',
                      isSelected && (isExclude ? 'bg-danger-tint/40 text-danger' : 'bg-brand-tint/40 text-brand'),
                    )}
                  >
                    <Checkbox
                      checked={isSelected}
                      onCheckedChange={() => toggle(opt.value)}
                      aria-label={opt.label}
                    />
                    <span className="truncate flex-1 text-ink">{opt.label}</span>
                    {opt.secondary && (
                      <span className="font-mono text-[10px] text-ink-dim shrink-0">{opt.secondary}</span>
                    )}
                  </label>
                );
              })
            )}
          </div>

          {/* Rodapé informativo */}
          <div className="pt-2 mt-2 border-t border-line-soft flex items-center justify-between text-[11px] text-ink-dim">
            <span>
              {filter.values.length} de {allOptions.length} selecionados
            </span>
            {isExclude && (
              <span className="text-danger font-medium">Excluindo selecionados</span>
            )}
          </div>
        </PopoverContent>
      </Popover>
    </div>
  );
}
