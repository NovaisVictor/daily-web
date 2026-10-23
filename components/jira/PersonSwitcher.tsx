'use client';

import { useRef, type RefObject } from 'react';
import { ChevronDown, UserPlus, X } from 'lucide-react';
import type { JiraPerson } from '@/lib/types';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuRadioGroup,
  DropdownMenuRadioItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import { cn } from '@/lib/utils';
import { focusRing } from '@/lib/theme';

interface Props {
  people: JiraPerson[];
  /** The followed person on screen, or null for the user's own Jira. */
  active: JiraPerson | null;
  onSelect: (accountId: string | 'eu') => void;
  onFollow: () => void;
  /** The person search field that "Acompanhar pessoa" opens, focused once the menu closes. */
  searchField: RefObject<HTMLInputElement | null>;
  onUnfollow: (accountId: string) => void;
}

/**
 * Whose Jira is on screen, as the panel title itself. It used to be a row of
 * tabs above the lists, taking a full line (more once a few people were
 * followed) on a fixed-height panel for something switched now and then; the
 * title already named the person, so the tabs only repeated it.
 */
export function PersonSwitcher({
  people,
  active,
  onSelect,
  onFollow,
  onUnfollow,
  searchField,
}: Props) {
  const seguindo = useRef(false);
  return (
    <DropdownMenu>
      {/* The visible text is the accessible name: "Jira · Eu" says both what
          the panel is and that it is someone's view, which "Jira" alone did not. */}
      <DropdownMenuTrigger
        className={cn(
          'inline-flex min-w-0 items-center gap-1 rounded-sm text-left hover:text-ink-mid',
          focusRing,
        )}
      >
        <span className="truncate">Jira · {active ? active.displayName : 'Eu'}</span>
        <ChevronDown aria-hidden className="size-4 shrink-0 text-ink-dim" />
      </DropdownMenuTrigger>
      <DropdownMenuContent
        align="start"
        className="min-w-56"
        // Radix gives focus back to the trigger on close, which would pull it
        // out of the search the item just opened: choosing it means typing a
        // name next, so the field gets the focus instead.
        onCloseAutoFocus={(e) => {
          if (!seguindo.current) return;
          seguindo.current = false;
          if (!searchField.current) return;
          e.preventDefault();
          searchField.current.focus();
        }}
      >
        <DropdownMenuRadioGroup
          value={active?.accountId ?? 'eu'}
          onValueChange={(value) => onSelect(value)}
        >
          <DropdownMenuRadioItem value="eu">Eu</DropdownMenuRadioItem>
          {people.map((p) => (
            <DropdownMenuRadioItem key={p.accountId} value={p.accountId}>
              {p.displayName}
            </DropdownMenuRadioItem>
          ))}
        </DropdownMenuRadioGroup>
        <DropdownMenuSeparator />
        <DropdownMenuItem
          onSelect={() => {
            seguindo.current = true;
            onFollow();
          }}
        >
          <UserPlus />
          Acompanhar pessoa
        </DropdownMenuItem>
        {active && (
          <DropdownMenuItem variant="destructive" onSelect={() => onUnfollow(active.accountId)}>
            <X />
            Parar de acompanhar {active.displayName}
          </DropdownMenuItem>
        )}
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
