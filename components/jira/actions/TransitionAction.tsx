'use client';

import type { ReactNode } from 'react';
import type { JiraItem } from '@/lib/types';

/** Slot T1: the status on the row becomes a picker of the allowed transitions. */
export function TransitionAction({ children }: { issue: JiraItem; children: ReactNode }) {
  return <>{children}</>;
}
