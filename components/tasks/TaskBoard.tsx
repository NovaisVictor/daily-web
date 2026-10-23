'use client';

import { useId, useState } from 'react';
import type { CSSProperties, DragEvent } from 'react';
import { ArrowLeft, ArrowRight } from 'lucide-react';
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
  noteTilt,
  noteTone,
  type BoardColumn,
} from '@/lib/taskBoard';
import { PushPin } from './PushPin';
import { FOCUS_DRAG_TYPE, type FocusSource } from '@/lib/focusBlock';
import { useFocusBlock } from '@/components/FocusBlockProvider';
import { GLYPH } from '@/components/data/Status';
import { cn } from '@/lib/utils';
import { focusRing, tabular } from '@/lib/theme';

const PRIORITY_LABEL: Record<TaskPriority, string> = {
  high: 'Alta',
  normal: 'Normal',
  low: 'Baixa',
};

interface Props {
  tasks: TodoTask[];
  onMove: (task: TodoTask, to: BoardColumn) => void;
  onOpen: (task: TodoTask) => void;
  formatDue: (due: string, time: string) => string;
}

function NoteCard({
  task,
  onMove,
  onOpen,
  formatDue,
}: {
  task: TodoTask;
  onMove: (task: TodoTask, to: BoardColumn) => void;
  onOpen: (task: TodoTask) => void;
  formatDue: (due: string, time: string) => string;
}) {
  const focus = useFocusBlock();
  const [dragging, setDragging] = useState(false);
  const column = columnOf(task);
  const { previous, next } = neighbours(column);
  const doneSubtasks = task.subtasks.filter((s) => s.completed).length;
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

  return (
    <li
      className="postit-slot"
      draggable
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
        <div className="postit" data-tone={noteTone(task)} data-done={task.completed || undefined} style={style}>
          <button
            type="button"
            className={cn('postit-title rounded-sm text-left', focusRing)}
            onClick={() => onOpen(task)}
          >
            <span className="postit-title-text">{task.title}</span>
          </button>

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
                <span className={tabular}>
                  <span className="sr-only">prazo </span>
                  {formatDue(task.due, task.time)}
                </span>
              )}
              {task.subtasks.length > 0 && (
                <span className={cn('postit-progress', tabular)} title="subtarefas concluídas">
                  <span
                    className="postit-progress-bar"
                    aria-hidden="true"
                    style={{ '--progress': `${(doneSubtasks / task.subtasks.length) * 100}%` } as CSSProperties}
                  />
                  <span className="sr-only">subtarefas concluídas: </span>
                  {doneSubtasks}/{task.subtasks.length}
                </span>
              )}
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
 * The tasks as notes pinned to a board. The panel keeps its fixed height and
 * scrolls inside; a narrow panel stacks the columns instead of scrolling
 * sideways, which the dashboard grid would clip.
 */
export function TaskBoard({ tasks, onMove, onOpen, formatDue }: Props) {
  const baseId = useId();
  const [over, setOver] = useState<BoardColumn | null>(null);
  const columns = groupByColumn(tasks);
  const byId = new Map(tasks.map((t) => [t.id, t]));

  const accepts = (event: DragEvent) => event.dataTransfer.types.includes(TASK_BOARD_DRAG_TYPE);

  return (
    <div className="@container">
      <div className="grid grid-cols-1 gap-4 @[30rem]:grid-cols-3">
        {BOARD_COLUMNS.map((column) => {
          const headingId = `${baseId}-${column.key}`;
          const list = columns[column.key];
          return (
            <section
              key={column.key}
              aria-labelledby={headingId}
              className="board-lane"
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
                if (task) onMove(task, column.key);
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
                  {column.key === 'done' ? 'Nada concluído por aqui.' : 'Nenhuma nota aqui.'}
                </p>
              ) : (
                <ul className="board-notes" aria-labelledby={headingId}>
                  {list.map((task) => (
                    <NoteCard
                      key={task.id}
                      task={task}
                      onMove={onMove}
                      onOpen={onOpen}
                      formatDue={formatDue}
                    />
                  ))}
                </ul>
              )}
            </section>
          );
        })}
      </div>
    </div>
  );
}
