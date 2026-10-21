import type { PullRequestItem } from '@/lib/types';

export type MyPullGroup = 'needs-you' | 'waiting-others' | 'ready' | 'draft';

export type MyPullBlocker = 'ci-failing' | 'changes-requested' | 'conflict';

export interface MyPullGroupEntry {
  group: MyPullGroup;
  items: PullRequestItem[];
}

const GROUP_ORDER: readonly MyPullGroup[] = ['needs-you', 'waiting-others', 'ready', 'draft'];

const BLOCKERS: readonly { blocker: MyPullBlocker; matches: (item: PullRequestItem) => boolean }[] = [
  { blocker: 'ci-failing', matches: (item) => item.ci === 'failing' },
  { blocker: 'changes-requested', matches: (item) => item.review === 'changes-requested' },
  { blocker: 'conflict', matches: (item) => item.merge === 'conflict' },
];

export function myPullBlockers(item: PullRequestItem): MyPullBlocker[] {
  return BLOCKERS.filter((rule) => rule.matches(item)).map((rule) => rule.blocker);
}

const GROUP_RULES: readonly { group: MyPullGroup; matches: (item: PullRequestItem) => boolean }[] = [
  { group: 'draft', matches: (item) => item.draft },
  { group: 'needs-you', matches: (item) => myPullBlockers(item).length > 0 },
  {
    group: 'ready',
    matches: (item) =>
      (item.review === 'approved' || item.review === 'none') &&
      (item.ci === 'passing' || item.ci === 'none') &&
      item.merge === 'clean',
  },
];

const FALLBACK_GROUP: MyPullGroup = 'waiting-others';

export function myPullGroup(item: PullRequestItem): MyPullGroup {
  return GROUP_RULES.find((rule) => rule.matches(item))?.group ?? FALLBACK_GROUP;
}

const OLDEST_FIRST: ReadonlySet<MyPullGroup> = new Set(['needs-you']);

function updatedTime(item: PullRequestItem): number {
  return Date.parse(item.updatedAt) || 0;
}

export function groupMyPulls(items: PullRequestItem[]): MyPullGroupEntry[] {
  return GROUP_ORDER.map((group) => {
    const direction = OLDEST_FIRST.has(group) ? 1 : -1;
    const grouped = items
      .filter((item) => myPullGroup(item) === group)
      .sort((a, b) => direction * (updatedTime(a) - updatedTime(b)));
    return { group, items: grouped };
  }).filter((entry) => entry.items.length > 0);
}
