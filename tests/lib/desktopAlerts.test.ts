import { describe, expect, it } from 'vitest';
import {
  currentAlerts,
  diffAlerts,
  dueReminders,
  summarize,
  type SeenState,
} from '@/lib/desktopAlerts';
import type {
  AgendaItem,
  DashboardState,
  EmailEnvelope,
  JiraItem,
  JiraProblemItem,
  PullRequestItem,
} from '@/lib/types';

const vazio = (): SeenState => ({ v: 1, sources: {}, reminders: [] });

function email(over: Partial<EmailEnvelope> = {}): EmailEnvelope {
  return {
    id: '1',
    account: 'mail-1',
    accountLabel: 'Trabalho',
    from: 'Ana',
    subject: 'Novidades',
    unread: true,
    date: '2026-09-18T10:00:00Z',
    messageId: '<1@exemplo>',
    references: [],
    labels: [],
    mailbox: 'inbox',
    folder: 'INBOX',
    ...over,
  };
}

function jira(over: Partial<JiraItem> = {}): JiraItem {
  return {
    key: 'WEB-1',
    summary: 'Corrigir painel',
    status: 'Aberta',
    statusCategory: 'new',
    project: 'WEB',
    url: 'https://jira/WEB-1',
    parent: null,
    role: 'assignee',
    awaitingApproval: false,
    kind: 'Story',
    subtask: false,
    hierarchyLevel: null,
    updatedAt: '2026-09-18T10:00:00Z',
    dueDate: '',
    priority: null,
    flag: 'none',
    ...over,
  };
}

function problem(over: Partial<JiraProblemItem> = {}): JiraProblemItem {
  return { ...jira(), problems: ['story-without-epic'], ...over };
}

function pull(over: Partial<PullRequestItem> = {}): PullRequestItem {
  return {
    repo: 'time/site',
    number: 7,
    title: 'Melhora login',
    url: 'https://github/pull/7',
    author: 'ana',
    draft: false,
    awaitingYou: false,
    mine: false,
    isPullRequest: true,
    updatedAt: '2026-09-18T10:00:00Z',
    ...over,
  };
}

function event(over: Partial<AgendaItem> = {}): AgendaItem {
  return {
    account: 'agenda-1',
    accountLabel: 'Trabalho',
    date: '2026-09-18',
    time: '10:00',
    title: 'Planejamento',
    ...over,
  };
}

function state(over: Partial<DashboardState> = {}): DashboardState {
  return {
    updatedAt: '2026-09-18T10:00:00Z',
    modules: [],
    mailboxes: [],
    agendaDays: 2,
    agendaCalendars: [],
    layout: [],
    layouts: [],
    email: { data: [], error: null },
    agenda: { data: [], error: null },
    pulls: { data: { items: [], errors: [] }, error: null },
    reviewRequests: {
      data: { items: [], truncated: false, total: 0, scopeNote: null },
      error: null,
    },
    jira: { data: [], error: null },
    jiraWatched: { data: [], error: null },
    jiraFollowedPeople: [],
    jiraDelivered: { data: [], error: null },
    jiraApproved: { data: [], error: null },
    jiraProblems: { data: [], error: null },
    jiraAncestors: [],
    tasks: { data: [], error: null },
    slack: { data: { mentions: [], directs: [], team: '' }, error: null },
    notifications: { data: [], error: null },
    pomodoro: {
      enabled: false,
      phase: 'focus',
      running: false,
      remainingSeconds: 1500,
      focusMinutes: 25,
      restMinutes: 5,
      completedFocusCount: 0,
    },
    nextRefreshAt: null,
    ...over,
  };
}

describe('diffAlerts', () => {
  it('inclui menções e mensagens diretas do Slack', () => {
    const alerts = currentAlerts(state({
      slack: {
        data: {
          team: 'Equipe',
          mentions: [{ id: 'C1:1', channel: '#geral', author: 'Ana', text: 'Oi', date: '2026-09-21T10:00:00Z', url: 'https://equipe.slack.com/x' }],
          directs: [{ id: 'D1:2', channel: 'mensagem direta', author: 'Bia', text: 'Olá', date: '2026-09-21T11:00:00Z', url: '' }],
        },
        error: null,
      },
    })).slack;
    expect(alerts?.get('slack:C1:1')?.title).toBe('Menção no Slack');
    expect(alerts?.get('slack:D1:2')?.title).toBe('Mensagem no Slack');
  });

  it('faz a primeira leitura virar linha de base sem avisar', () => {
    const result = diffAlerts(vazio(), currentAlerts(state({ email: { data: [email()], error: null } })));

    expect(result.alerts).toEqual([]);
    expect(result.seen.sources.email).toEqual(['email:<1@exemplo>']);
  });

  it('avisa só sobre e-mail novo, não lido e da caixa de entrada', () => {
    const seen: SeenState = { ...vazio(), sources: { email: ['email:<1@exemplo>'] } };
    const result = diffAlerts(
      seen,
      currentAlerts(state({
        email: {
          data: [
            email(),
            email({ id: '2', messageId: '<2@exemplo>' }),
            email({ id: '3', messageId: '<3@exemplo>', unread: false }),
            email({ id: '4', messageId: '<4@exemplo>', mailbox: 'sent' }),
          ],
          error: null,
        },
      })),
    );

    expect(result.alerts.map((alert) => alert.tag)).toEqual(['email:<2@exemplo>']);
    expect(result.alerts[0].body).toBe('Ana — Novidades');
  });

  it('avisa sobre issues como responsável ou ambos, mas não como relator', () => {
    const result = diffAlerts(
      { ...vazio(), sources: { jira: [] } },
      currentAlerts(state({
        jira: {
          data: [
            jira({ key: 'WEB-1', role: 'reporter' }),
            jira({ key: 'WEB-2', role: 'assignee' }),
            jira({ key: 'WEB-3', role: 'both' }),
          ],
          error: null,
        },
      })),
    );

    expect(result.alerts.map((alert) => alert.tag)).toEqual(['jira:WEB-2', 'jira:WEB-3']);
  });

  it('diz que a aprovação está pendente quando a issue só espera a sua decisão', () => {
    const result = diffAlerts(
      { ...vazio(), sources: { jira: [] } },
      currentAlerts(state({
        jira: {
          data: [
            jira({ key: 'WEB-4', role: 'assignee', awaitingApproval: true }),
            jira({ key: 'WEB-5', role: 'assignee' }),
          ],
          error: null,
        },
      })),
    );

    expect(result.alerts.map((alert) => alert.title)).toEqual([
      'Aprovação pendente',
      'Nova issue no seu nome',
    ]);
  });

  it('avisa quando surge um problema novo numa issue já conhecida e não repete', () => {
    const first = diffAlerts(
      { ...vazio(), sources: { jiraProblem: ['jira-problem:WEB-1:story-without-epic'] } },
      currentAlerts(state({
        jiraProblems: {
          data: [problem({ problems: ['story-without-epic', 'story-done-without-start'] })],
          error: null,
        },
      })),
    );
    const second = diffAlerts(first.seen, currentAlerts(state({
      jiraProblems: {
        data: [problem({ problems: ['story-without-epic', 'story-done-without-start'] })],
        error: null,
      },
    })));

    expect(first.alerts.map((alert) => alert.tag)).toEqual([
      'jira-problem:WEB-1:story-done-without-start',
    ]);
    expect(second.alerts).toEqual([]);
  });

  it('ignora PR próprio e issue do GitHub, mas avisa revisão pedida', () => {
    const result = diffAlerts(
      { ...vazio(), sources: { pull: [], review: [] } },
      currentAlerts(state({
        pulls: {
          data: {
            items: [pull({ number: 1, mine: true }), pull({ number: 2, isPullRequest: false })],
            errors: [],
          },
          error: null,
        },
        reviewRequests: {
          data: { items: [pull({ number: 3 })], truncated: false, total: 1, scopeNote: null },
          error: null,
        },
      })),
    );

    expect(result.alerts.map((alert) => alert.tag)).toEqual(['review:time/site#3']);
  });

  it('não avisa nem esquece uma fonte sem dados e não repete quando ela volta', () => {
    const seen: SeenState = { ...vazio(), sources: { email: ['email:<1@exemplo>'] } };
    const failed = diffAlerts(
      seen,
      currentAlerts(state({ email: { data: null, error: 'indisponível' } })),
    );
    const recovered = diffAlerts(
      failed.seen,
      currentAlerts(state({ email: { data: [email()], error: null } })),
    );

    expect(failed.alerts).toEqual([]);
    expect(failed.seen.sources.email).toEqual(['email:<1@exemplo>']);
    expect(recovered.alerts).toEqual([]);
  });

  it('avisa sobre evento novo com data curta e marca o dia inteiro', () => {
    const result = diffAlerts(
      { ...vazio(), sources: { agenda: [] } },
      currentAlerts(state({ agenda: { data: [event({ time: '' })], error: null } })),
    );

    expect(result.alerts).toEqual([
      expect.objectContaining({
        tag: 'agenda:agenda-1|2026-09-18||Planejamento',
        body: '18/09 dia inteiro — Planejamento',
      }),
    ]);
  });
});

describe('dueReminders', () => {
  const now = new Date(2026, 8, 18, 10, 0, 0);

  it('avisa uma vez sobre evento em nove minutos', () => {
    const first = dueReminders([event({ time: '10:09' })], now, vazio());
    const second = dueReminders([event({ time: '10:09' })], now, first.seen);

    expect(first.alerts).toEqual([
      expect.objectContaining({ title: 'Em 9 min', body: '10:09 — Planejamento' }),
    ]);
    expect(second.alerts).toEqual([]);
  });

  it('ignora evento em onze minutos, evento de dia inteiro e evento passado', () => {
    const result = dueReminders(
      [event({ time: '10:11' }), event({ title: 'Feriado', time: '' }), event({ time: '09:59' })],
      now,
      vazio(),
    );

    expect(result.alerts).toEqual([]);
  });

  it('remove chaves antigas e mantém as recentes', () => {
    const recent = event({ time: '09:00', title: 'Recente' });
    const old = event({ date: '2026-09-16', time: '09:00', title: 'Antigo' });
    const seen: SeenState = {
      ...vazio(),
      reminders: [
        'reminder:agenda-1|2026-09-18|09:00|Recente',
        'reminder:agenda-1|2026-09-16|09:00|Antigo',
      ],
    };

    expect(dueReminders([recent, old], now, seen).seen.reminders).toEqual([
      'reminder:agenda-1|2026-09-18|09:00|Recente',
    ]);
  });
});

describe('summarize', () => {
  const alerts = Array.from({ length: 6 }, (_, index) => ({
    tag: String(index),
    title: 'Aviso',
    body: 'Corpo',
    url: '',
  }));

  it('resume seis avisos em um só', () => {
    expect(summarize(alerts)).toEqual([
      { tag: 'resumo', title: 'daily-web', body: '6 novidades no painel', url: '' },
    ]);
  });

  it('mantém cinco avisos sem alteração', () => {
    expect(summarize(alerts.slice(0, 5))).toEqual(alerts.slice(0, 5));
  });
});
