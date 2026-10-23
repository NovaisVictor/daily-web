import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { useDesktopAlerts } from '@/lib/hooks/useDesktopAlerts';
import type { DashboardState, EmailEnvelope } from '@/lib/types';

function email(id: string): EmailEnvelope {
  return {
    id,
    account: 'mail-1',
    accountLabel: 'Trabalho',
    from: 'Ana',
    subject: `Assunto ${id}`,
    unread: true,
    date: '2026-09-18T10:00:00Z',
    messageId: `<${id}@exemplo>`,
    references: [],
    labels: [],
    mailbox: 'inbox',
    folder: 'INBOX',
  };
}

function state(updatedAt: string, emails: EmailEnvelope[]): DashboardState {
  return {
    updatedAt,
    modules: ['email'],
    mailboxes: [],
    agendaDays: 2,
    agendaCalendars: [],
    tasksView: 'list',
    layout: [],
    layouts: [],
    email: { data: emails, error: null },
    agenda: { data: [], error: null },
    pulls: { data: { items: [], errors: [], defaultBranches: [], truncated: [] }, error: null },
    reviewRequests: {
      data: { items: [], truncated: false, total: 0, scopeNote: null },
      error: null,
    },
    myPulls: { data: { items: [], truncated: false, total: 0 }, error: null },
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
  };
}

class FakeNotification {
  static permission: NotificationPermission = 'granted';
  static requestPermission = vi.fn(async () => FakeNotification.permission);
  static instances: FakeNotification[] = [];

  onclick: ((event: Event) => void) | null = null;

  constructor(
    readonly title: string,
    readonly options?: NotificationOptions,
  ) {
    FakeNotification.instances.push(this);
  }

  close(): void {}
}

function Probe({ dashboard }: { dashboard: DashboardState }) {
  const desktop = useDesktopAlerts(dashboard);
  return (
    <button type="button" onClick={() => void desktop.enable()}>
      ligar
    </button>
  );
}

describe('useDesktopAlerts', () => {
  beforeEach(() => {
    localStorage.clear();
    FakeNotification.instances = [];
    FakeNotification.permission = 'granted';
    FakeNotification.requestPermission.mockClear();
    Object.defineProperty(window, 'Notification', {
      configurable: true,
      value: FakeNotification,
    });
  });

  afterEach(() => {
    cleanup();
    localStorage.clear();
    Reflect.deleteProperty(window, 'Notification');
    vi.restoreAllMocks();
  });

  it('não avisa na primeira leitura e avisa sobre e-mail da leitura seguinte', async () => {
    localStorage.setItem('daily-web.desktop-alerts.enabled', '1');
    const first = state('2026-09-18T10:00:00Z', [email('1')]);
    const { rerender } = render(<Probe dashboard={first} />);

    await waitFor(() => {
      const saved = localStorage.getItem('daily-web.desktop-alerts.v1');
      expect(saved).toContain('email:<1@exemplo>');
    });
    expect(FakeNotification.instances).toHaveLength(0);

    rerender(<Probe dashboard={state('2026-09-18T10:01:00Z', [email('1'), email('2')])} />);

    await waitFor(() => expect(FakeNotification.instances).toHaveLength(1));
    expect(FakeNotification.instances[0].title).toBe('Novo e-mail');
    expect(FakeNotification.instances[0].options?.tag).toBe('email:<2@exemplo>');
  });

  it('não mostra avisos quando está desligado', async () => {
    const { rerender } = render(
      <Probe dashboard={state('2026-09-18T10:00:00Z', [email('1')])} />,
    );
    await waitFor(() => expect(localStorage.getItem('daily-web.desktop-alerts.v1')).not.toBeNull());

    rerender(<Probe dashboard={state('2026-09-18T10:01:00Z', [email('1'), email('2')])} />);

    await waitFor(() => {
      expect(localStorage.getItem('daily-web.desktop-alerts.v1')).toContain('email:<2@exemplo>');
    });
    expect(FakeNotification.instances).toHaveLength(0);
  });

  it('registra itens enquanto desligado e não despeja o histórico ao ligar', async () => {
    const { rerender } = render(
      <Probe dashboard={state('2026-09-18T10:00:00Z', [email('1')])} />,
    );
    await waitFor(() => expect(localStorage.getItem('daily-web.desktop-alerts.v1')).not.toBeNull());
    rerender(<Probe dashboard={state('2026-09-18T10:01:00Z', [email('1'), email('2')])} />);
    await waitFor(() => {
      expect(localStorage.getItem('daily-web.desktop-alerts.v1')).toContain('email:<2@exemplo>');
    });

    fireEvent.click(screen.getByRole('button', { name: 'ligar' }));
    await waitFor(() => expect(FakeNotification.requestPermission).toHaveBeenCalledOnce());
    rerender(<Probe dashboard={state('2026-09-18T10:02:00Z', [email('1'), email('2')])} />);

    await waitFor(() => expect(localStorage.getItem('daily-web.desktop-alerts.enabled')).toBe('1'));
    expect(FakeNotification.instances).toHaveLength(0);
  });
});
