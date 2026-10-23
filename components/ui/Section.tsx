import type { ReactNode } from 'react';
import { Panel } from '@/components/data/Panel';
import { tabular } from '@/lib/theme';

interface Props {
  eyebrow: ReactNode;
  count?: string;
  actions?: ReactNode;
  /** Para o painel que precisa impor altura ao próprio conteúdo. */
  className?: string;
  children: ReactNode;
}

/**
 * One block per topic. The card is what says where a topic ends, so there is no
 * rule under the header competing with it.
 */
export function Section({ eyebrow, count, actions, className, children }: Props) {
  return (
    <Panel
      className={className}
      title={
        <span className="flex items-baseline gap-2.5">
          {eyebrow}
          {count && <span className={`text-sm font-normal text-ink-dim ${tabular}`}>{count}</span>}
        </span>
      }
      action={actions}
    >
      {children}
    </Panel>
  );
}
