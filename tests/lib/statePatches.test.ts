import { describe, expect, it } from 'vitest';
import {
  countUnreadNotifications,
  markEmailsSeen,
  markNotificationRead,
  markNotificationsRead,
  removeEmails,
  removeTask,
  setSubtaskCompleted,
  setTaskCompleted,
  setTaskDoing,
  setTaskStyle,
} from '@/lib/statePatches';
import { defaultLayout } from '@/lib/dashboardLayout';
import type { DashboardState, EmailEnvelope, NotificationItem, TodoTask } from '@/lib/types';

function envelope(over: Partial<EmailEnvelope>): EmailEnvelope {
  return {
    id: '1',
    account: 'mail-1',
    accountLabel: 'Trabalho',
    from: 'Alguém',
    subject: 'Assunto',
    unread: true,
    date: '2026-08-26T10:00:00Z',
    messageId: '<a@b>',
    references: [],
    labels: [],
    mailbox: 'inbox' as const,
    folder: 'INBOX',
    ...over,
  };
}

function task(over: Partial<TodoTask>): TodoTask {
  return {
    id: 't1',
    title: 'Tarefa',
    completed: false,
    due: '',
    priority: 'normal',
    time: '',
    recur: '',
    notes: '',
    subtasks: [],
    doing: false,
    paper: null,
    pin: null,
    ...over,
  };
}

function notification(over: Partial<NotificationItem>): NotificationItem {
  return { id: 'ENG-1', source: 'jira_mention', title: 'ENG-1 — x', url: 'u', read: false, date: '2026-08-26T10:00:00Z', ...over };
}

function state(over: Partial<DashboardState> = {}): DashboardState {
  return {
    updatedAt: '2026-08-26T10:00:00Z',
    modules: ['email', 'tasks', 'jira'],
    mailboxes: [{ id: 'mail-1', label: 'Trabalho' }],
    agendaDays: 2,
    agendaCalendars: [],
    tasksView: 'list',
    layout: defaultLayout(),
    layouts: [],
    email: { data: [envelope({ id: '1' }), envelope({ id: '2' })], error: null },
    agenda: { data: [], error: null },
    pulls: { data: { items: [], errors: [], defaultBranches: [], truncated: [] }, error: null },
    reviewRequests: { data: { items: [], truncated: false, total: 0, scopeNote: null }, error: null },
    myPulls: { data: { items: [], truncated: false, total: 0 }, error: null },
    jira: { data: [], error: null },
    jiraWatched: { data: [], error: null },
    jiraDelivered: { data: [], error: null },
    jiraApproved: { data: [], error: null },
    jiraProblems: { data: [], error: null },
    jiraAncestors: [],
    jiraFollowedPeople: [],
    tasks: { data: [task({ id: 't1' }), task({ id: 't2' })], error: null },
    slack: { data: { mentions: [], directs: [], team: '' }, error: null },
    notifications: { data: [notification({ id: 'A' }), notification({ id: 'B' })], error: null },
    pomodoro: {
      enabled: true,
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

describe('markEmailsSeen', () => {
  it('marca só os alvos', () => {
    const next = markEmailsSeen(state(), [{ account: 'mail-1', id: '1' }], true);
    expect(next.email.data?.[0].unread).toBe(false);
    expect(next.email.data?.[1].unread).toBe(true);
  });

  it('desmarca também', () => {
    const lido = markEmailsSeen(state(), [{ account: 'mail-1', id: '1' }], true);
    const voltou = markEmailsSeen(lido, [{ account: 'mail-1', id: '1' }], false);
    expect(voltou.email.data?.[0].unread).toBe(true);
  });

  // Dois e-mails de caixas diferentes podem ter o mesmo uid: só o par
  // conta/id identifica a mensagem.
  it('não confunde o mesmo id em caixas diferentes', () => {
    const base = state({
      email: { data: [envelope({ id: '1', account: 'mail-1' }), envelope({ id: '1', account: 'mail-2' })], error: null },
    });
    const next = markEmailsSeen(base, [{ account: 'mail-1', id: '1' }], true);
    expect(next.email.data?.[0].unread).toBe(false);
    expect(next.email.data?.[1].unread).toBe(true);
  });

  it('não altera o estado original', () => {
    const base = state();
    markEmailsSeen(base, [{ account: 'mail-1', id: '1' }], true);
    expect(base.email.data?.[0].unread).toBe(true);
  });

  it('sobrevive a painel com erro e sem dados', () => {
    const base = state({ email: { data: null, error: 'caiu' } });
    expect(markEmailsSeen(base, [{ account: 'mail-1', id: '1' }], true)).toEqual(base);
  });
});

describe('removeEmails', () => {
  it('tira os alvos da lista', () => {
    const next = removeEmails(state(), [{ account: 'mail-1', id: '1' }]);
    expect(next.email.data?.map((e) => e.id)).toEqual(['2']);
  });

  it('aceita vários alvos de uma vez', () => {
    const next = removeEmails(state(), [
      { account: 'mail-1', id: '1' },
      { account: 'mail-1', id: '2' },
    ]);
    expect(next.email.data).toEqual([]);
  });
});

describe('markNotificationRead', () => {
  it('marca a notificação e derruba a contagem do badge', () => {
    const base = state();
    expect(countUnreadNotifications(base)).toBe(2);

    const next = markNotificationRead(base, 'A');
    expect(next.notifications.data?.find((n) => n.id === 'A')?.read).toBe(true);
    expect(countUnreadNotifications(next)).toBe(1);
  });

  it('ignora id desconhecido sem quebrar', () => {
    expect(countUnreadNotifications(markNotificationRead(state(), 'ZZZ'))).toBe(2);
  });
});

describe('markNotificationsRead', () => {
  it('zera o badge quando recebe o sino inteiro', () => {
    const base = state();
    const ids = (base.notifications.data ?? []).map((n) => n.id);

    const next = markNotificationsRead(base, ids);
    expect(countUnreadNotifications(next)).toBe(0);
    expect(next.notifications.data?.every((n) => n.read)).toBe(true);
  });

  it('deixa de fora quem não está na lista', () => {
    const next = markNotificationsRead(state(), ['A']);
    expect(next.notifications.data?.find((n) => n.id === 'A')?.read).toBe(true);
    expect(countUnreadNotifications(next)).toBe(1);
  });

  // Chamado com nada, devolve o mesmo estado: o refresher reaplica patches
  // sobre o retrato dele, e um objeto novo a cada chamada seria desperdício.
  it('devolve o mesmo estado para uma lista vazia', () => {
    const base = state();
    expect(markNotificationsRead(base, [])).toBe(base);
  });
});

describe('tarefas', () => {
  it('conclui e reabre', () => {
    const feita = setTaskCompleted(state(), 't1', true);
    expect(feita.tasks.data?.[0].completed).toBe(true);
    expect(setTaskCompleted(feita, 't1', false).tasks.data?.[0].completed).toBe(false);
  });

  it('põe e tira a tarefa de Fazendo', () => {
    const fazendo = setTaskDoing(state(), 't1', true);
    expect(fazendo.tasks.data?.[0].doing).toBe(true);
    expect(setTaskDoing(fazendo, 't1', false).tasks.data?.[0].doing).toBe(false);
  });

  // O servidor tira de Fazendo ao concluir; sem espelhar isto, o cartão
  // voltaria para Fazendo ao ser reaberto antes de o recarregamento chegar.
  it('concluir tira a tarefa de Fazendo', () => {
    const feita = setTaskCompleted(setTaskDoing(state(), 't1', true), 't1', true);
    expect(feita.tasks.data?.[0]).toMatchObject({ completed: true, doing: false });
  });

  it('muda só a cor informada, e null volta ao automático', () => {
    const rosa = setTaskStyle(state(), 't1', { paper: 'pink' });
    expect(rosa.tasks.data?.[0]).toMatchObject({ paper: 'pink', pin: null });
    const comAlfinete = setTaskStyle(rosa, 't1', { pin: 'blue' });
    expect(comAlfinete.tasks.data?.[0]).toMatchObject({ paper: 'pink', pin: 'blue' });
    expect(setTaskStyle(comAlfinete, 't1', { paper: null }).tasks.data?.[0]).toMatchObject({
      paper: null,
      pin: 'blue',
    });
    expect(comAlfinete.tasks.data?.[1]).toMatchObject({ paper: null, pin: null });
  });

  // A cor não é a coluna: concluir não pode apagar o que a pessoa escolheu.
  it('concluir mantém a cor', () => {
    const feita = setTaskCompleted(setTaskStyle(state(), 't1', { paper: 'grey' }), 't1', true);
    expect(feita.tasks.data?.[0]).toMatchObject({ completed: true, paper: 'grey' });
  });

  it('remove a tarefa', () => {
    expect(removeTask(state(), 't1').tasks.data?.map((t) => t.id)).toEqual(['t2']);
  });

  it('marca a subtarefa sem tocar nas outras', () => {
    const base = state({
      tasks: {
        data: [
          task({
            id: 't1',
            subtasks: [
              { id: 's1', title: 'a', completed: false },
              { id: 's2', title: 'b', completed: false },
            ],
          }),
        ],
        error: null,
      },
    });
    const next = setSubtaskCompleted(base, 't1', 's1', true);
    expect(next.tasks.data?.[0].subtasks[0].completed).toBe(true);
    expect(next.tasks.data?.[0].subtasks[1].completed).toBe(false);
  });

  it('não altera o estado original', () => {
    const base = state();
    setTaskCompleted(base, 't1', true);
    expect(base.tasks.data?.[0].completed).toBe(false);
  });
});
