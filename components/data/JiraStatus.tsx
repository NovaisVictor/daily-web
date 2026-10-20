import type { JiraItem, JiraStatusCategory } from '@/lib/types';
import { normalizeStatus } from '@/lib/parsers/jira';
import { GLYPH } from './Status';
import { cn } from '@/lib/utils';

/**
 * A situation never borrows the accent: it would change hue whenever the accent
 * changes, with nothing about the issue having changed. The glyph carries the
 * state alongside the tone so the reading survives a grayscale print.
 */
const STATUS_TONE: Record<JiraStatusCategory, { glyph: string; tone: string }> = {
  new: { glyph: GLYPH.idle, tone: 'text-ink-dim' },
  indeterminate: { glyph: GLYPH.moving, tone: 'text-info' },
  done: { glyph: GLYPH.live, tone: 'text-success' },
};

/** The legacy `jira-status-<category>` class rides along: it is what the panel's
 *  tests reach for when they check which situation a row is showing. */
export function JiraStatus({ issue }: { issue: Pick<JiraItem, 'status' | 'statusCategory'> }) {
  const { glyph, tone } = STATUS_TONE[issue.statusCategory];
  return (
    <span className="inline-flex shrink-0 items-center gap-1.5 whitespace-nowrap">
      <span aria-hidden className={tone}>
        {glyph}
      </span>
      <span className={cn(tone, `jira-status-${issue.statusCategory}`)}>
        {normalizeStatus(issue.status)}
      </span>
    </span>
  );
}
