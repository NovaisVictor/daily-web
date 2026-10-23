import type { JiraDatedItem, JiraItem, PullRequestItem } from '@/lib/types';
import { MY_PULL_BLOCKER_LABEL, myPullBlockers, myPullGroup } from '@/lib/myPulls';

export interface StandupSource {
  open: JiraItem[];
  delivered: JiraDatedItem[];
  approved: JiraDatedItem[];
  myPulls: PullRequestItem[];
}

export interface Standup {
  yesterday: string[];
  today: string[];
  blockers: string[];
}

const SUNDAY = 0;
const MONDAY = 1;
const SATURDAY = 6;

function startOfDay(date: Date): Date {
  return new Date(date.getFullYear(), date.getMonth(), date.getDate());
}

function daysBefore(date: Date, days: number): Date {
  return new Date(date.getFullYear(), date.getMonth(), date.getDate() - days);
}

const DAYS_BACK_TO_FRIDAY: Record<number, number> = { [SUNDAY]: 2, [MONDAY]: 3, [SATURDAY]: 1 };

export function previousWorkingDay(now: Date): Date {
  return daysBefore(startOfDay(now), DAYS_BACK_TO_FRIDAY[now.getDay()] ?? 1);
}

function issueLine(item: JiraItem): string {
  return `${item.key} — ${item.summary}`;
}

function pullLine(item: PullRequestItem): string {
  return `${item.repo}#${item.number} — ${item.title}`;
}

function within(iso: string, from: Date, until: Date): boolean {
  const time = Date.parse(iso);
  return time >= from.getTime() && time < until.getTime();
}

// The delivered and approved lists only say whether an issue fell on today;
// `updatedAt` is the closest client-side proxy for "since the last working day".
function closedSince(items: JiraDatedItem[], from: Date): JiraDatedItem[] {
  const byKey = new Map<string, JiraDatedItem>();
  for (const item of items) {
    if (!item.today && Date.parse(item.updatedAt) >= from.getTime() && !byKey.has(item.key)) {
      byKey.set(item.key, item);
    }
  }
  return [...byKey.values()];
}

// An issue that only reached the list through a pending approval carries a
// neutral `assignee` role, so approval rows are left out of the user's own work.
function isOwnWork(item: JiraItem): boolean {
  return item.role !== 'reporter' && !item.awaitingApproval;
}

export function buildStandup(source: StandupSource, now: Date): Standup {
  const today = startOfDay(now);
  const from = previousWorkingDay(now);
  const own = source.open.filter(isOwnWork);
  const pulls = source.myPulls.filter((item) => item.isPullRequest);

  return {
    yesterday: [
      ...closedSince([...source.delivered, ...source.approved], from).map(issueLine),
      ...pulls.filter((item) => within(item.createdAt, from, today)).map(pullLine),
    ],
    today: own
      .filter((item) => item.statusCategory === 'indeterminate' && item.flag === 'none')
      .map(issueLine),
    blockers: [
      ...own.filter((item) => item.flag === 'impediment').map(issueLine),
      ...pulls
        .filter((item) => myPullGroup(item) === 'needs-you')
        .map(
          (item) =>
            `${pullLine(item)} (${myPullBlockers(item)
              .map((blocker) => MY_PULL_BLOCKER_LABEL[blocker])
              .join(', ')})`,
        ),
    ],
  };
}

const SECTIONS: readonly { title: string; lines: keyof Standup; empty: string }[] = [
  { title: 'Ontem', lines: 'yesterday', empty: 'Nada entregue' },
  { title: 'Hoje', lines: 'today', empty: 'Nada em andamento' },
  { title: 'Bloqueios', lines: 'blockers', empty: 'Nenhum' },
];

export function standupText(standup: Standup): string {
  return SECTIONS.map(({ title, lines, empty }) => {
    const items = standup[lines].length > 0 ? standup[lines] : [empty];
    return [title, ...items.map((line) => `- ${line}`)].join('\n');
  }).join('\n\n');
}
