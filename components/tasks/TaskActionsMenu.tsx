'use client';

import { useRef } from 'react';
import { CalendarPlus, ListPlus, MoreHorizontal, Pencil, Trash2 } from 'lucide-react';
import type { TodoTask } from '@/lib/types';
import { IconAction } from '@/components/data/IconAction';
import { useFocusBlock } from '@/components/FocusBlockProvider';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuRadioGroup,
  DropdownMenuRadioItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import { BOARD_COLUMNS, columnOf, type BoardColumn } from '@/lib/taskBoard';
import { cn } from '@/lib/utils';

interface Props {
  task: TodoTask;
  onEdit: () => void;
  onAddSubtask: () => void;
  onMove: (to: BoardColumn) => void;
  onDelete: () => void;
  /** On the board a move takes the note to another column, which focuses its
   *  title there; the menu must not then pull the focus back to a trigger
   *  that no longer exists. In the list the row stays, and so does the focus. */
  moveTakesFocus?: boolean;
  size?: 'icon-xs' | 'icon-sm';
  className?: string;
}

/**
 * Every action on one task, the same in the list and on the board, so neither
 * view can do something the other cannot.
 */
export function TaskActionsMenu({
  task,
  onEdit,
  onAddSubtask,
  onMove,
  onDelete,
  moveTakesFocus = false,
  size = 'icon-sm',
  className,
}: Props) {
  const focus = useFocusBlock();
  // Radix puts the focus back on the trigger when the menu closes. Some items
  // send it somewhere better (the new subtask field, the moved note), and that
  // must win.
  const keepFocus = useRef(false);

  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <IconAction
          label={`ações de ${task.title}`}
          icon={<MoreHorizontal className="size-4" />}
          size={size}
          className={cn('shrink-0', className)}
        />
      </DropdownMenuTrigger>
      <DropdownMenuContent
        align="end"
        onCloseAutoFocus={(event) => {
          if (keepFocus.current) event.preventDefault();
          keepFocus.current = false;
        }}
      >
        <DropdownMenuItem onSelect={onEdit}>
          <Pencil />
          Editar
        </DropdownMenuItem>
        <DropdownMenuItem
          onSelect={() => {
            keepFocus.current = true;
            onAddSubtask();
          }}
        >
          <ListPlus />
          Adicionar subtarefa
        </DropdownMenuItem>
        {focus.enabled && !task.completed && (
          <DropdownMenuItem
            onSelect={() => focus.schedule({ kind: 'task', ref: task.id, title: task.title })}
          >
            <CalendarPlus />
            Agendar foco
          </DropdownMenuItem>
        )}
        <DropdownMenuSeparator />
        <DropdownMenuLabel className="type-caption text-ink-dim">Mover para</DropdownMenuLabel>
        <DropdownMenuRadioGroup
          value={columnOf(task)}
          onValueChange={(value) => {
            const to = value as BoardColumn;
            if (to === columnOf(task)) return;
            keepFocus.current = moveTakesFocus;
            onMove(to);
          }}
        >
          {BOARD_COLUMNS.map((column) => (
            <DropdownMenuRadioItem key={column.key} value={column.key}>
              {column.label}
            </DropdownMenuRadioItem>
          ))}
        </DropdownMenuRadioGroup>
        <DropdownMenuSeparator />
        <DropdownMenuItem variant="destructive" onSelect={onDelete}>
          <Trash2 />
          Apagar
        </DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
