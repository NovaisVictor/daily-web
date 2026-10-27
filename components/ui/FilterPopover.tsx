'use client';

import { useId, type ReactNode } from 'react';
import { SlidersHorizontal } from 'lucide-react';
import { Popover, PopoverContent, PopoverTrigger } from './popover';
import { cn } from '@/lib/utils';
import { focusRing, tabular } from '@/lib/theme';

function countLabel(count: number): string {
  if (count === 0) return 'nenhum ativo';
  return count === 1 ? '1 ativo' : `${count} ativos`;
}

/**
 * The secondary filters of a panel behind one trigger. A row of six dropdowns
 * and seven chips wrapped into three lines on a card; the search stays out,
 * this holds the rest, and the count on the trigger says something is hidden
 * here while ActiveFilters below the bar says what.
 */
export function FilterPopover({
  label,
  count,
  children,
}: {
  /** Names the open panel for screen readers, e.g. "filtros do Jira". */
  label: string;
  /** How many secondary filters are on. Only non-defaults count. */
  count: number;
  children: ReactNode;
}) {
  return (
    <Popover>
      <PopoverTrigger
        aria-label={`Filtros, ${countLabel(count)}`}
        className={cn(
          'inline-flex h-8 shrink-0 items-center gap-2 rounded-full border px-3.5 text-sm whitespace-nowrap transition-colors duration-100 ease-brand motion-reduce:transition-none',
          focusRing,
          count > 0
            ? 'border-brand-edge bg-brand-tint text-ink shadow-control'
            : 'border-line-strong bg-surface-2 text-ink-mid shadow-e1 hover:bg-accent hover:text-accent-foreground',
        )}
      >
        <SlidersHorizontal aria-hidden className="size-4 shrink-0" />
        Filtros
        {count > 0 && (
          <span
            aria-hidden
            className={cn(
              'inline-flex min-w-5 items-center justify-center rounded-full bg-brand px-1.5 text-[11px] leading-5 font-semibold text-brand-ink',
              tabular,
            )}
          >
            {count}
          </span>
        )}
      </PopoverTrigger>
      <PopoverContent
        align="start"
        sideOffset={6}
        aria-label={label}
        className="flex max-h-(--radix-popover-content-available-height) w-80 max-w-[calc(100vw-2rem)] flex-col gap-4 overflow-y-auto p-4"
      >
        {children}
      </PopoverContent>
    </Popover>
  );
}

/** A labelled block inside FilterPopover: the heading names the region. */
export function FilterPopoverSection({
  title,
  children,
  className,
}: {
  title: string;
  children: ReactNode;
  className?: string;
}) {
  const id = useId();
  return (
    <section aria-labelledby={id} className="flex flex-col gap-2">
      <h3 id={id} className="type-caption font-medium text-ink-dim">
        {title}
      </h3>
      <div className={cn('flex flex-wrap items-center gap-2', className)}>{children}</div>
    </section>
  );
}
