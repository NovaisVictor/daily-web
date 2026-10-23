'use client';

import { useId, useRef, useState, type FormEvent } from 'react';
import type { TaskPriority, TodoTask } from '@/lib/types';
import { parseDueInput } from '@/lib/dateParsing';
import { focusRing, selectClass } from '@/lib/theme';
import { cn } from '@/lib/utils';
import { ChevronRight } from 'lucide-react';
import { useConfirm } from '@/components/data/ConfirmDialog';
import { NoteColourPicker, type NoteStyle } from '@/components/tasks/NoteColourPicker';
import { readErrorMessage } from '@/components/tasks/readErrorMessage';
import { derivedPaper } from '@/lib/taskBoard';
import { Button } from './ui/button';
import { Chip } from './ui/Chip';
import { Input } from './ui/input';
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from './ui/dialog';

interface Props {
  task: TodoTask | null;
  onClose: () => void;
  /** `styleError` when the task was saved but its note colour was not. */
  onSaved: (styleError?: string) => void;
  onDeleted: (id: string) => void;
}

type Recur = 'none' | 'daily' | 'weekly' | 'monthly';

const RECUR_OPTIONS: { value: Recur; label: string }[] = [
  { value: 'none', label: 'Não repete' },
  { value: 'daily', label: 'Diária' },
  { value: 'weekly', label: 'Semanal' },
  { value: 'monthly', label: 'Mensal' },
];

// Strongest first: the order a person scans for "how urgent is this".
const PRIORITY_OPTIONS: { value: TaskPriority; label: string }[] = [
  { value: 'high', label: 'Alta' },
  { value: 'normal', label: 'Normal' },
  { value: 'low', label: 'Baixa' },
];

const WEEKDAYS = ['dom', 'seg', 'ter', 'qua', 'qui', 'sex', 'sáb'];
const ISO_DAY_RE = /^\d{4}-\d{2}-\d{2}$/;
const TIME_RE = /^\d{2}:\d{2}$/;
const TITLE_MAX = 255;

function initialRecur(task: TodoTask | null): Recur {
  if (task?.recur === 'daily' || task?.recur === 'weekly') return task.recur;
  // The local store writes 'monthly' and Microsoft To Do reports
  // 'absoluteMonthly'; recognising only the latter made every local monthly
  // task open as "Não repete" and lose its recurrence on save.
  if (task?.recur === 'monthly' || task?.recur === 'absoluteMonthly') return 'monthly';
  return 'none';
}

// Local getters, not toISOString: "today" must be the user's calendar day,
// the same rule lib/dateParsing.ts and lib/taskGrouping.ts follow.
function localIso(date: Date): string {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

function shiftDays(date: Date, days: number): Date {
  const next = new Date(date);
  next.setDate(next.getDate() + days);
  return next;
}

// "Next week" means the coming Monday, so a task picked on a Friday lands on
// the start of the next working week rather than the following Friday.
function nextMonday(date: Date): Date {
  const untilMonday = ((8 - date.getDay()) % 7) || 7;
  return shiftDays(date, untilMonday);
}

// parseDueInput throws on text it does not understand; here that is an
// expected state of a field being typed, rendered as an inline message.
function tryParseDue(text: string, now: Date): { day: string; time: string } | null {
  try {
    const parsed = parseDueInput(text, now);
    return { day: parsed.due, time: parsed.time === 'none' ? '' : parsed.time };
  } catch {
    return null;
  }
}

function describeDue(day: string, time: string): string {
  const [year, month, date] = day.split('-').map(Number);
  const weekday = WEEKDAYS[new Date(year, month - 1, date).getDay()];
  const label = `${weekday}, ${String(date).padStart(2, '0')}/${String(month).padStart(2, '0')}`;
  return time ? `${label} ${time}` : label;
}

export function TaskFormModal({ task, onClose, onSaved, onDeleted }: Props) {
  const ids = useId();
  const titleId = `${ids}-title`;
  const titleErrorId = `${ids}-title-error`;
  const typedId = `${ids}-typed`;
  const typedHintId = `${ids}-typed-hint`;
  const recurHintId = `${ids}-recur-hint`;

  // Stored values are only trusted when they have the shape the inputs take;
  // anything else opens as "no date" instead of a broken native input.
  // A stored recurrence without a date opens as "Não repete", the same value
  // the disabled select shows and the save sends.
  const [initial] = useState(() => {
    const day = task?.due && ISO_DAY_RE.test(task.due) ? task.due : '';
    return {
      title: task?.title ?? '',
      day,
      time: day && task?.time && TIME_RE.test(task.time) ? task.time : '',
      recur: day ? initialRecur(task) : ('none' as Recur),
      priority: task?.priority ?? ('normal' as TaskPriority),
      style: { paper: task?.paper ?? null, pin: task?.pin ?? null } as NoteStyle,
    };
  });

  const [title, setTitle] = useState(initial.title);
  const [day, setDayState] = useState(initial.day);
  const [time, setTime] = useState(initial.time);
  const [recur, setRecur] = useState<Recur>(initial.recur);
  const [priority, setPriority] = useState<TaskPriority>(initial.priority);
  const [style, setStyle] = useState<NoteStyle>(initial.style);
  const [typing, setTyping] = useState(false);
  const [typed, setTyped] = useState('');
  const [titleError, setTitleError] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const [deleting, setDeleting] = useState(false);
  const titleRef = useRef<HTMLInputElement>(null);
  const typedRef = useRef<HTMLInputElement>(null);
  // Two quick submits fire twice before the state renders; the ref blocks the
  // second call at once, the state takes care of the button.
  const enviando = useRef(false);
  const { confirm, dialog } = useConfirm();
  // Radix hands focus back to a DialogTrigger on close, and this dialog has
  // none: it is mounted by whoever opens it. So the opener is remembered here.
  const [opener] = useState(() =>
    document.activeElement instanceof HTMLElement ? document.activeElement : null,
  );

  // A recurring task without a date is completed for good instead of coming
  // back, so the recurrence only counts while there is a date.
  const effectiveRecur: Recur = day ? recur : 'none';
  const busy = saving || deleting;

  const now = new Date();
  const today = localIso(now);
  const tomorrow = localIso(shiftDays(now, 1));
  const monday = localIso(nextMonday(now));

  const typedParsed = typed.trim() ? tryParseDue(typed, now) : null;
  const typedPreview = typedParsed ? describeDue(typedParsed.day, typedParsed.time) : null;
  const typedError =
    typed.trim() && !typedParsed
      ? `Não reconheci "${typed.trim()}". Exemplos: hoje, amanhã 14:30, +3d, 2026-11-05 09:00.`
      : null;

  const styleChanged = style.paper !== initial.style.paper || style.pin !== initial.style.pin;
  const dirty =
    styleChanged ||
    title !== initial.title ||
    day !== initial.day ||
    time !== initial.time ||
    effectiveRecur !== initial.recur ||
    priority !== initial.priority ||
    typed.trim() !== '';

  const setDay = (next: string) => {
    setDayState(next);
    // A time without a day means nothing to the API, so it goes with the day.
    if (!next) setTime('');
  };

  const onTypedChange = (value: string) => {
    setTyped(value);
    // While the text does not parse, the date fields keep their last valid
    // value and the inline message says what is wrong.
    const parsed = value.trim() ? tryParseDue(value, now) : null;
    if (parsed) {
      setDayState(parsed.day);
      setTime(parsed.time);
    }
  };

  const requestClose = async () => {
    if (busy) return;
    if (dirty) {
      const discard = await confirm({
        title: 'Descartar as alterações?',
        description: 'O que você mudou nesta tarefa ainda não foi salvo.',
        confirmLabel: 'Descartar',
        cancelLabel: 'Continuar editando',
        destructive: true,
      });
      if (!discard) return;
    }
    onClose();
  };

  const save = async (event: FormEvent) => {
    event.preventDefault();
    if (enviando.current) return;
    if (!title.trim()) {
      setTitleError('Dê um título à tarefa.');
      titleRef.current?.focus();
      return;
    }
    if (typedError) {
      typedRef.current?.focus();
      return;
    }
    const due = day ? (time ? `${day} ${time}` : day) : '';
    enviando.current = true;
    setSaving(true);
    setError(null);
    try {
      const res = task
        ? await fetch(`/api/tasks/${encodeURIComponent(task.id)}`, {
            method: 'PATCH',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ title: title.trim(), due, priority, recur: effectiveRecur }),
          })
        : await fetch('/api/tasks', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
              title: title.trim(),
              due,
              priority,
              recur: effectiveRecur === 'none' ? undefined : effectiveRecur,
            }),
          });
      if (!res.ok) {
        const data = await res.json().catch(() => ({}));
        setError(data.error ?? 'Não foi possível salvar. Tente de novo.');
        return;
      }
      if (!styleChanged) {
        onSaved();
        return;
      }
      // A separate request, and only after the task is saved: the colour
      // lives in this app's database while the task may live in Microsoft To
      // Do, and one request doing both would have no clear meaning when only
      // half of it failed. A new task's id comes back from the create.
      // The task exists now whatever happens next, so the form closes even
      // when the colour fails; staying open would make "Salvar" create the
      // task a second time.
      let styleError: string | undefined;
      try {
        const id = task ? task.id : ((await res.json()) as { id: string }).id;
        const styleRes = await fetch(`/api/tasks/${encodeURIComponent(id)}/board`, {
          method: 'PATCH',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(style),
        });
        if (!styleRes.ok) styleError = await readErrorMessage(styleRes, 'erro ao salvar a cor');
      } catch {
        styleError = 'verifique a conexão e escolha a cor de novo';
      }
      onSaved(styleError);
    } catch {
      setError('Não foi possível salvar. Verifique a conexão e tente de novo.');
    } finally {
      // Released even on failure: the person has to be able to retry.
      enviando.current = false;
      setSaving(false);
    }
  };

  const remove = async () => {
    if (!task || busy) return;
    const ok = await confirm({
      title: 'Apagar a tarefa?',
      description: `"${task.title}" será removida. Isso não tem volta.`,
      confirmLabel: 'Apagar',
      destructive: true,
    });
    if (!ok) return;
    setDeleting(true);
    setError(null);
    try {
      const res = await fetch(`/api/tasks/${encodeURIComponent(task.id)}`, { method: 'DELETE' });
      if (!res.ok) {
        const data = await res.json().catch(() => ({}));
        setError(data.error ?? 'Não foi possível apagar. Tente de novo.');
        return;
      }
      onDeleted(task.id);
    } catch {
      setError('Não foi possível apagar. Verifique a conexão e tente de novo.');
    } finally {
      setDeleting(false);
    }
  };

  const labelClass = 'text-sm text-ink-mid';
  const fieldSelect = cn(selectClass, focusRing, 'h-9 w-full border-line-strong disabled:cursor-not-allowed disabled:opacity-50');

  return (
    <>
      <Dialog open onOpenChange={(open) => !open && void requestClose()}>
        <DialogContent
          aria-describedby={undefined}
          // Not `autoFocus` on the title: React focuses it during commit,
          // before Radix records the element to return focus to, and focus
          // then fell to <body> on close instead of back on the opener.
          onOpenAutoFocus={(event) => {
            event.preventDefault();
            titleRef.current?.focus();
          }}
          onCloseAutoFocus={(event) => {
            event.preventDefault();
            opener?.focus();
          }}
          className="max-h-[88dvh] overflow-y-auto sm:max-w-[480px]"
        >
          <DialogHeader className="text-left">
            <DialogTitle className="type-subhead">{task ? 'Editar tarefa' : 'Nova tarefa'}</DialogTitle>
          </DialogHeader>

          <form noValidate onSubmit={(event) => void save(event)} className="flex flex-col gap-5">
            <div className="flex flex-col gap-2">
              <label htmlFor={titleId} className={labelClass}>
                Título
              </label>
              <Input
                id={titleId}
                ref={titleRef}
                value={title}
                maxLength={TITLE_MAX}
                placeholder="O que precisa ser feito?"
                aria-invalid={titleError ? true : undefined}
                aria-describedby={titleError ? titleErrorId : undefined}
                onChange={(event) => {
                  setTitle(event.target.value);
                  if (titleError) setTitleError(null);
                }}
              />
              {titleError && (
                <p id={titleErrorId} className="text-sm text-danger">
                  {titleError}
                </p>
              )}
            </div>

            <fieldset className="flex flex-col gap-3">
              <legend className={cn(labelClass, 'mb-2')}>Data</legend>
              <div className="flex flex-wrap gap-2">
                <Chip active={day === today} onClick={() => setDay(today)}>
                  Hoje
                </Chip>
                <Chip active={day === tomorrow} onClick={() => setDay(tomorrow)}>
                  Amanhã
                </Chip>
                <Chip active={day === monday && day !== tomorrow} onClick={() => setDay(monday)}>
                  Próx. semana
                </Chip>
                <Chip active={day === ''} onClick={() => setDay('')}>
                  Sem data
                </Chip>
              </div>
              <div className="grid grid-cols-2 gap-3">
                <label className="flex flex-col gap-1.5">
                  <span className="type-caption text-ink-dim">Dia</span>
                  <Input type="date" value={day} onChange={(event) => setDay(event.target.value)} />
                </label>
                <label className="flex flex-col gap-1.5">
                  <span className="type-caption text-ink-dim">Hora</span>
                  <Input
                    type="time"
                    value={time}
                    disabled={!day}
                    onChange={(event) => setTime(event.target.value)}
                  />
                </label>
              </div>

              <div className="flex flex-col gap-2">
                <button
                  type="button"
                  aria-expanded={typing}
                  aria-controls={typedId}
                  onClick={() => {
                    if (typing) setTyped('');
                    setTyping(!typing);
                  }}
                  className={cn(
                    'inline-flex items-center gap-1 self-start rounded-sm text-sm text-ink-mid hover:text-ink',
                    focusRing,
                  )}
                >
                  <ChevronRight
                    aria-hidden
                    className={cn('size-4 transition-transform motion-reduce:transition-none', typing && 'rotate-90')}
                  />
                  Digitar data
                </button>
                {typing && (
                  <div className="flex flex-col gap-1.5">
                    <label htmlFor={typedId} className="sr-only">
                      Data em texto
                    </label>
                    <Input
                      id={typedId}
                      ref={typedRef}
                      value={typed}
                      autoFocus
                      placeholder="amanhã 14:30"
                      aria-invalid={typedError ? true : undefined}
                      aria-describedby={typedHintId}
                      onChange={(event) => onTypedChange(event.target.value)}
                    />
                    <p
                      id={typedHintId}
                      aria-live="polite"
                      className={cn('type-caption', typedError ? 'text-danger' : 'text-ink-dim')}
                    >
                      {typedError ??
                        (typedPreview ? `→ ${typedPreview}` : 'hoje, amanhã, +3d ou AAAA-MM-DD, com hora opcional no fim')}
                    </p>
                  </div>
                )}
              </div>
            </fieldset>

            <div className="grid gap-4 sm:grid-cols-2">
              <label className="flex flex-col gap-2">
                <span className={labelClass}>Prioridade</span>
                <select
                  className={fieldSelect}
                  value={priority}
                  onChange={(event) => setPriority(event.target.value as TaskPriority)}
                >
                  {PRIORITY_OPTIONS.map((option) => (
                    <option key={option.value} value={option.value}>
                      {option.label}
                    </option>
                  ))}
                </select>
              </label>
              <div className="flex flex-col gap-2">
                <label className="flex flex-col gap-2">
                  <span className={labelClass}>Repetição</span>
                  <select
                    className={fieldSelect}
                    value={effectiveRecur}
                    disabled={!day}
                    aria-describedby={!day ? recurHintId : undefined}
                    onChange={(event) => setRecur(event.target.value as Recur)}
                  >
                    {RECUR_OPTIONS.map((option) => (
                      <option key={option.value} value={option.value}>
                        {option.label}
                      </option>
                    ))}
                  </select>
                </label>
                {!day && (
                  <p id={recurHintId} className="type-caption text-ink-dim">
                    Defina uma data para repetir.
                  </p>
                )}
              </div>
            </div>

            <fieldset className="flex flex-col">
              <legend className={cn(labelClass, 'mb-2')}>Cor da nota</legend>
              <NoteColourPicker
                value={style}
                automaticPaper={derivedPaper({ completed: task?.completed ?? false, priority })}
                onChange={(patch) => setStyle((current) => ({ ...current, ...patch }))}
              />
            </fieldset>

            {error && (
              <p role="alert" className="text-sm text-danger">
                {error}
              </p>
            )}

            <DialogFooter className="mt-1 flex-row items-center justify-end sm:justify-end">
              {task && (
                <Button
                  type="button"
                  variant="ghost"
                  className="mr-auto px-3 text-danger hover:text-danger"
                  onClick={() => void remove()}
                  disabled={busy}
                >
                  {deleting ? 'Apagando…' : 'Apagar'}
                </Button>
              )}
              <Button type="button" variant="outline" onClick={onClose} disabled={busy}>
                Cancelar
              </Button>
              <Button type="submit" disabled={busy}>
                {saving ? 'Salvando…' : 'Salvar'}
              </Button>
            </DialogFooter>
          </form>
        </DialogContent>
      </Dialog>
      {dialog}
    </>
  );
}
