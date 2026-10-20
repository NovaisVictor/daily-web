'use client';

import { useState } from 'react';
import { MoreHorizontal } from 'lucide-react';
import type { JiraItem } from '@/lib/types';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import { cn } from '@/lib/utils';
import { focusRing } from '@/lib/theme';
import { FlagMenuItem, FlagDialog } from './actions/FlagAction';
import { CommentMenuItem, CommentDialog } from './actions/CommentAction';
import { EditMenuItems, EditDialogs } from './actions/EditActions';

/** Which dialog an item of the row menu opened. The dialog lives outside the
 *  menu because the menu unmounts as soon as an item is picked. */
export type IssueDialog = 'flag' | 'comment' | 'due' | 'priority' | 'assign' | 'create-story';

export interface MenuItemProps {
  issue: JiraItem;
  onOpen: (dialog: IssueDialog) => void;
}

export interface DialogProps {
  issue: JiraItem;
  open: IssueDialog | null;
  onClose: () => void;
}

/** The row's "⋯" menu: every write that is not the status or the approval. */
export function IssueActions({ issue }: { issue: JiraItem }) {
  const [open, setOpen] = useState<IssueDialog | null>(null);
  const onClose = () => setOpen(null);

  return (
    <>
      <DropdownMenu>
        <DropdownMenuTrigger asChild>
          <button
            type="button"
            className={cn(
              'inline-flex size-7 shrink-0 items-center justify-center rounded-md text-ink-dim hover:bg-muted hover:text-ink',
              focusRing,
            )}
            aria-label={`ações de ${issue.key}`}
          >
            <MoreHorizontal className="size-4" />
          </button>
        </DropdownMenuTrigger>
        <DropdownMenuContent align="end">
          <CommentMenuItem issue={issue} onOpen={setOpen} />
          <FlagMenuItem issue={issue} onOpen={setOpen} />
          <EditMenuItems issue={issue} onOpen={setOpen} />
        </DropdownMenuContent>
      </DropdownMenu>
      <CommentDialog issue={issue} open={open} onClose={onClose} />
      <FlagDialog issue={issue} open={open} onClose={onClose} />
      <EditDialogs issue={issue} open={open} onClose={onClose} />
    </>
  );
}
