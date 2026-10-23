'use client';

import { useEffect, useId, useRef, useState } from 'react';
import type { CSSProperties, DragEvent, KeyboardEvent } from 'react';
import { ArrowLeft, ArrowRight, Plus } from 'lucide-react';
import type { TaskPriority, TodoTask } from '@/lib/types';
import {
  BOARD_COLUMNS,
  TASK_BOARD_DRAG_TYPE,
  columnLabel,
  columnOf,
  groupByColumn,
  neighbours,
  noteCurls,
  notePin,
  notePaper,
  noteTilt,
  type BoardColumn,
} from '@/lib/taskBoard';
import { isOverdue } from '@/lib/taskGrouping';
import { PushPin } from './PushPin';
import { SubtaskList } from './SubtaskList';
import { TaskActionsMenu } from './TaskActionsMenu';
import type { NoteStyle } from './NoteColourPicker';
import { segmentedGroup, segmentedItem } from './segmented';
import { FOCUS_DRAG_TYPE, type FocusSource } from '@/lib/focusBlock';
import { useFocusBlock } from '@/components/FocusBlockProvider';
import { GLYPH } from '@/components/data/Status';
import { Input } from '@/components/ui/input';
import { cn } from '@/lib/utils';
import { focusRing, tabular } from '@/lib/theme';

const PRIORITY_LABEL: Record<TaskPriority, string> = {
  high: 'Alta',
  normal: 'Normal',
  low: 'Baixa',
};

/** "Feito" only grows: past this many notes the column hides the rest behind
 *  a button, or a month of finished work would bury the open columns. */
export const DONE_LIMIT = 10;

/** Where a new note can start. "Feito" is not one: a task is not born done. */
type NewNoteColumn = Exclude<BoardColumn, 'done'>;

interface Props {
  tasks: TodoTask[];
  /** Resolves false when the move failed and the note went back. */
  onMove: (task: TodoTask, to: BoardColumn) => Promise<boolean>;
  onOpen: (task: TodoTask) => void;
  onRemove: (task: TodoTask) => void;
  onStyleChange: (task: TodoTask, patch: Partial<NoteStyle>) => void;
  /** Resolves false when nothing was created, so the field keeps the text. */
  onCreate: (title: string, column: NewNoteColumn) => Promise<boolean>;
  onChanged: () => void;
  onError: (message: string) => void;
  onSubtaskChanged: (taskId: string, itemId: string, completed: boolean) => void;
  formatDue: (due: string, time: string) => string;
}

interface NoteProps extends Omit<Props, 'tasks' | 'onCreate' | 'onMove'> {
  task: TodoTask;
  /** A move asked for by a button or the menu, which keeps the focus on the note. */
  onMove: (task: TodoTask, to: BoardColumn) => void;
  titleRef: (node: HTMLButtonElement | null) => void;
}

function NoteCard({
  task,
  onMove,
  onOpen,
  onRemove,
  onStyleChange,
  onChanged,
  onError,
  onSubtaskChanged,
  formatDue,
  titleRef,
}: NoteProps) {
  const focus = useFocusBlock();
  const checklistId = useId();
  const [dragging, setDragging] = useState(false);
  const [checklistOpen, setChecklistOpen] = useState(false);
  const [addingSubtask, setAddingSubtask] = useState(false);
  const column = columnOf(task);
  const { previous, next } = neighbours(column);
  const doneSubtasks = task.subtasks.filter((s) => s.completed).length;
  const overdue = isOverdue(task);
  // Custom property, not a transform: the stylesheet composes it with the
  // hover lift, and turns the lift off under reduced motion.
  const style = { '--note-tilt': `${noteTilt(task.id)}deg` } as CSSProperties;

  const startDrag = (event: DragEvent<HTMLLIElement>) => {
    event.dataTransfer.setData(TASK_BOARD_DRAG_TYPE, task.id);
    // The same note can still be dropped on the agenda to book focus time, as
    // a row of the list can; the board must not take that away.
    if (focus.enabled && !task.completed) {
      const source: FocusSource = { kind: 'task', ref: task.id, title: task.title };
      event.dataTransfer.setData(FOCUS_DRAG_TYPE, JSON.stringify(source));
    }
    event.dataTransfer.effectAllowed = 'copyMove';
    setDragging(true);
  };

  const startAddingSubtask = () => {
    setChecklistOpen(true);
    setAddingSubtask(true);
  };

  return (
    <li
      className="postit-slot"
      // Typing in the subtask field inside a draggable note would start a drag
      // the moment the text is selected with the mouse.
      draggable={!addingSubtask}
      onDragStart={startDrag}
      onDragEnd={() => setDragging(false)}
      data-dragging={dragging || undefined}
      data-curl={noteCurls(task.id) || undefined}
    >
      {/* Outside the note: a curled note is masked, and the mask would cut
          away the pin's head, which stands above the paper. */}
      <PushPin color={notePin(task)} />
      {/* The paper's own shadow lives on this wrapper: a curled note is masked,
          and a shadow on the masked element would be cut with it. Keeping the
          pin outside also keeps it from getting a second shadow. */}
      <div className="postit-paper">
        <div className="postit" data-paper={notePaper(task)} data-done={task.completed || undefined} style={style}>
          <div className="postit-head">
            <button
              ref={titleRef}
              type="button"
              className={cn('postit-title rounded-sm text-left', focusRing)}
              onClick={() => onOpen(task)}
            >
              <span className="postit-title-text">{task.title}</span>
            </button>
            <TaskActionsMenu
              task={task}
              size="icon-xs"
              // Ghost button colours come from the app surface; on the paper they
              // would be a grey smudge, so the note's own ink takes over.
              className="-mt-0.5 -mr-1.5 text-(--postit-ink-mid) hover:bg-(--postit-wash) hover:text-(--postit-ink) data-[state=open]:bg-(--postit-wash) dark:hover:bg-(--postit-wash)"
              moveTakesFocus
              onEdit={() => onOpen(task)}
              onAddSubtask={startAddingSubtask}
              onMove={(to) => onMove(task, to)}
              onStyleChange={(patch) => onStyleChange(task, patch)}
              onDelete={() => onRemove(task)}
            />
          </div>

          {(task.priority !== 'normal' || task.recur !== '' || task.due || task.subtasks.length > 0) && (
            <div className="postit-meta">
              {task.priority !== 'normal' && (
                <span className="postit-tag">
                  <span aria-hidden>{task.priority === 'high' ? GLYPH.alert : GLYPH.idle}</span>
                  {PRIORITY_LABEL[task.priority]}
                </span>
              )}
              {task.recur !== '' && (
                <span className="postit-tag" title="tarefa recorrente">
                  repete
                </span>
              )}
              {task.due && (
                <span className={cn('postit-due', tabular)} data-overdue={overdue || undefined}>
                  {overdue && <span aria-hidden>{GLYPH.alert}</span>}
                  <span className="sr-only">{overdue ? 'atrasada, prazo ' : 'prazo '}</span>
                  {formatDue(task.due, task.time)}
                </span>
              )}
              {task.subtasks.length > 0 && (
                <button
                  type="button"
                  className={cn('postit-progress', tabular, focusRing)}
                  aria-expanded={checklistOpen}
                  aria-controls={checklistId}
                  aria-label={`subtarefas de ${task.title}: ${doneSubtasks} de ${task.subtasks.length} concluídas`}
                  onClick={() => {
                    setChecklistOpen((open) => !open);
                    setAddingSubtask(false);
                  }}
                >
                  <span
                    className="postit-progress-bar"
                    aria-hidden="true"
                    style={{ '--progress': `${(doneSubtasks / task.subtasks.length) * 100}%` } as CSSProperties}
                  />
                  {doneSubtasks}/{task.subtasks.length}
                </button>
              )}
            </div>
          )}

          {checklistOpen && (
            <div id={checklistId}>
              <SubtaskList
                task={task}
                variant="note"
                onChanged={onChanged}
                onError={onError}
                onSubtaskChanged={onSubtaskChanged}
                adding={addingSubtask}
                onStartAdding={() => setAddingSubtask(true)}
                onDoneAdding={() => setAddingSubtask(false)}
              />
            </div>
          )}

          {/* Dragging is pointer-only. These are the same moves for keyboard,
              screen reader and touch, where HTML5 drag does not fire at all. */}
          <div className="postit-moves">
            {previous && (
              <button
                type="button"
                className={cn('postit-move', focusRing)}
                aria-label={`mover ${task.title} para ${columnLabel(previous)}`}
                onClick={() => onMove(task, previous)}
              >
                <ArrowLeft className="size-3.5" aria-hidden="true" />
                {columnLabel(previous)}
              </button>
            )}
            {next && (
              <button
                type="button"
                className={cn('postit-move ml-auto', focusRing)}
                aria-label={`mover ${task.title} para ${columnLabel(next)}`}
                onClick={() => onMove(task, next)}
              >
                {columnLabel(next)}
                <ArrowRight className="size-3.5" aria-hidden="true" />
              </button>
            )}
          </div>
        </div>
      </div>
    </li>
  );
}

/**
 * "+ Adicionar" at the foot of a column. Enter creates and leaves the field
 * open, because notes usually come in a batch; Esc puts the focus back on the
 * button that opened it.
 */
function AddNote({
  column,
  onCreate,
}: {
  column: NewNoteColumn;
  onCreate: (title: string, column: NewNoteColumn) => Promise<boolean>;
}) {
  const [open, setOpen] = useState(false);
  const [title, setTitle] = useState('');
  const [saving, setSaving] = useState(false);
  const opener = useRef<HTMLButtonElement>(null);
  const returnFocus = useRef(false);
  const label = columnLabel(column);

  useEffect(() => {
    if (!open && returnFocus.current) {
      returnFocus.current = false;
      opener.current?.focus();
    }
  }, [open]);

  const close = (withFocus: boolean) => {
    returnFocus.current = withFocus;
    setTitle('');
    setOpen(false);
  };

  const submit = async () => {
    const value = title.trim();
    // A second Enter while the first is still on its way would create the
    // same note twice.
    if (!value || saving) return;
    setSaving(true);
    const created = await onCreate(value, column);
    setSaving(false);
    if (created) setTitle('');
  };

  const onKeyDown = (event: KeyboardEvent<HTMLInputElement>) => {
    if (event.key === 'Enter') {
      event.preventDefault();
      void submit();
    }
    if (event.key === 'Escape') {
      event.preventDefault();
      close(true);
    }
  };

  if (!open) {
    return (
      <button
        ref={opener}
        type="button"
        className={cn('board-lane-add', focusRing)}
        aria-label={`adicionar tarefa em ${label}`}
        onClick={() => setOpen(true)}
      >
        <Plus className="size-3.5" aria-hidden="true" />
        Adicionar
      </button>
    );
  }

  return (
    <Input
      value={title}
      onChange={(event) => setTitle(event.target.value)}
      onKeyDown={onKeyDown}
      // Leaving an empty field closes it; leaving one with text keeps it, so
      // a stray click does not throw away what was typed.
      onBlur={() => {
        if (!title.trim() && !saving) close(false);
      }}
      aria-label={`nova tarefa em ${label}`}
      aria-busy={saving || undefined}
      placeholder="Título, e Enter para adicionar"
      maxLength={255}
      autoFocus
    />
  );
}

/**
 * The tasks as notes pinned to a board. The panel keeps its fixed height and
 * scrolls inside. A narrow panel shows one column at a time behind tabs:
 * stacked, "Fazendo" and "Feito" ended up far below the fold of the card.
 */
export function TaskBoard({ tasks, onMove, onCreate, ...noteProps }: Props) {
  const baseId = useId();
  const [over, setOver] = useState<BoardColumn | null>(null);
  const [active, setActive] = useState<BoardColumn>('todo');
  const [showAllDone, setShowAllDone] = useState(false);
  const tabs = useRef(new Map<BoardColumn, HTMLButtonElement>());
  const titles = useRef(new Map<string, HTMLButtonElement>());
  // A note moved by a button is unmounted and drawn again in its new column,
  // and the focus went to the page with it. This is where it should land.
  const pendingFocus = useRef<{ id: string; to: BoardColumn } | null>(null);
  const columns = groupByColumn(tasks);
  const byId = new Map(tasks.map((t) => [t.id, t]));

  useEffect(() => {
    const pending = pendingFocus.current;
    if (!pending) return;
    const task = byId.get(pending.id);
    if (!task) {
      pendingFocus.current = null;
      return;
    }
    if (columnOf(task) !== pending.to) return;
    const title = titles.current.get(pending.id);
    if (!title) {
      // Past the first notes of "Feito": show them all so the focus has
      // somewhere to go.
      if (pending.to === 'done') setShowAllDone(true);
      return;
    }
    pendingFocus.current = null;
    title.focus();
  });

  const accepts = (event: DragEvent) => event.dataTransfer.types.includes(TASK_BOARD_DRAG_TYPE);

  const moveKeepingFocus = (task: TodoTask, to: BoardColumn) => {
    pendingFocus.current = { id: task.id, to };
    // The note's new column is the one on screen afterwards; on a narrow
    // board the person would otherwise lose sight of it.
    setActive(to);
    void onMove(task, to).then((ok) => {
      if (!ok && pendingFocus.current?.id === task.id) pendingFocus.current = null;
    });
  };

  const onTabKey = (event: KeyboardEvent<HTMLButtonElement>, index: number) => {
    const step = event.key === 'ArrowRight' ? 1 : event.key === 'ArrowLeft' ? -1 : 0;
    const edge = event.key === 'Home' ? 0 : event.key === 'End' ? BOARD_COLUMNS.length - 1 : -1;
    if (step === 0 && edge === -1) return;
    event.preventDefault();
    const target = edge >= 0 ? edge : (index + step + BOARD_COLUMNS.length) % BOARD_COLUMNS.length;
    const key = BOARD_COLUMNS[target].key;
    setActive(key);
    tabs.current.get(key)?.focus();
  };

  return (
    <div className="@container">
      <div
        role="tablist"
        aria-label="Colunas do quadro"
        className={cn(segmentedGroup, 'mb-3 flex w-full @[30rem]:hidden')}
      >
        {BOARD_COLUMNS.map((column, index) => (
          <button
            key={column.key}
            ref={(node) => {
              if (node) tabs.current.set(column.key, node);
              else tabs.current.delete(column.key);
            }}
            type="button"
            role="tab"
            id={`${baseId}-tab-${column.key}`}
            aria-selected={active === column.key}
            aria-controls={`${baseId}-${column.key}-lane`}
            tabIndex={active === column.key ? 0 : -1}
            className={cn(segmentedItem, focusRing, 'flex-1 justify-center')}
            onClick={() => setActive(column.key)}
            onKeyDown={(event) => onTabKey(event, index)}
          >
            {column.label}
            <span className={cn('text-ink-dim', tabular)}>{columns[column.key].length}</span>
          </button>
        ))}
      </div>
      <div className="grid grid-cols-1 gap-4 @[30rem]:grid-cols-3">
        {BOARD_COLUMNS.map((column) => {
          const headingId = `${baseId}-${column.key}`;
          const list = columns[column.key];
          const shown = column.key === 'done' && !showAllDone ? list.slice(0, DONE_LIMIT) : list;
          return (
            <section
              key={column.key}
              id={`${headingId}-lane`}
              aria-labelledby={headingId}
              className={cn('board-lane', active !== column.key && '@max-[30rem]:hidden')}
              data-over={over === column.key || undefined}
              onDragOver={(event) => {
                if (!accepts(event)) return;
                event.preventDefault();
                event.dataTransfer.dropEffect = 'move';
                setOver(column.key);
              }}
              onDragLeave={(event) => {
                // Moving between notes inside the lane fires leave on the lane
                // too; only leaving the lane itself should drop the highlight.
                if (event.currentTarget.contains(event.relatedTarget as Node | null)) return;
                setOver(null);
              }}
              onDrop={(event) => {
                if (!accepts(event)) return;
                event.preventDefault();
                setOver(null);
                const task = byId.get(event.dataTransfer.getData(TASK_BOARD_DRAG_TYPE));
                // A drop needs no focus work: the pointer already knows where it went.
                if (task) void onMove(task, column.key);
              }}
            >
              <h3 id={headingId} className="board-lane-title">
                {column.label}
                <span className={cn('board-lane-count', tabular)} aria-hidden="true">
                  {list.length}
                </span>
                <span className="sr-only">{`, ${list.length} ${list.length === 1 ? 'tarefa' : 'tarefas'}`}</span>
              </h3>
              {list.length === 0 ? (
                <p className="board-lane-empty">
                  {column.key === 'done' ? 'Arraste uma nota para cá.' : 'Arraste uma nota para cá ou adicione.'}
                </p>
              ) : (
                <ul className="board-notes" aria-labelledby={headingId}>
                  {shown.map((task) => (
                    <NoteCard
                      key={task.id}
                      task={task}
                      {...noteProps}
                      onMove={moveKeepingFocus}
                      titleRef={(node) => {
                        if (node) titles.current.set(task.id, node);
                        else titles.current.delete(task.id);
                      }}
                    />
                  ))}
                </ul>
              )}
              {column.key === 'done' && list.length > DONE_LIMIT && (
                <button
                  type="button"
                  className={cn('board-lane-add', focusRing)}
                  aria-expanded={showAllDone}
                  onClick={() => setShowAllDone((all) => !all)}
                >
                  {showAllDone ? 'Mostrar menos' : `Mostrar todas (${list.length})`}
                </button>
              )}
              {column.key !== 'done' && <AddNote column={column.key} onCreate={onCreate} />}
            </section>
          );
        })}
      </div>
    </div>
  );
}
