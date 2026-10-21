import { describe, expect, it } from 'vitest';
import type { PullJiraRef, PullRequestItem } from '@/lib/types';
import type { JiraTransition } from '@/lib/integrations/jira/transitions';
import { jiraSyncSuggestion, pickTransition, syncIntentOf } from '@/lib/pullJiraSync';

const PR: PullRequestItem = {
  id: 'PR_1',
  repo: 'acme/repo-1',
  number: 1,
  title: 'feat: TT-5019 Change 1',
  url: 'https://github.com/acme/repo-1/pull/1',
  author: 'viewer',
  draft: false,
  awaitingYou: false,
  mine: true,
  isPullRequest: true,
  updatedAt: '2026-10-21T10:00:00Z',
  createdAt: '2026-10-20T10:00:00Z',
  ci: 'passing',
  failedChecks: [],
  review: 'pending',
  pendingReviewers: [],
  merge: 'clean',
  size: null,
  headRef: 'feature/TT-5019-branch-1',
  baseRef: 'main',
  headSha: 'abc',
};

const ref = (statusCategory: PullJiraRef['statusCategory']): PullJiraRef => ({
  key: 'TT-5019',
  url: 'https://example.atlassian.net/browse/TT-5019',
  status: 'Backlog',
  statusCategory,
});

const DRAFT = { ...PR, draft: true };
const ISSUE = { ...PR, isPullRequest: false };

describe('jiraSyncSuggestion', () => {
  it('suggests moving a backlog card to review when the PR is ready', () => {
    expect(jiraSyncSuggestion(PR, ref('new'))).toEqual({ kind: 'move', intent: 'review' });
  });

  it('suggests moving a backlog card to in progress when the PR is a draft', () => {
    expect(jiraSyncSuggestion(DRAFT, ref('new'))).toEqual({ kind: 'move', intent: 'in-progress' });
  });

  it('flags a done card next to an open PR', () => {
    expect(jiraSyncSuggestion(PR, ref('done'))).toEqual({ kind: 'diverged', reason: 'done-with-open-pr' });
  });

  it('flags a done card next to an open draft PR', () => {
    expect(jiraSyncSuggestion(DRAFT, ref('done'))).toEqual({ kind: 'diverged', reason: 'done-with-open-pr' });
  });

  it('suggests nothing for a card already in progress', () => {
    expect(jiraSyncSuggestion(PR, ref('indeterminate'))).toBeNull();
  });

  it('suggests nothing for a draft whose card is already in progress', () => {
    expect(jiraSyncSuggestion(DRAFT, ref('indeterminate'))).toBeNull();
  });

  it.each(['new', 'indeterminate', 'done'] as const)('suggests nothing for an issue with a %s card', (category) => {
    expect(jiraSyncSuggestion(ISSUE, ref(category))).toBeNull();
  });
});

const t = (id: string, to: string, category: JiraTransition['to']['category']): JiraTransition => ({
  id,
  name: `transição ${id}`,
  to: { name: to, category },
  requires: 'nothing',
});

const TT_WORKFLOW = [
  t('2', 'Discovery', 'new'),
  t('9', 'Aguardando Dependência', 'indeterminate'),
  t('7', 'Code Review PR', 'indeterminate'),
  t('31', 'Em Andamento', 'indeterminate'),
  t('41', 'Concluído', 'done'),
];

describe('pickTransition', () => {
  it('picks the code review status for review', () => {
    expect(pickTransition(TT_WORKFLOW, 'review')?.id).toBe('7');
  });

  it('picks a status named "Em revisão" for review', () => {
    expect(pickTransition([t('9', 'Aguardando', 'indeterminate'), t('5', 'Em revisão', 'indeterminate')], 'review')?.id).toBe('5');
  });

  it('picks the in progress status for in-progress', () => {
    expect(pickTransition(TT_WORKFLOW, 'in-progress')?.id).toBe('31');
  });

  it('picks "In Progress" for in-progress', () => {
    expect(pickTransition([t('3', 'In Progress', 'indeterminate')], 'in-progress')?.id).toBe('3');
  });

  it('falls back to the first indeterminate target when no name matches', () => {
    const transitions = [t('2', 'Discovery', 'new'), t('9', 'Aguardando Dependência', 'indeterminate'), t('8', 'Doing', 'indeterminate')];
    expect(pickTransition(transitions, 'review')?.id).toBe('9');
  });

  it('finds nothing when no target is in progress or matches', () => {
    expect(pickTransition([t('2', 'Discovery', 'new'), t('41', 'Concluído', 'done')], 'in-progress')).toBeNull();
  });
});

describe('syncIntentOf', () => {
  it.each(['review', 'in-progress'])('accepts %s', (value) => {
    expect(syncIntentOf(value)).toBe(value);
  });

  it.each(['done', '', null, 'REVIEW'])('rejects %j', (value) => {
    expect(syncIntentOf(value)).toBeNull();
  });
});
