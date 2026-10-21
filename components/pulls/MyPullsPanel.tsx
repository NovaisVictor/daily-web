'use client';

import type { MyPullsDigest, PanelResult, PullRequestItem } from '@/lib/types';
import { PanelError } from '@/components/data/PanelError';
import { EmptyState } from '@/components/data/EmptyState';
import { SkeletonRows } from '@/components/ui/legacy-skeleton';
import { tabular } from '@/lib/theme';
import { groupMyPulls, myPullBlockers, type MyPullBlocker, type MyPullGroup } from '@/lib/myPulls';
import { PullRow } from './PullRow';

const GROUP_LABEL: Record<MyPullGroup, string> = {
  'needs-you': 'Precisa de você',
  'waiting-others': 'Esperando os outros',
  ready: 'Pronto para merge',
  draft: 'Rascunho',
};

const BLOCKER_LABEL: Record<MyPullBlocker, string> = {
  'ci-failing': 'CI falhou',
  'changes-requested': 'pediram mudanças',
  conflict: 'conflito',
};

function blockerReason(item: PullRequestItem): string {
  return myPullBlockers(item)
    .map((blocker) => BLOCKER_LABEL[blocker])
    .join(', ');
}

function rowKey(item: PullRequestItem): string {
  return `${item.repo}#${item.number}`;
}

/** Slot G3: the user's own PRs, grouped by what blocks them. */
export function MyPullsPanel({
  myPulls,
  items,
  loading,
  filteredOut = false,
}: {
  myPulls: PanelResult<MyPullsDigest>;
  /** Already filtered by the panel's filters. */
  items: PullRequestItem[];
  loading: boolean;
  /** The user has PRs, but the panel's filters hide them all. */
  filteredOut?: boolean;
}) {
  const digest = myPulls.data;
  return (
    <div id="pulls-panel-meus" role="tabpanel" aria-labelledby="pulls-tab-meus">
      {myPulls.error && <PanelError>{myPulls.error}</PanelError>}
      {(digest?.errors ?? []).length > 0 && <PanelError>{digest?.errors?.join('; ')}</PanelError>}
      {loading && items.length === 0 && !myPulls.error && <SkeletonRows count={4} />}
      {!loading && items.length === 0 && !myPulls.error && (
        <EmptyState title={filteredOut ? 'Nenhum resultado para os filtros.' : 'Nenhum PR seu aberto.'} />
      )}

      {groupMyPulls(items).map(({ group, items: groupItems }) => {
        const headingId = `pulls-meus-${group}`;
        return (
          <section key={group} aria-labelledby={headingId} className="mb-6 last:mb-0">
            <h3 id={headingId} className="type-subhead mb-2 border-b border-line pb-2">
              {GROUP_LABEL[group]}{' '}
              <span className={`font-normal normal-case ${tabular}`}>{groupItems.length}</span>
            </h3>
            {group === 'needs-you' ? (
              <ul className="text-sm">
                {groupItems.map((item) => (
                  <li key={rowKey(item)}>
                    <p className="type-caption px-2 pt-2 text-danger">{blockerReason(item)}</p>
                    <ul>
                      <PullRow item={item} withRepo />
                    </ul>
                  </li>
                ))}
              </ul>
            ) : (
              <ul className="text-sm">
                {groupItems.map((item) => (
                  <PullRow key={rowKey(item)} item={item} withRepo />
                ))}
              </ul>
            )}
          </section>
        );
      })}

      {digest?.truncated && (
        <p className="type-caption mt-3 text-ink-dim">
          Mostrando {items.length} de {digest.total}: a busca traz uma página por ciclo.
        </p>
      )}
    </div>
  );
}
