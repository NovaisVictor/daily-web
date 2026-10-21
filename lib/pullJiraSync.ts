import type { PullJiraRef, PullRequestItem } from '@/lib/types';
import type { JiraTransition } from '@/lib/integrations/jira/transitions';

export type SyncIntent = 'review' | 'in-progress';

export type Suggestion =
  | { kind: 'move'; intent: SyncIntent }
  | { kind: 'diverged'; reason: 'done-with-open-pr' };

export const SYNC_INTENTS: readonly SyncIntent[] = ['review', 'in-progress'];

export function syncIntentOf(value: unknown): SyncIntent | null {
  return SYNC_INTENTS.find((intent) => intent === value) ?? null;
}

export const INTENT_LABEL: Record<SyncIntent, string> = {
  review: 'revisão',
  'in-progress': 'em andamento',
};

/** Only open items reach the panel, so a done card next to one is always out of step. */
export function jiraSyncSuggestion(item: PullRequestItem, ref: PullJiraRef): Suggestion | null {
  if (!item.isPullRequest) return null;
  if (ref.statusCategory === 'done') return { kind: 'diverged', reason: 'done-with-open-pr' };
  if (ref.statusCategory === 'new') return { kind: 'move', intent: item.draft ? 'in-progress' : 'review' };
  return null;
}

const TARGET_NAME: Record<SyncIntent, RegExp> = {
  review: /code review|revis(ã|a)o|review/i,
  'in-progress': /andamento|in progress/i,
};

/** Transition names and status names differ in Jira, so the match is on the
 *  target status. No match is no suggestion: guessing another "in progress"
 *  status would move the card somewhere the user did not ask for. */
export function pickTransition(transitions: JiraTransition[], intent: SyncIntent): JiraTransition | null {
  return transitions.find((t) => TARGET_NAME[intent].test(t.to.name)) ?? null;
}
