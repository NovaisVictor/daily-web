import { describe, expect, it } from 'vitest';
import {
  buildStandup,
  buildWeekly,
  previousWorkingDay,
  standupText,
  startOfWeek,
  weeklyText,
  type StandupSource,
} from '@/lib/standup';
import type { JiraDatedItem, JiraItem, PullRequestItem } from '@/lib/types';

const MONDAY = new Date(2026, 9, 19, 9, 30);
const WEDNESDAY = new Date(2026, 9, 21, 9, 30);

function at(day: number, hour = 15): string {
  return new Date(2026, 9, day, hour).toISOString();
}

function issue(over: Partial<JiraItem> = {}): JiraItem {
  return {
    key: 'A-1',
    summary: 'Resumo',
    status: 'Em andamento',
    statusCategory: 'indeterminate',
    project: 'A',
    url: 'https://example/A-1',
    parent: null,
    role: 'assignee',
    awaitingApproval: false,
    kind: 'História',
    subtask: false,
    hierarchyLevel: 0,
    updatedAt: at(20),
    dueDate: '',
    priority: null,
    flag: 'none',
    ...over,
  };
}

function dated(over: Partial<JiraDatedItem> = {}): JiraDatedItem {
  return { ...issue({ statusCategory: 'done', status: 'Resolvido' }), today: false, ...over };
}

function pull(over: Partial<PullRequestItem> = {}): PullRequestItem {
  return {
    id: 'PR_1',
    repo: 'acme/api',
    number: 7,
    title: 'feat: add login',
    url: 'https://github.com/acme/api/pull/7',
    author: 'viewer',
    draft: false,
    awaitingYou: false,
    mine: true,
    isPullRequest: true,
    updatedAt: at(20),
    createdAt: at(10),
    ci: 'passing',
    failedChecks: [],
    review: 'pending',
    pendingReviewers: [],
    reviewers: [],
    reviewRequestedAt: null,
    merge: 'clean',
    size: null,
    headRef: 'feature/login',
    baseRef: 'main',
    headSha: 'abc',
    ...over,
  };
}

function source(over: Partial<StandupSource> = {}): StandupSource {
  return { open: [], delivered: [], approved: [], myPulls: [], ...over };
}

describe('previousWorkingDay', () => {
  it('is the day before on a weekday', () => {
    expect(previousWorkingDay(WEDNESDAY)).toEqual(new Date(2026, 9, 20));
  });

  it('is Friday on a Monday', () => {
    expect(previousWorkingDay(MONDAY)).toEqual(new Date(2026, 9, 16));
  });

  it('is Friday over the weekend', () => {
    expect(previousWorkingDay(new Date(2026, 9, 17, 10))).toEqual(new Date(2026, 9, 16));
    expect(previousWorkingDay(new Date(2026, 9, 18, 10))).toEqual(new Date(2026, 9, 16));
  });
});

describe('buildStandup', () => {
  it('returns three empty sections when nothing is loaded', () => {
    expect(buildStandup(source(), WEDNESDAY)).toEqual({ yesterday: [], today: [], blockers: [] });
  });

  it('lists in yesterday what was delivered or approved since the previous working day', () => {
    const standup = buildStandup(
      source({
        delivered: [dated({ key: 'A-1', summary: 'Entregue' })],
        approved: [dated({ key: 'A-2', summary: 'Aprovada', updatedAt: at(20, 18) })],
      }),
      WEDNESDAY,
    );
    expect(standup.yesterday).toEqual(['A-1 — Entregue', 'A-2 — Aprovada']);
  });

  it('leaves out of yesterday what was closed today or before the previous working day', () => {
    const standup = buildStandup(
      source({
        delivered: [
          dated({ key: 'A-1', today: true, updatedAt: at(21, 8) }),
          dated({ key: 'A-2', updatedAt: at(19) }),
        ],
      }),
      WEDNESDAY,
    );
    expect(standup.yesterday).toEqual([]);
  });

  it('lists an issue both delivered and approved only once', () => {
    const standup = buildStandup(
      source({ delivered: [dated({ key: 'A-1' })], approved: [dated({ key: 'A-1' })] }),
      WEDNESDAY,
    );
    expect(standup.yesterday).toEqual(['A-1 — Resumo']);
  });

  it('reaches back to Friday on a Monday, weekend included', () => {
    const standup = buildStandup(
      source({
        delivered: [
          dated({ key: 'A-1', summary: 'Sexta', updatedAt: at(16) }),
          dated({ key: 'A-2', summary: 'Sábado', updatedAt: at(17) }),
          dated({ key: 'A-3', summary: 'Quinta', updatedAt: at(15) }),
        ],
        myPulls: [pull({ number: 1, title: 'Sexta', createdAt: at(16) })],
      }),
      MONDAY,
    );
    expect(standup.yesterday).toEqual(['A-1 — Sexta', 'A-2 — Sábado', 'acme/api#1 — Sexta']);
  });

  it('lists in yesterday the PRs opened since the previous working day, not the ones opened today', () => {
    const standup = buildStandup(
      source({
        myPulls: [
          pull({ number: 1, title: 'Ontem', createdAt: at(20) }),
          pull({ number: 2, title: 'Hoje', createdAt: at(21, 8) }),
          pull({ number: 3, title: 'Antes', createdAt: at(19) }),
          pull({ number: 4, title: 'Issue', createdAt: at(20), isPullRequest: false }),
        ],
      }),
      WEDNESDAY,
    );
    expect(standup.yesterday).toEqual(['acme/api#1 — Ontem']);
  });

  it('lists in today the assigned issues in progress', () => {
    const standup = buildStandup(
      source({
        open: [
          issue({ key: 'A-1', summary: 'Andando' }),
          issue({ key: 'A-2', summary: 'Ambos', role: 'both' }),
          issue({ key: 'A-3', statusCategory: 'new' }),
          issue({ key: 'A-4', role: 'reporter' }),
          issue({ key: 'A-5', awaitingApproval: true }),
          issue({ key: 'A-6', flag: 'impediment' }),
        ],
      }),
      WEDNESDAY,
    );
    expect(standup.today).toEqual(['A-1 — Andando', 'A-2 — Ambos']);
  });

  it('lists in blockers the assigned issues flagged as impeded, whatever their status', () => {
    const standup = buildStandup(
      source({
        open: [
          issue({ key: 'A-1', summary: 'Travada', flag: 'impediment' }),
          issue({ key: 'A-2', summary: 'A fazer', statusCategory: 'new', flag: 'impediment' }),
          issue({ key: 'A-3', role: 'reporter', flag: 'impediment' }),
          issue({ key: 'A-4' }),
        ],
      }),
      WEDNESDAY,
    );
    expect(standup.blockers).toEqual(['A-1 — Travada', 'A-2 — A fazer']);
  });

  it('lists in blockers each blocked PR with what blocks it', () => {
    const standup = buildStandup(
      source({
        myPulls: [
          pull({ number: 1, title: 'CI', ci: 'failing' }),
          pull({ number: 2, title: 'Revisão', review: 'changes-requested' }),
          pull({ number: 3, title: 'Conflito', merge: 'conflict' }),
          pull({ number: 4, title: 'Tudo', ci: 'failing', review: 'changes-requested', merge: 'conflict' }),
        ],
      }),
      WEDNESDAY,
    );
    expect(standup.blockers).toEqual([
      'acme/api#1 — CI (CI falhou)',
      'acme/api#2 — Revisão (pediram mudanças)',
      'acme/api#3 — Conflito (conflito)',
      'acme/api#4 — Tudo (CI falhou, pediram mudanças, conflito)',
    ]);
  });

  it('leaves out of blockers the PRs that wait on others and the drafts', () => {
    const standup = buildStandup(
      source({
        myPulls: [
          pull({ number: 1 }),
          pull({ number: 2, draft: true, ci: 'failing' }),
          pull({ number: 3, review: 'approved', merge: 'clean' }),
          pull({ number: 4, merge: 'unknown', ci: 'running' }),
        ],
      }),
      WEDNESDAY,
    );
    expect(standup.blockers).toEqual([]);
  });
});

describe('standupText', () => {
  it('writes each section with a placeholder when it is empty', () => {
    expect(standupText({ yesterday: [], today: [], blockers: [] })).toBe(
      'Ontem\n- Nada entregue\n\nHoje\n- Nada em andamento\n\nBloqueios\n- Nenhum',
    );
  });

  it('writes one line per item under its section', () => {
    expect(
      standupText({
        yesterday: ['A-1 — Entregue', 'acme/api#7 — feat: add login'],
        today: ['A-2 — Andando'],
        blockers: ['A-3 — Travada'],
      }),
    ).toBe(
      'Ontem\n- A-1 — Entregue\n- acme/api#7 — feat: add login\n\nHoje\n- A-2 — Andando\n\nBloqueios\n- A-3 — Travada',
    );
  });
});

describe('startOfWeek', () => {
  it('is the Monday of the current week', () => {
    expect(startOfWeek(WEDNESDAY)).toEqual(new Date(2026, 9, 19));
  });

  it('is the day itself on a Monday', () => {
    expect(startOfWeek(MONDAY)).toEqual(new Date(2026, 9, 19));
  });

  it('is the Monday just past on a Sunday', () => {
    expect(startOfWeek(new Date(2026, 9, 25, 10))).toEqual(new Date(2026, 9, 19));
  });
});

describe('buildWeekly', () => {
  it('returns three empty sections when nothing is loaded', () => {
    expect(buildWeekly(source(), WEDNESDAY)).toEqual({ delivered: [], pulls: [], blockers: [] });
  });

  it('lists what was delivered or approved since Monday, today included', () => {
    const weekly = buildWeekly(
      source({
        delivered: [
          dated({ key: 'A-1', summary: 'Segunda', updatedAt: at(19, 10) }),
          dated({ key: 'A-2', summary: 'Hoje', updatedAt: at(21, 8), today: true }),
        ],
        approved: [dated({ key: 'A-3', summary: 'Aprovada', updatedAt: at(20) })],
      }),
      WEDNESDAY,
    );
    expect(weekly.delivered).toEqual(['A-1 — Segunda', 'A-2 — Hoje', 'A-3 — Aprovada']);
  });

  it('leaves out what was closed before Monday', () => {
    const weekly = buildWeekly(
      source({ delivered: [dated({ key: 'A-1', updatedAt: at(16) })] }),
      WEDNESDAY,
    );
    expect(weekly.delivered).toEqual([]);
  });

  it('lists an issue both delivered and approved only once', () => {
    const weekly = buildWeekly(
      source({ delivered: [dated({ key: 'A-1' })], approved: [dated({ key: 'A-1' })] }),
      WEDNESDAY,
    );
    expect(weekly.delivered).toEqual(['A-1 — Resumo']);
  });

  it('lists the PRs opened since Monday, today included, and not the older ones', () => {
    const weekly = buildWeekly(
      source({
        myPulls: [
          pull({ number: 1, title: 'feat: segunda', createdAt: at(19, 9) }),
          pull({ number: 2, title: 'feat: hoje', createdAt: at(21, 8) }),
          pull({ number: 3, title: 'feat: antiga', createdAt: at(15) }),
          pull({ number: 4, title: 'issue', createdAt: at(20), isPullRequest: false }),
        ],
      }),
      WEDNESDAY,
    );
    expect(weekly.pulls).toEqual(['acme/api#1 — feat: segunda', 'acme/api#2 — feat: hoje']);
  });

  it('lists the same blockers as the daily summary', () => {
    const blocked = source({
      open: [issue({ key: 'A-9', summary: 'Travada', flag: 'impediment' })],
      myPulls: [pull({ ci: 'failing' })],
    });
    const { blockers } = buildWeekly(blocked, WEDNESDAY);
    expect(blockers).toHaveLength(2);
    expect(blockers).toEqual(buildStandup(blocked, WEDNESDAY).blockers);
  });
});

describe('weeklyText', () => {
  it('writes each section with a placeholder when it is empty', () => {
    expect(weeklyText({ delivered: [], pulls: [], blockers: [] })).toBe(
      'Entregue na semana\n- Nada entregue\n\nPRs abertos na semana\n- Nenhum\n\nBloqueios\n- Nenhum',
    );
  });
});
