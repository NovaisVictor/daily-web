'use client';

import { useId, useRef, type KeyboardEvent, type ReactNode } from 'react';
import { Check } from 'lucide-react';
import type { NotePaper, PinColor } from '@/lib/types';
import {
  NOTE_PAPERS,
  PAPER_LABEL,
  PIN_COLORS,
  PIN_LABEL,
  pinClashes,
} from '@/lib/taskBoard';
import { cn } from '@/lib/utils';
import { focusRing } from '@/lib/theme';

export interface NoteStyle {
  paper: NotePaper | null;
  pin: PinColor | null;
}

interface Props {
  value: NoteStyle;
  /** The paper "Automático" stands for right now, from priority and completion. */
  automaticPaper: NotePaper;
  /** Only the colour that changed: the board saves it on its own, so a pick
   *  never sends back a stale value of the other one. */
  onChange: (patch: Partial<NoteStyle>) => void;
  className?: string;
}

const CLASH_HINT = 'pode sumir neste papel';

interface Option<T extends string> {
  value: T | null;
  label: string;
  clashes?: boolean;
}

/**
 * One ARIA radio group: a single tab stop, arrows move and select, the same
 * keys as a native radio set. Buttons rather than inputs, because each option
 * is a swatch and the native control would have to be hidden and redrawn.
 */
function SwatchGroup<T extends string>({
  label,
  options,
  selected,
  onSelect,
  renderSwatch,
}: {
  label: string;
  options: Option<T>[];
  selected: T | null;
  onSelect: (value: T | null) => void;
  renderSwatch: (value: T | null) => ReactNode;
}) {
  const labelId = useId();
  const buttons = useRef<(HTMLButtonElement | null)[]>([]);
  const selectedIndex = Math.max(
    0,
    options.findIndex((o) => o.value === selected),
  );

  const onKeyDown = (event: KeyboardEvent<HTMLButtonElement>, index: number) => {
    const forward = event.key === 'ArrowRight' || event.key === 'ArrowDown';
    const back = event.key === 'ArrowLeft' || event.key === 'ArrowUp';
    if (!forward && !back) return;
    event.preventDefault();
    const target = (index + (forward ? 1 : -1) + options.length) % options.length;
    onSelect(options[target].value);
    buttons.current[target]?.focus();
  };

  return (
    <div className="flex flex-col gap-2">
      <span id={labelId} className="text-sm text-ink-mid">
        {label}
      </span>
      <div role="radiogroup" aria-labelledby={labelId} className="flex flex-wrap items-center gap-1">
        {options.map((option, index) => {
          const checked = index === selectedIndex;
          return (
            <button
              key={option.value ?? 'auto'}
              ref={(node) => {
                buttons.current[index] = node;
              }}
              type="button"
              role="radio"
              aria-checked={checked}
              aria-label={option.clashes ? `${option.label}, ${CLASH_HINT}` : option.label}
              title={option.clashes ? `${option.label}: ${CLASH_HINT}` : option.label}
              tabIndex={checked ? 0 : -1}
              data-clash={option.clashes || undefined}
              className={cn('colour-swatch', focusRing)}
              onClick={() => onSelect(option.value)}
              onKeyDown={(event) => onKeyDown(event, index)}
            >
              {renderSwatch(option.value)}
              {checked && <Check className="colour-swatch-check" aria-hidden="true" />}
            </button>
          );
        })}
      </div>
    </div>
  );
}

/**
 * The paper and pin of one note, each starting with "Automático". Shared by
 * the board and list menus, which save each pick at once, and by the task
 * form, which saves on "Salvar".
 */
export function NoteColourPicker({ value, automaticPaper, onChange, className }: Props) {
  const paper = value.paper ?? automaticPaper;
  const clashingPin = value.pin !== null && pinClashes(value.pin, paper) ? value.pin : null;

  const paperOptions: Option<NotePaper>[] = [
    { value: null, label: `Papel automático (${PAPER_LABEL[automaticPaper]})` },
    ...NOTE_PAPERS.map((c) => ({ value: c, label: `Papel ${PAPER_LABEL[c]}` })),
  ];
  const pinOptions: Option<PinColor>[] = [
    { value: null, label: 'Alfinete automático' },
    ...PIN_COLORS.map((c) => ({
      value: c,
      label: `Alfinete ${PIN_LABEL[c]}`,
      clashes: pinClashes(c, paper),
    })),
  ];

  return (
    <div className={cn('flex flex-col gap-4', className)}>
      <SwatchGroup
        label="Papel"
        options={paperOptions}
        selected={value.paper}
        onSelect={(next) => onChange({ paper: next })}
        renderSwatch={(c) => (
          <span
            className="paper-swatch"
            data-paper={c ?? automaticPaper}
            data-auto={c === null || undefined}
            aria-hidden="true"
          >
            {c === null && 'A'}
          </span>
        )}
      />
      <div className="flex flex-col gap-1.5">
        <SwatchGroup
          label="Alfinete"
          options={pinOptions}
          selected={value.pin}
          onSelect={(next) => onChange({ pin: next })}
          renderSwatch={(c) =>
            c === null ? (
              <span className="pin-swatch" data-auto aria-hidden="true">
                A
              </span>
            ) : (
              <span className="pin-swatch" data-pin={c} aria-hidden="true" />
            )
          }
        />
        <p className={cn('type-caption', clashingPin ? 'text-warning' : 'text-ink-dim')}>
          {clashingPin
            ? `O alfinete ${PIN_LABEL[clashingPin]} ${CLASH_HINT}.`
            : 'Automático evita o alfinete que some no papel.'}
        </p>
      </div>
    </div>
  );
}
