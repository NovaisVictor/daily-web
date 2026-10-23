'use client';

import { useEffect, useRef, useState } from 'react';
import { Plus } from 'lucide-react';
import type { TodoTask } from '@/lib/types';
import { IconAction } from '@/components/data/IconAction';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { cn } from '@/lib/utils';
import { focusRing } from '@/lib/theme';
import { readErrorMessage } from './readErrorMessage';

const checkbox = 'size-4 shrink-0 cursor-pointer accent-brand';

interface Props {
  task: TodoTask;
  onChanged: () => void;
  onError: (message: string) => void;
  onSubtaskChanged: (taskId: string, itemId: string, completed: boolean) => void;
  adding: boolean;
  onStartAdding: () => void;
  onDoneAdding: () => void;
  /** "list" hangs under the row with an indent; "note" sits inside a post-it,
   *  where the paper sets the colours and there is no room for an indent. */
  variant?: 'list' | 'note';
}

/**
 * A task's checklist: tick, add and delete subtasks. The list and the board
 * share it so a subtask can be handled the same way from either view.
 */
export function SubtaskList({
  task,
  onChanged,
  onError,
  onSubtaskChanged,
  adding,
  onStartAdding,
  onDoneAdding,
  variant = 'list',
}: Props) {
  const [newTitle, setNewTitle] = useState('');
  const addButton = useRef<HTMLButtonElement>(null);
  // Closing the field unmounts it, and the focus would fall to the page. It
  // goes back to the button that opened it, but only when the field had it:
  // a refresh closing the field must not pull the focus from elsewhere.
  const returnFocus = useRef(false);
  const note = variant === 'note';

  useEffect(() => {
    if (!adding && returnFocus.current) {
      returnFocus.current = false;
      addButton.current?.focus();
    }
  }, [adding]);

  const finishAdding = () => {
    returnFocus.current = true;
    onDoneAdding();
  };

  const toggleSubtask = async (subtaskId: string, completed: boolean) => {
    onSubtaskChanged(task.id, subtaskId, completed);

    const res = await fetch(
      `/api/tasks/${encodeURIComponent(task.id)}/subtasks/${encodeURIComponent(subtaskId)}`,
      {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ completed }),
      },
    );
    if (!res.ok) {
      onError(await readErrorMessage(res, 'Falha ao atualizar subtarefa'));
      onChanged();
    }
  };

  const addSubtask = async () => {
    if (!newTitle.trim()) return;
    const res = await fetch(`/api/tasks/${encodeURIComponent(task.id)}/subtasks`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ title: newTitle.trim() }),
    });
    if (!res.ok) {
      onError(await readErrorMessage(res, 'Falha ao adicionar subtarefa'));
      return;
    }
    setNewTitle('');
    finishAdding();
    onChanged();
  };

  const removeSubtask = async (subtaskId: string) => {
    const res = await fetch(
      `/api/tasks/${encodeURIComponent(task.id)}/subtasks/${encodeURIComponent(subtaskId)}`,
      { method: 'DELETE' },
    );
    if (!res.ok) {
      onError(await readErrorMessage(res, 'Falha ao apagar subtarefa'));
      return;
    }
    onChanged();
  };

  return (
    <div
      className={
        note
          ? 'postit-checklist'
          : /* A subtask is the parent's child: the indent and the left hairline
               say so without a label. The rule starts aligned with the parent's
               checkbox. */
            'mb-3 ml-11 flex flex-col gap-1 border-l border-line-soft pl-4'
      }
    >
      {task.subtasks.map((subtask) => (
        <div
          key={subtask.id}
          className={cn(
            note ? 'postit-subtask' : 'flex items-center gap-2 text-sm',
            !note && (subtask.completed ? 'text-ink-dim line-through' : 'text-ink-mid'),
          )}
          data-done={subtask.completed || undefined}
        >
          <input
            type="checkbox"
            className={note ? 'postit-check' : checkbox}
            checked={subtask.completed}
            onChange={() => void toggleSubtask(subtask.id, !subtask.completed)}
            aria-label={`concluir subtarefa ${subtask.title}`}
          />
          <span className={cn('min-w-0 flex-1', note ? 'postit-subtask-text' : 'truncate')}>
            {subtask.title}
          </span>
          {note ? (
            <button
              type="button"
              className={cn('postit-icon-button postit-icon-button-danger', focusRing)}
              onClick={() => void removeSubtask(subtask.id)}
              aria-label={`apagar subtarefa ${subtask.title}`}
            >
              ×
            </button>
          ) : (
            <Button
              type="button"
              variant="ghost"
              size="icon-xs"
              className="shrink-0 text-ink-dim hover:bg-danger-tint hover:text-danger"
              onClick={() => void removeSubtask(subtask.id)}
              aria-label={`apagar subtarefa ${subtask.title}`}
            >
              ×
            </Button>
          )}
        </div>
      ))}
      {adding ? (
        <div className={note ? 'postit-subtask-add' : 'mt-1 flex gap-2'}>
          {note ? (
            <input
              className={cn('postit-input', focusRing)}
              value={newTitle}
              onChange={(e) => setNewTitle(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === 'Enter') void addSubtask();
                if (e.key === 'Escape') finishAdding();
              }}
              placeholder="nova subtarefa"
              aria-label={`nova subtarefa de ${task.title}`}
              autoFocus
            />
          ) : (
            <Input
              className="min-w-0 flex-1"
              value={newTitle}
              onChange={(e) => setNewTitle(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === 'Enter') void addSubtask();
                if (e.key === 'Escape') finishAdding();
              }}
              placeholder="nova subtarefa"
              aria-label={`nova subtarefa de ${task.title}`}
              autoFocus
            />
          )}
          {note ? (
            <button
              type="button"
              className={cn('postit-icon-button', focusRing)}
              onClick={() => void addSubtask()}
              aria-label="Adicionar subtarefa"
            >
              <Plus className="size-3.5" aria-hidden="true" />
            </button>
          ) : (
            <IconAction
              variant="outline"
              label="Adicionar subtarefa"
              onClick={() => void addSubtask()}
              icon={<Plus className="size-4" />}
            />
          )}
        </div>
      ) : (
        <button
          ref={addButton}
          type="button"
          className={cn(
            note
              ? 'postit-subtask-new'
              : 'mt-1 inline-flex h-7 w-fit items-center gap-1.5 rounded-full px-2 text-sm text-ink-dim transition-colors duration-100 ease-brand hover:bg-muted hover:text-ink motion-reduce:transition-none',
            focusRing,
          )}
          onClick={onStartAdding}
          aria-label={`adicionar subtarefa em ${task.title}`}
        >
          <Plus className="size-3.5" aria-hidden="true" />
          adicionar subtarefa
        </button>
      )}
    </div>
  );
}
