/**
 * The pill switch of the tasks panel. The "Lista / Quadro" toggle marks its
 * choice with aria-pressed and the board's column tabs with aria-selected, and
 * both must look like the same control.
 */
export const segmentedGroup =
  'inline-flex items-center gap-0.5 rounded-full border border-line-strong bg-surface-2 p-0.5 shadow-e1';

export const segmentedItem =
  'inline-flex h-7 items-center gap-1.5 rounded-full px-2.5 text-sm text-ink-mid transition-colors duration-100 ease-brand hover:text-ink aria-pressed:bg-brand-tint aria-pressed:text-ink aria-pressed:shadow-control aria-selected:bg-brand-tint aria-selected:text-ink aria-selected:shadow-control motion-reduce:transition-none';
