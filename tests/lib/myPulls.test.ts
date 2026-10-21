import { describe, expect, it } from 'vitest';
import { groupMyPulls, myPullBlockers, myPullGroup } from '@/lib/myPulls';
import type { PullRequestItem } from '@/lib/types';

function pull(over: Partial<PullRequestItem> = {}): PullRequestItem {
  return {
    id: 'PR_1',
    repo: 'acme/repo-1',
    number: 1,
    title: 'feat: Change 1',
    url: 'https://github.com/acme/repo-1/pull/1',
    author: 'viewer',
    draft: false,
    awaitingYou: false,
    mine: true,
    isPullRequest: true,
    updatedAt: '2026-10-20T10:00:00Z',
    createdAt: '2026-10-19T10:00:00Z',
    ci: 'passing',
    failedChecks: [],
    review: 'pending',
    pendingReviewers: [],
    merge: 'clean',
    size: null,
    headRef: 'feature/x',
    baseRef: 'main',
    headSha: 'abc',
    ...over,
  };
}

describe('myPullGroup', () => {
  it('a draft is a draft even with failing CI', () => {
    expect(myPullGroup(pull({ draft: true, ci: 'failing' }))).toBe('draft');
  });

  it('failing CI needs you', () => {
    expect(myPullGroup(pull({ ci: 'failing' }))).toBe('needs-you');
  });

  it('requested changes need you', () => {
    expect(myPullGroup(pull({ review: 'changes-requested' }))).toBe('needs-you');
  });

  it('a merge conflict needs you', () => {
    expect(myPullGroup(pull({ merge: 'conflict' }))).toBe('needs-you');
  });

  it('a blocker wins over an approval', () => {
    expect(myPullGroup(pull({ review: 'approved', ci: 'failing' }))).toBe('needs-you');
  });

  it('approved, passing and clean is ready', () => {
    expect(myPullGroup(pull({ review: 'approved', ci: 'passing', merge: 'clean' }))).toBe('ready');
  });

  it('approved, without CI and clean is ready', () => {
    expect(myPullGroup(pull({ review: 'approved', ci: 'none', merge: 'clean' }))).toBe('ready');
  });

  it('approved and passing with mergeability not computed yet waits: it cannot be claimed to merge cleanly', () => {
    expect(myPullGroup(pull({ review: 'approved', ci: 'passing', merge: 'unknown' }))).toBe('waiting-others');
  });

  it('approved and passing but blocked by branch rules waits', () => {
    expect(myPullGroup(pull({ review: 'approved', merge: 'blocked' }))).toBe('waiting-others');
  });

  it('approved with CI still running waits', () => {
    expect(myPullGroup(pull({ review: 'approved', ci: 'running' }))).toBe('waiting-others');
  });

  it('a pending review waits', () => {
    expect(myPullGroup(pull({ review: 'pending' }))).toBe('waiting-others');
  });

  it('a repo without required review is ready once CI passes and GitHub says it merges cleanly', () => {
    expect(myPullGroup(pull({ review: 'none', ci: 'passing', merge: 'clean' }))).toBe('ready');
  });

  it('a repo without required review still waits while mergeability is not computed', () => {
    expect(myPullGroup(pull({ review: 'none', ci: 'passing', merge: 'unknown' }))).toBe('waiting-others');
  });

  it('an unknown CI state is not taken as failing', () => {
    expect(myPullGroup(pull({ review: 'approved', ci: 'unknown' }))).toBe('waiting-others');
  });

  it('an unknown review state is not taken as approved', () => {
    expect(myPullGroup(pull({ review: 'unknown' }))).toBe('waiting-others');
  });
});

describe('myPullBlockers', () => {
  it('lists every blocker in a fixed order', () => {
    expect(myPullBlockers(pull({ merge: 'conflict', ci: 'failing', review: 'changes-requested' }))).toEqual([
      'ci-failing',
      'changes-requested',
      'conflict',
    ]);
  });

  it('a PR without blockers has none', () => {
    expect(myPullBlockers(pull())).toEqual([]);
  });
});

describe('groupMyPulls', () => {
  it('orders groups needs-you, waiting-others, ready, draft', () => {
    const groups = groupMyPulls([
      pull({ number: 1, draft: true }),
      pull({ number: 2, review: 'approved' }),
      pull({ number: 3 }),
      pull({ number: 4, ci: 'failing' }),
    ]);
    expect(groups.map((entry) => entry.group)).toEqual(['needs-you', 'waiting-others', 'ready', 'draft']);
  });

  it('omits empty groups', () => {
    expect(groupMyPulls([pull({ draft: true })]).map((entry) => entry.group)).toEqual(['draft']);
  });

  it('returns no groups for no items', () => {
    expect(groupMyPulls([])).toEqual([]);
  });

  it('puts the oldest update first in needs-you', () => {
    const [needsYou] = groupMyPulls([
      pull({ number: 1, ci: 'failing', updatedAt: '2026-10-20T10:00:00Z' }),
      pull({ number: 2, ci: 'failing', updatedAt: '2026-10-01T10:00:00Z' }),
    ]);
    expect(needsYou.items.map((item) => item.number)).toEqual([2, 1]);
  });

  it('puts the most recent update first in the other groups', () => {
    const [waiting] = groupMyPulls([
      pull({ number: 1, updatedAt: '2026-10-01T10:00:00Z' }),
      pull({ number: 2, updatedAt: '2026-10-20T10:00:00Z' }),
    ]);
    expect(waiting.items.map((item) => item.number)).toEqual([2, 1]);
  });
});
