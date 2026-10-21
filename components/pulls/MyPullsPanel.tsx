'use client';

import type { MyPullsDigest, PanelResult, PullRequestItem } from '@/lib/types';
import { PanelError } from '@/components/data/PanelError';
import { EmptyState } from '@/components/data/EmptyState';
import { SkeletonRows } from '@/components/ui/legacy-skeleton';
import { PullRow } from './PullRow';

/** Slot G3: the user's own PRs, grouped by what blocks them. */
export function MyPullsPanel({
  myPulls,
  items,
  loading,
}: {
  myPulls: PanelResult<MyPullsDigest>;
  /** Already filtered by the panel's filters. */
  items: PullRequestItem[];
  loading: boolean;
}) {
  return (
    <div id="pulls-panel-meus" role="tabpanel" aria-labelledby="pulls-tab-meus">
      {myPulls.error && <PanelError>{myPulls.error}</PanelError>}
      {loading && items.length === 0 && !myPulls.error && <SkeletonRows count={4} />}
      {!loading && items.length === 0 && !myPulls.error && <EmptyState title="Nenhum PR seu aberto." />}
      {items.length > 0 && (
        <ul className="text-sm">
          {items.map((item) => (
            <PullRow key={`${item.repo}#${item.number}`} item={item} withRepo />
          ))}
        </ul>
      )}
    </div>
  );
}
