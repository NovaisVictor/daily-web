'use client';

import type { JiraItem } from '@/lib/types';

/** Slot T2: the APROV badge, which becomes an approve / decline control. */
export function ApprovalBadge({ className, title }: { issue: JiraItem; className: string; title: string }) {
  return (
    <span className={className} title={title}>
      APROV
    </span>
  );
}
