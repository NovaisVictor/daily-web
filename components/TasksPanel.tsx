'use client';

import { useMemo, useState } from 'react';
import { CalendarPlus, List, Plus, StickyNote } from 'lucide-react';
import { IconAction } from '@/components/data/IconAction';
import { NavArrowRight } from 'iconoir-react';
import type { PanelResult, TaskPriority, TasksView, TodoTask } from '@/lib/types';
import { PanelError } from '@/components/data/PanelError';
import type { ActiveFilter } from '@/lib/filters';
import { matchesQuery } from '@/lib/filters';
import { groupTasksByDueWindow, isOverdue } from '@/lib/taskGrouping';
import type { TaskGroupKey } from '@/lib/taskGrouping';
import { TaskFormModal } from './TaskFormModal';
import { Section } from './ui/Section';
import { FilterBar } from './ui/FilterBar';
import { SearchInput } from './ui/SearchInput';
import { Chip } from './ui/Chip';
import { ActiveFilters } from './ui/ActiveFilters';
import { EmptyState } from '@/components/data/EmptyState';
import { useConfirm } from '@/components/data/ConfirmDialog';
import { SkeletonRows } from './ui/legacy-skeleton';
import { Button } from './ui/button';
import { GLYPH } from './data/Status';
import { cn } from '@/lib/utils';
import { focusRing, tabular } from '@/lib/theme';
import { FOCUS_DRAG_TYPE, type FocusSource } from '@/lib/focusBlock';
import { useFocusBlock } from '@/components/FocusBlockProvider';
import { TaskBoard } from '@/components/tasks/TaskBoard';
import { SubtaskList } from '@/components/tasks/SubtaskList';
import { TaskActionsMenu } from '@/components/tasks/TaskActionsMenu';
import { segmentedGroup, segmentedItem } from '@/components/tasks/segmented';
import { readErrorMessage } from '@/components/tasks/readErrorMessage';
import { PAPER_LABEL, PIN_LABEL, columnLabel, planMove, type BoardColumn } from '@/lib/taskBoard';
import type { NoteStyle } from '@/components/tasks/NoteColourPicker';

/** A failing integration is information, not an alarm: contained block, side marker. */

// 24px: the smallest target WCAG 2.5.8 accepts; at 18px the arrow was easy to miss.
const caret =
  'inline-flex size-6 shrink-0 items-center justify-center rounded-md text-ink-dim transition-transform duration-100 ease-brand hover:bg-muted hover:text-ink aria-expanded:rotate-90 motion-reduce:transition-none';

const flagPill =
  'inline-flex shrink-0 items-center gap-1 rounded-full border px-2 py-0.5 type-caption';
const neutralFlag = 'border-line-strong bg-neutral-tint text-ink-dim';
// "Fazendo" is a board column, but the list must show it too: otherwise a
// task in progress looks exactly like one nobody started.
const doingFlag = 'border-info/40 bg-info-tint text-info';

/**
 * Priority is a state, so it carries a glyph and a word beside the hue and never
 * the accent: an accent-tinted flag would change colour with the theme while the
 * task's urgency stayed exactly the same.
 */
const PRIORITY_TONE: Record<TaskPriority, { glyph: string; tone: string }> = {
  high: { glyph: GLYPH.alert, tone: 'border-warning/45 bg-warning-tint text-warning' },
  normal: { glyph: GLYPH.idle, tone: neutralFlag },
  low: { glyph: GLYPH.idle, tone: neutralFlag },
};

const checkbox = 'size-4 shrink-0 cursor-pointer accent-brand';

interface Props {
  tasks: PanelResult<TodoTask[]>;
  onChanged: () => void;
  /** Refletem a ação na tela antes de o servidor responder. */
  onCompletedChanged: (id: string, completed: boolean) => void;
  onRemoved: (id: string) => void;
  onSubtaskChanged: (taskId: string, itemId: string, completed: boolean) => void;
  onDoingChanged?: (id: string, doing: boolean) => void;
  onStyleChanged?: (id: string, patch: Partial<NoteStyle>) => void;
  /** The saved choice between the list and the board. The board is the
   *  default: it does everything the list does, and shows "Fazendo" at a glance. */
  view?: TasksView;
  onViewChanged?: (view: TasksView) => void;
  loading?: boolean;
}

const PRIORITY_LABEL: Record<TaskPriority, string> = {
  high: 'Alta',
  normal: 'Normal',
  low: 'Baixa',
};

// As faixas vêm em caixa alta para servirem de cabeçalho da lista; no chip
// elas viram texto normal, com só a primeira letra maiúscula.
export function chipCase(label: string): string {
  const lower = label.toLocaleLowerCase('pt-BR');
  return lower.charAt(0).toLocaleUpperCase('pt-BR') + lower.slice(1);
}

// A faixa já diz de que período a tarefa é (hoje, esta semana…), então o
// ano é redundante na linha: dia/mês basta, com a hora quando existir.
export function formatDue(due: string, time: string): string {
  const [, month, day] = due.split('-');
  if (!month || !day) return due;
  return time ? `${day}/${month} ${time}` : `${day}/${month}`;
}

/** Late is said with a glyph and a word as well as the warning hue, so it does
 *  not depend on telling colours apart. */
function DueDate({ task }: { task: TodoTask }) {
  const overdue = isOverdue(task);
  return (
    <span
      className={cn(
        'inline-flex shrink-0 items-center gap-1 type-caption',
        overdue ? 'font-medium text-warning' : 'text-ink-dim',
        tabular,
      )}
    >
      {overdue && <span aria-hidden>{GLYPH.alert}</span>}
      {overdue && <span className="sr-only">atrasada, prazo </span>}
      {formatDue(task.due, task.time)}
    </span>
  );
}

export function TasksPanel({
  tasks,
  onChanged,
  onCompletedChanged,
  onRemoved,
  onSubtaskChanged,
  onDoingChanged,
  onStyleChanged,
  view: savedView = 'board',
  onViewChanged,
  loading = false,
}: Props) {
  const focus = useFocusBlock();
  // Local so the toggle answers at once; re-synced when the saved choice
  // arrives or changes, which on first paint is after the state loads.
  const [view, setView] = useState<TasksView>(savedView);
  const [syncedView, setSyncedView] = useState<TasksView>(savedView);
  if (savedView !== syncedView) {
    setSyncedView(savedView);
    setView(savedView);
  }
  const [announcement, setAnnouncement] = useState('');
  const [editing, setEditing] = useState<TodoTask | 'new' | null>(null);
  const { confirm, dialog: confirmDialog } = useConfirm();
  const [actionError, setActionError] = useState<string | null>(null);

  const [query, setQuery] = useState('');
  const [priority, setPriority] = useState<TaskPriority | 'all'>('all');
  const [windowKey, setWindowKey] = useState<TaskGroupKey | 'all'>('all');
  // Concluída é ruído no dia a dia: some por padrão e só volta se pedirem.
  const [showCompleted, setShowCompleted] = useState(false);
  const [addingSubtaskFor, setAddingSubtaskFor] = useState<string | null>(null);
  // Subtarefa é detalhe da tarefa pai: fica recolhida até alguém pedir para
  // ver. Sem isso, uma lista com dez tarefas de três etapas vira quarenta
  // linhas e a lista principal deixa de ser legível de relance.
  const [expanded, setExpanded] = useState<Set<string>>(new Set());

  const toggleExpanded = (id: string) => {
    setExpanded((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  };

  // Whoever asks to add a subtask wants the field, and the ones already there
  // next to it.
  const startAddingSubtask = (id: string) => {
    setAddingSubtaskFor(id);
    setExpanded((prev) => new Set(prev).add(id));
  };

  const all = useMemo(() => tasks.data ?? [], [tasks.data]);

  const filtered = useMemo(
    () =>
      all.filter(
        (t) =>
          matchesQuery([t.title], query) &&
          (priority === 'all' || t.priority === priority) &&
          (showCompleted || !t.completed),
      ),
    [all, query, priority, showCompleted],
  );

  const groups = useMemo(() => {
    const grouped = groupTasksByDueWindow(filtered);
    return windowKey === 'all' ? grouped : grouped.filter((g) => g.key === windowKey);
  }, [filtered, windowKey]);

  // The board always shows "Feito": a done column that hides what is done
  // would be empty by default. The other filters apply as they do to the list,
  // and the window order (overdue first) carries into each column.
  const boardTasks = useMemo(() => {
    const base = all.filter(
      (t) =>
        matchesQuery([t.title], query) && (priority === 'all' || t.priority === priority),
    );
    return groupTasksByDueWindow(base)
      .filter((g) => windowKey === 'all' || g.key === windowKey)
      .flatMap((g) => g.tasks);
  }, [all, query, priority, windowKey]);

  const availableWindows = useMemo(() => groupTasksByDueWindow(all), [all]);
  const visibleCount =
    view === 'board' ? boardTasks.length : groups.reduce((sum, g) => sum + g.tasks.length, 0);

  const activeFilters: ActiveFilter[] = [
    ...(query.trim() ? [{ id: 'query', label: `Busca: ${query.trim()}` }] : []),
    ...(priority !== 'all' ? [{ id: 'priority', label: PRIORITY_LABEL[priority] }] : []),
    ...(windowKey !== 'all'
      ? [
          {
            id: 'window',
            label: availableWindows.find((g) => g.key === windowKey)?.label ?? String(windowKey),
          },
        ]
      : []),
  ];

  const clearFilter = (id: string) => {
    if (id === 'query') setQuery('');
    if (id === 'priority') setPriority('all');
    if (id === 'window') setWindowKey('all');
  };

  const clearAll = () => {
    setQuery('');
    setPriority('all');
    setWindowKey('all');
  };

  const toggleComplete = async (task: TodoTask) => {
    const completed = !task.completed;
    // Tarefa que repete não é concluída: ela pula para a próxima data. Marcar
    // otimista aqui daria um pisca de "feita" antes de o servidor corrigir.
    const recorrente = task.recur !== '';
    if (!recorrente) onCompletedChanged(task.id, completed);
    setActionError(null);

    const res = await fetch(`/api/tasks/${encodeURIComponent(task.id)}`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ completed }),
    });
    if (!res.ok) {
      setActionError(await readErrorMessage(res, 'Falha ao atualizar tarefa'));
      onChanged();
      return;
    }
    // A resposta confirma; recarregar mantém a lista alinhada com o servidor
    // (uma recorrente, por exemplo, volta com data nova).
    onChanged();
  };

  const chooseView = async (next: TasksView) => {
    if (next === view) return;
    setView(next);
    onViewChanged?.(next);
    setActionError(null);
    const res = await fetch('/api/preferences', {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ tasksView: next }),
    });
    // The view already changed and stays: it is what the person asked to see.
    // Only remembering it failed, and that is what the message says.
    if (!res.ok) {
      const reason = await readErrorMessage(res, 'erro ao guardar');
      setActionError(`A visualização mudou só nesta tela: não foi guardada (${reason}). Tente de novo.`);
    }
  };

  const moveTask = async (task: TodoTask, to: BoardColumn): Promise<boolean> => {
    const steps = planMove(task, to);
    if (steps.length === 0) return true;
    setActionError(null);
    // Same rule as the checkbox: a recurring task is not marked done ahead of
    // the server, because it rolls over to its next date instead.
    const recurring = task.recur !== '';
    for (const step of steps) {
      if (step.kind === 'status') onDoingChanged?.(task.id, step.status === 'doing');
      else if (!(step.completed && recurring)) onCompletedChanged(task.id, step.completed);
    }

    for (const step of steps) {
      const res =
        step.kind === 'complete'
          ? await fetch(`/api/tasks/${encodeURIComponent(task.id)}`, {
              method: 'PATCH',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({ completed: step.completed }),
            })
          : await fetch(`/api/tasks/${encodeURIComponent(task.id)}/board`, {
              method: 'PATCH',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({ status: step.status }),
            });
      if (!res.ok) {
        const message = await readErrorMessage(res, 'Falha ao mover tarefa');
        setActionError(message);
        setAnnouncement(`Não foi possível mover ${task.title}: ${message}`);
        onChanged();
        return false;
      }
    }
    setAnnouncement(
      to === 'done' && recurring && task.due
        ? `${task.title} concluída. Ela repete, então volta para A fazer com a próxima data.`
        : `${task.title} movida para ${columnLabel(to)}.`,
    );
    onChanged();
    return true;
  };

  const describeStyle = (patch: Partial<NoteStyle>): string => {
    if ('paper' in patch) return patch.paper ? `Papel ${PAPER_LABEL[patch.paper]}` : 'Papel automático';
    return patch.pin ? `Alfinete ${PIN_LABEL[patch.pin]}` : 'Alfinete automático';
  };

  // Shown at once, like a move. The server only writes a row of this app's
  // own database, so a failure is rare; when it happens the old colours come
  // back right away and the reload confirms what is really saved.
  const changeStyle = async (task: TodoTask, patch: Partial<NoteStyle>) => {
    const previous: Partial<NoteStyle> = {};
    if ('paper' in patch) previous.paper = task.paper;
    if ('pin' in patch) previous.pin = task.pin;
    onStyleChanged?.(task.id, patch);
    setActionError(null);
    const res = await fetch(`/api/tasks/${encodeURIComponent(task.id)}/board`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(patch),
    });
    if (!res.ok) {
      const message = await readErrorMessage(res, 'Falha ao mudar a cor');
      onStyleChanged?.(task.id, previous);
      setActionError(message);
      setAnnouncement(`Não foi possível mudar a cor de ${task.title}: ${message}`);
      onChanged();
      return;
    }
    setAnnouncement(`${describeStyle(patch)} em ${task.title}.`);
  };

  // One request even for "Fazendo": a create followed by a separate move could
  // leave the task in "A fazer" when the second request failed.
  const createTask = async (title: string, column: 'todo' | 'doing'): Promise<boolean> => {
    setActionError(null);
    const res = await fetch('/api/tasks', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ title, status: column }),
    });
    if (!res.ok) {
      const message = await readErrorMessage(res, 'Falha ao criar tarefa');
      setActionError(message);
      setAnnouncement(`Não foi possível adicionar ${title}: ${message}`);
      return false;
    }
    setAnnouncement(`${title} adicionada em ${columnLabel(column)}.`);
    onChanged();
    return true;
  };

  const remove = async (task: TodoTask) => {
    // Same rule as notes and e-mail: deleting asks first. With Microsoft To Do
    // behind the panel there is no trash to restore from.
    const ok = await confirm({
      title: 'Apagar a tarefa?',
      description: `"${task.title}" será removida. Isso não tem volta.`,
      confirmLabel: 'Apagar',
      destructive: true,
    });
    if (!ok) return;
    onRemoved(task.id);
    setActionError(null);

    const res = await fetch(`/api/tasks/${encodeURIComponent(task.id)}`, { method: 'DELETE' });
    if (!res.ok) {
      setActionError(await readErrorMessage(res, 'Falha ao apagar tarefa'));
      // A tarefa continua existindo: recarrega para ela voltar à lista.
      onChanged();
      return;
    }
  };

  return (
    <Section
      eyebrow="Tarefas"
      count={activeFilters.length > 0 ? `${visibleCount} de ${all.length}` : undefined}
      actions={
        <div className="flex items-center gap-2">
          <div role="group" aria-label="Visualização das tarefas" className={segmentedGroup}>
            <button
              type="button"
              className={cn(segmentedItem, focusRing)}
              aria-pressed={view === 'list'}
              onClick={() => void chooseView('list')}
            >
              <List className="size-3.5" aria-hidden="true" />
              Lista
            </button>
            <button
              type="button"
              className={cn(segmentedItem, focusRing)}
              aria-pressed={view === 'board'}
              onClick={() => void chooseView('board')}
            >
              <StickyNote className="size-3.5" aria-hidden="true" />
              Quadro
            </button>
          </div>
          <IconAction
            variant="default"
            label="Nova tarefa"
            onClick={() => setEditing('new')}
            icon={<Plus className="size-4" />}
          />
        </div>
      }
    >
      <FilterBar label="Filtrar tarefas">
        <SearchInput
          value={query}
          onChange={setQuery}
          label="buscar tarefas"
          placeholder="título"
        />
        <Chip
          active={priority === 'high'}
          onClick={() => setPriority(priority === 'high' ? 'all' : 'high')}
        >
          Alta
        </Chip>
        <Chip
          active={priority === 'low'}
          onClick={() => setPriority(priority === 'low' ? 'all' : 'low')}
        >
          Baixa
        </Chip>
        {view === 'list' && (
          <Chip active={showCompleted} onClick={() => setShowCompleted((v) => !v)}>
            Concluídas
          </Chip>
        )}
        {availableWindows.map((g) => (
          <Chip
            key={g.key}
            active={windowKey === g.key}
            onClick={() => setWindowKey(windowKey === g.key ? 'all' : g.key)}
          >
            {chipCase(g.label)}
          </Chip>
        ))}
      </FilterBar>

      <ActiveFilters filters={activeFilters} onRemove={clearFilter} onClearAll={clearAll} />

      {tasks.error && <PanelError>{tasks.error}</PanelError>}
      {actionError && <PanelError>{actionError}</PanelError>}

      {loading && all.length === 0 && <SkeletonRows count={5} />}

      {/* The board needs no empty state of its own: its empty columns already
          say where a note goes, and each has its own "Adicionar". */}
      {view === 'list' && !loading && all.length === 0 && !tasks.error && (
        <EmptyState
          title="Nenhuma tarefa por aqui. Crie a primeira."
          action={
            <Button type="button" onClick={() => setEditing('new')}>
              <Plus className="size-4" aria-hidden="true" />
              Nova tarefa
            </Button>
          }
        />
      )}

      {all.length > 0 && visibleCount === 0 && (
        <EmptyState title="Nenhuma tarefa com esses filtros." />
      )}

      <p role="status" className="sr-only">
        {announcement}
      </p>

      {view === 'board' && !(loading && all.length === 0) && (
        <TaskBoard
          tasks={boardTasks}
          onMove={moveTask}
          onOpen={setEditing}
          onRemove={(task) => void remove(task)}
          onStyleChange={(task, patch) => void changeStyle(task, patch)}
          onCreate={createTask}
          onChanged={onChanged}
          onError={setActionError}
          onSubtaskChanged={onSubtaskChanged}
          formatDue={formatDue}
        />
      )}

      {view === 'list' && groups.map((group) => (
        <div key={group.key} className="mt-5 first:mt-0">
          <h3 className="mb-2 block type-caption text-ink-dim">{group.label}</h3>
          <ul>
            {group.tasks.map((task) => (
              <li
                key={task.id}
                className="border-b border-line-soft even:bg-muted/25"
                draggable={focus.enabled && !task.completed}
                onDragStart={(event) => {
                  if (!focus.enabled || task.completed) return;
                  const source: FocusSource = { kind: 'task', ref: task.id, title: task.title };
                  event.dataTransfer.setData(FOCUS_DRAG_TYPE, JSON.stringify(source));
                  event.dataTransfer.effectAllowed = 'copy';
                }}
              >
                <div className="flex items-center gap-3 rounded-md px-2 py-3 transition-colors duration-100 ease-brand hover:bg-brand-tint motion-reduce:transition-none">
                  {/* A seta só existe onde há o que revelar. Numa tarefa sem
                      subtarefa ela seria um controle que não faz nada. */}
                  {task.subtasks.length > 0 ? (
                    <button
                      type="button"
                      className={cn(caret, focusRing)}
                      aria-label={`${expanded.has(task.id) ? 'recolher' : 'expandir'} subtarefas de ${task.title}`}
                      aria-expanded={expanded.has(task.id)}
                      onClick={() => toggleExpanded(task.id)}
                    >
                      <NavArrowRight width={14} height={14} />
                    </button>
                  ) : (
                    <span className="inline-block size-6 shrink-0" aria-hidden="true" />
                  )}
                  <input
                    type="checkbox"
                    className={checkbox}
                    checked={task.completed}
                    onChange={() => void toggleComplete(task)}
                    aria-label={`concluir ${task.title}`}
                  />
                  {/* Parity with the board: a colour chosen there shows here
                      too, or the list would hide something the board says. */}
                  {task.paper && (
                    <span
                      role="img"
                      className="paper-dot"
                      data-paper={task.paper}
                      aria-label={`nota ${PAPER_LABEL[task.paper]}`}
                      title={`nota ${PAPER_LABEL[task.paper]}`}
                    />
                  )}
                  <button
                    type="button"
                    className={cn(
                      'flex min-w-0 flex-1 flex-col items-start gap-0.5 rounded-sm text-left',
                      focusRing,
                    )}
                    onClick={() => setEditing(task)}
                  >
                    <span
                      className={cn(
                        'w-full truncate',
                        task.completed ? 'text-ink-dim line-through' : 'text-ink',
                      )}
                    >
                      {task.title}
                    </span>
                  </button>
                  {task.doing && (
                    <span className={cn(flagPill, doingFlag)}>
                      <span aria-hidden>{GLYPH.moving}</span>
                      <span>Fazendo</span>
                    </span>
                  )}
                  {task.priority !== 'normal' && (
                    <span className={cn(flagPill, PRIORITY_TONE[task.priority].tone)}>
                      <span aria-hidden>{PRIORITY_TONE[task.priority].glyph}</span>
                      <span>{PRIORITY_LABEL[task.priority]}</span>
                    </span>
                  )}
                  {task.recur !== '' && (
                    <span className={cn(flagPill, neutralFlag)} title="tarefa recorrente">
                      repete
                    </span>
                  )}
                  {task.due && <DueDate task={task} />}
                  {task.subtasks.length > 0 && (
                    <span
                      className={cn('shrink-0 type-caption text-ink-dim', tabular)}
                      title="subtarefas concluídas"
                    >
                      {task.subtasks.filter((s) => s.completed).length}/{task.subtasks.length}
                    </span>
                  )}
                  {/* O contador acima é o que faz a subtarefa escondida ainda
                      ser visível como informação: dá para ver que existe e
                      quanto falta sem abrir. */}
                  {focus.enabled && !task.completed && (
                    <IconAction
                      label={`agendar foco para ${task.title}`}
                      onClick={() => focus.schedule({ kind: 'task', ref: task.id, title: task.title })}
                      icon={<CalendarPlus className="size-4" />}
                    />
                  )}
                  <TaskActionsMenu
                    task={task}
                    onEdit={() => setEditing(task)}
                    onAddSubtask={() => startAddingSubtask(task.id)}
                    onMove={(to) => void moveTask(task, to)}
                    onStyleChange={(patch) => void changeStyle(task, patch)}
                    onDelete={() => void remove(task)}
                  />
                </div>
                {(expanded.has(task.id) || addingSubtaskFor === task.id) && (
                  <SubtaskList
                    task={task}
                    onChanged={onChanged}
                    onError={setActionError}
                    onSubtaskChanged={onSubtaskChanged}
                    adding={addingSubtaskFor === task.id}
                    onStartAdding={() => startAddingSubtask(task.id)}
                    onDoneAdding={() => setAddingSubtaskFor(null)}
                  />
                )}
              </li>
            ))}
          </ul>
        </div>
      ))}

      {confirmDialog}
      {editing && (
        <TaskFormModal
          task={editing === 'new' ? null : editing}
          onClose={() => setEditing(null)}
          onSaved={(styleError) => {
            setEditing(null);
            // The task itself was saved; only its colour was not, and the
            // message says exactly that rather than "failed to save".
            if (styleError) setActionError(`A tarefa foi salva, mas a cor não: ${styleError}`);
            onChanged();
          }}
          onDeleted={(id) => {
            setEditing(null);
            onRemoved(id);
          }}
        />
      )}
    </Section>
  );
}
