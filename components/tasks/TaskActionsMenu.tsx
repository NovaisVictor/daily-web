'use client';

import { useRef, useState } from 'react';
import { CalendarPlus, ListPlus, MoreHorizontal, Palette, Pencil, Trash2 } from 'lucide-react';
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
import { Popover, PopoverAnchor, PopoverContent } from '@/components/ui/popover';
import { BOARD_COLUMNS, columnOf, derivedPaper, type BoardColumn } from '@/lib/taskBoard';
import { NoteColourPicker, type NoteStyle } from './NoteColourPicker';
import { cn } from '@/lib/utils';

interface Props {
  task: TodoTask;
  onEdit: () => void;
  onAddSubtask: () => void;
  onMove: (to: BoardColumn) => void;
  /** One pick of the note's paper or pin, saved at once. */
  onStyleChange: (patch: Partial<NoteStyle>) => void;
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
  onStyleChange,
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
  const trigger = useRef<HTMLButtonElement>(null);
  // The colours open beside the menu's button rather than inside the menu: a
  // menu closes on every pick, and choosing a paper and then a pin would mean
  // opening it twice.
  const [colourOpen, setColourOpen] = useState(false);
  // Opened only once the menu has fully closed: while its focus trap is still
  // up it pulls the focus back, and the popover reads that as a click outside
  // and closes in the same instant it opened.
  const colourPending = useRef(false);

  return (
    <Popover open={colourOpen} onOpenChange={setColourOpen}>
      <DropdownMenu>
        <PopoverAnchor asChild>
          <DropdownMenuTrigger asChild>
            <IconAction
              ref={trigger}
              label={`ações de ${task.title}`}
              icon={<MoreHorizontal className="size-4" />}
              size={size}
              className={cn('shrink-0', className)}
            />
          </DropdownMenuTrigger>
        </PopoverAnchor>
        <DropdownMenuContent
          align="end"
          onCloseAutoFocus={(event) => {
            if (keepFocus.current) event.preventDefault();
            keepFocus.current = false;
            if (colourPending.current) {
              colourPending.current = false;
              setColourOpen(true);
            }
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
          <DropdownMenuItem
            onSelect={() => {
              // The popover takes the focus; the menu must not pull it back to
              // the trigger on its way out.
              keepFocus.current = true;
              colourPending.current = true;
            }}
          >
            <Palette />
            Cor da nota…
          </DropdownMenuItem>
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
      <PopoverContent
        align="end"
        aria-label={`cor da nota de ${task.title}`}
        // Opaque, unlike the glass popovers elsewhere: it opens over the
        // notes, and bright paper bleeding through the blur made the swatches
        // and the clash warning hard to read.
        className="w-80 max-w-[calc(100vw-2rem)] bg-surface-3"
        // Anchored, not triggered, so Radix has no trigger to give the focus
        // back to; without this it would fall to the page.
        onCloseAutoFocus={(event) => {
          event.preventDefault();
          trigger.current?.focus();
        }}
      >
        <p className="mb-3 text-sm font-medium text-ink">Cor da nota</p>
        <NoteColourPicker
          value={{ paper: task.paper, pin: task.pin }}
          automaticPaper={derivedPaper(task)}
          onChange={onStyleChange}
        />
      </PopoverContent>
    </Popover>
  );
}
