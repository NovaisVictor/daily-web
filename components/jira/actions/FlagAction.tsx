'use client';

import type { JiraItem } from '@/lib/types';
import type { DialogProps, MenuItemProps } from '../IssueActions';

/** Slot T3: the flag shown on a row that is marked as impeded. */
export function FlagIndicator(_props: { issue: JiraItem }) {
  return null;
}

export function FlagMenuItem(_props: MenuItemProps) {
  return null;
}

export function FlagDialog(_props: DialogProps) {
  return null;
}
