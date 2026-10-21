import { describe, expect, it, beforeEach, vi } from 'vitest';
import { mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';

beforeEach(() => {
  vi.resetModules();
  const dbPath = path.join(mkdtempSync(path.join(tmpdir(), 'daily-web-db-')), 'test.db');
  process.env.DAILY_WEB_DB_PATH = dbPath;
});

describe('notifications_read', () => {
  it('marca uma notificação como lida e não a esquece', async () => {
    const { markRead, isRead } = await import('@/lib/notifications');
    expect(isRead('u-1', 'jira_mention', 'ENG-1')).toBe(false);
    markRead('u-1', 'jira_mention', 'ENG-1');
    expect(isRead('u-1', 'jira_mention', 'ENG-1')).toBe(true);
  });

  it('marcar duas vezes não falha (idempotente)', async () => {
    const { markRead, isRead } = await import('@/lib/notifications');
    markRead('u-1', 'jira_mention', 'ENG-1');
    markRead('u-1', 'jira_mention', 'ENG-1');
    expect(isRead('u-1', 'jira_mention', 'ENG-1')).toBe(true);
  });

  it('fontes diferentes com o mesmo id externo não se confundem', async () => {
    const { markRead, isRead } = await import('@/lib/notifications');
    markRead('u-1', 'jira_mention', 'X-1');
    expect(isRead('u-1', 'outra_fonte', 'X-1')).toBe(false);
  });
});

const JIRA_CONNECTION = {
  id: 'jira-1',
  module: 'jira' as const,
  label: 'Jira',
  values: { cloud: 'acme', email: 'a@x.com', token: 't' },
};

describe('getNotifications', () => {
  it('marca como lidas as issues já dispensadas antes', async () => {
    vi.doMock('@/lib/integrations/jiraApi', () => ({
      fetchMentions: vi.fn(async () => [
        {
          key: 'ENG-1', summary: 'Corrigir bug', status: '', project: 'ENG',
          url: 'https://x/ENG-1', parent: null, role: 'assignee' as const, kind: '', subtask: false,
        },
      ]),
    }));
    const { markRead, getNotifications } = await import('@/lib/notifications');
    markRead('u-1', 'jira_mention', 'ENG-1');
    const items = await getNotifications('u-1', JIRA_CONNECTION);
    expect(items).toHaveLength(1);
    expect(items[0].read).toBe(true);
    expect(items[0].title).toContain('ENG-1');
  });

  it('não vaza o estado de lida entre usuários', async () => {
    vi.doMock('@/lib/integrations/jiraApi', () => ({
      fetchMentions: vi.fn(async () => [
        {
          key: 'ENG-1', summary: 'Corrigir bug', status: '', project: 'ENG',
          url: 'https://x/ENG-1', parent: null, role: 'assignee' as const, kind: '', subtask: false,
        },
      ]),
    }));
    const { markRead, getNotifications } = await import('@/lib/notifications');
    markRead('u-1', 'jira_mention', 'ENG-1');
    const items = await getNotifications('u-2', JIRA_CONNECTION);
    expect(items[0].read).toBe(false);
  });
});

function pull(over: Record<string, unknown> = {}) {
  return {
    repo: 'joao/daily-web', number: 12, title: 'Corrige o login',
    url: 'https://github.com/joao/daily-web/pull/12', author: 'alguem',
    draft: false, awaitingYou: false, mine: false, isPullRequest: true,
    id: 'PR_test', createdAt: '', ci: 'none' as const, failedChecks: [], review: 'none' as const, pendingReviewers: [],
    merge: 'unknown' as const, size: { additions: 1, deletions: 1, files: 1 }, headRef: 'feature/x', baseRef: 'main', headSha: 'abc123',
    updatedAt: '2026-08-30T10:00:00Z', ...over,
  };
}

function envelope(over: Record<string, unknown> = {}) {
  return {
    id: '10', account: 'mail-1', accountLabel: 'Trabalho', from: 'Milton',
    subject: 'Revisão', unread: true, date: '2026-08-30T10:00:00Z',
    messageId: '<a@x>', references: [], labels: [], mailbox: 'inbox' as const,
    folder: 'INBOX', ...over,
  };
}

describe('notificationId', () => {
  it('vai e volta, preservando a fonte e o id externo', async () => {
    const { notificationId, parseNotificationId } = await import('@/lib/notifications');
    const id = notificationId('pull_request', 'joao/daily-web#12');
    expect(parseNotificationId(id)).toEqual({
      source: 'pull_request', externalId: 'joao/daily-web#12',
    });
  });

  // O id externo do e-mail traz ':' dentro. Se a volta cortasse em todo ':',
  // o id externo sairia truncado e o "lido" seria gravado com a chave errada.
  it('preserva o id externo que contém dois-pontos', async () => {
    const { notificationId, parseNotificationId } = await import('@/lib/notifications');
    const id = notificationId('email', 'mail-1:<a:b@x>');
    expect(parseNotificationId(id)?.externalId).toBe('mail-1:<a:b@x>');
  });

  it('recusa um id sem fonte conhecida', async () => {
    const { parseNotificationId } = await import('@/lib/notifications');
    expect(parseNotificationId('ENG-1')).toBeNull();
    expect(parseNotificationId('inventada:X-1')).toBeNull();
  });
});

describe('pullNotifications', () => {
  it('avisa de cada pull request aberto', async () => {
    const { pullNotifications } = await import('@/lib/notifications');
    const items = pullNotifications('u-1', [pull()]);
    expect(items).toHaveLength(1);
    expect(items[0].source).toBe('pull_request');
    expect(items[0].title).toContain('#12');
    expect(items[0].url).toBe('https://github.com/joao/daily-web/pull/12');
    expect(items[0].read).toBe(false);
  });

  // O painel traz issues e PRs na mesma lista; o pedido é avisar de PR.
  it('ignora o que é issue, não pull request', async () => {
    const { pullNotifications } = await import('@/lib/notifications');
    expect(pullNotifications('u-1', [pull({ isPullRequest: false })])).toHaveLength(0);
  });

  it('lembra do que já foi dispensado', async () => {
    const { markRead, pullNotifications } = await import('@/lib/notifications');
    markRead('u-1', 'pull_request', 'joao/daily-web#12');
    expect(pullNotifications('u-1', [pull()])[0].read).toBe(true);
  });

  it('não deixa uma enxurrada de PRs afogar o sino', async () => {
    const { pullNotifications } = await import('@/lib/notifications');
    const muitos = Array.from({ length: 50 }, (_, i) => pull({ number: i + 1 }));
    expect(pullNotifications('u-1', muitos)).toHaveLength(20);
  });
});

describe('emailNotifications', () => {
  it('avisa do e-mail que chegou e não foi lido', async () => {
    const { emailNotifications } = await import('@/lib/notifications');
    const items = emailNotifications('u-1', [envelope()]);
    expect(items).toHaveLength(1);
    expect(items[0].source).toBe('email');
    expect(items[0].title).toContain('Revisão');
  });

  it('não avisa do que já foi lido na caixa', async () => {
    const { emailNotifications } = await import('@/lib/notifications');
    expect(emailNotifications('u-1', [envelope({ unread: false })])).toHaveLength(0);
  });

  // Os enviados entram na lista para compor conversa; nada do que você
  // mandou é "e-mail novo".
  it('ignora os enviados', async () => {
    const { emailNotifications } = await import('@/lib/notifications');
    expect(emailNotifications('u-1', [envelope({ mailbox: 'sent' })])).toHaveLength(0);
  });

  it('mostra o mais recente primeiro e limita o volume', async () => {
    const { emailNotifications } = await import('@/lib/notifications');
    const muitos = Array.from({ length: 50 }, (_, i) => envelope({
      id: String(i), messageId: `<${i}@x>`, date: `2026-08-${String(i % 28 + 1).padStart(2, '0')}T10:00:00Z`,
    }));
    const items = emailNotifications('u-1', muitos);
    expect(items).toHaveLength(20);
    expect(items[0].title).toBeTruthy();
    const datas = muitos.map((e) => e.date).sort().reverse();
    expect(items[0].id).toContain(muitos.find((e) => e.date === datas[0])!.messageId);
  });
});

describe('slackNotifications', () => {
  it('inclui menções e diretas e respeita o estado de leitura', async () => {
    const { markRead, slackNotifications } = await import('@/lib/notifications');
    markRead('u-1', 'slack', 'C1:1');
    const items = slackNotifications('u-1', {
      team: 'Equipe',
      mentions: [{ id: 'C1:1', channel: '#geral', author: 'Ana', text: 'Oi', date: '2026-09-20T10:00:00Z', url: 'https://equipe.slack.com/x' }],
      directs: [{ id: 'D1:2', channel: 'mensagem direta', author: 'Bia', text: 'Olá', date: '2026-09-21T10:00:00Z', url: '' }],
    });
    expect(items.map((item) => item.source)).toEqual(['slack', 'slack']);
    expect(items.find((item) => item.id.endsWith('C1:1'))?.read).toBe(true);
    expect(items.find((item) => item.id.endsWith('D1:2'))?.read).toBe(false);
  });
});

const OFF = { data: null, error: null };

describe('combineNotifications', () => {
  it('junta as três fontes numa lista só', async () => {
    const { combineNotifications } = await import('@/lib/notifications');
    const result = combineNotifications(
      'u-1',
      { data: [{ id: 'jira_mention:ENG-1', source: 'jira_mention' as const, title: 'ENG-1', url: 'u', read: false, date: '2026-08-30T10:00:00Z' }], error: null },
      { data: { items: [pull()], errors: [], defaultBranches: [], truncated: [] }, error: null },
      { data: [envelope()], error: null },
    );
    expect(result.data?.map((n) => n.source).sort()).toEqual(['email', 'jira_mention', 'pull_request']);
  });

  // O sino precisa funcionar para quem não usa Jira: era a única fonte, e o
  // painel inteiro ficava ausente quando ela não existia.
  it('avisa de PR e e-mail mesmo sem Jira configurado', async () => {
    const { combineNotifications } = await import('@/lib/notifications');
    const result = combineNotifications('u-1', OFF, { data: { items: [pull()], errors: [], defaultBranches: [], truncated: [] }, error: null }, { data: [envelope()], error: null });
    expect(result.data).toHaveLength(2);
  });

  it('continua ausente quando nenhuma fonte está ligada', async () => {
    const { combineNotifications } = await import('@/lib/notifications');
    expect(combineNotifications('u-1', OFF, OFF, OFF).data).toBeNull();
  });

  it('inclui o Slack sem alterar as outras fontes', async () => {
    const { combineNotifications } = await import('@/lib/notifications');
    const result = combineNotifications('u-1', OFF, OFF, OFF, {
      data: {
        team: 'Equipe', directs: [],
        mentions: [{ id: 'C1:1', channel: '#geral', author: 'Ana', text: 'Oi', date: '2026-09-21T10:00:00Z', url: '' }],
      },
      error: null,
    });
    expect(result.data?.map((item) => item.source)).toEqual(['slack']);
  });

  // Um Jira fora do ar não pode esconder o e-mail que chegou, nem sumir o erro.
  it('mantém o erro de uma fonte sem perder os avisos das outras', async () => {
    const { combineNotifications } = await import('@/lib/notifications');
    const result = combineNotifications('u-1', { data: null, error: 'Jira fora do ar' }, OFF, { data: [envelope()], error: null });
    expect(result.error).toBe('Jira fora do ar');
    expect(result.data).toHaveLength(1);
  });
});

describe('ordem do sino', () => {
  // As fontes eram concatenadas na ordem jira → PR → e-mail, então um e-mail
  // recém-chegado ia parar no fim da lista, atrás de PRs de semanas atrás.
  it('mostra o mais recente primeiro, misturando as fontes', async () => {
    const { combineNotifications } = await import('@/lib/notifications');
    const result = combineNotifications(
      'u-1',
      { data: [{ id: 'jira_mention:ENG-1', source: 'jira_mention' as const, title: 'ENG-1', url: 'u', read: false, date: '2026-08-20T10:00:00Z' }], error: null },
      { data: { items: [pull({ updatedAt: '2026-08-10T10:00:00Z' })], errors: [], defaultBranches: [], truncated: [] }, error: null },
      { data: [envelope({ date: '2026-08-30T10:00:00Z' })], error: null },
    );
    expect(result.data?.map((n) => n.source)).toEqual(['email', 'jira_mention', 'pull_request']);
  });

  it('o e-mail que acabou de chegar fica no topo', async () => {
    const { combineNotifications } = await import('@/lib/notifications');
    const result = combineNotifications(
      'u-1',
      { data: [], error: null },
      { data: { items: [pull({ updatedAt: '2026-08-31T09:00:00Z' })], errors: [], defaultBranches: [], truncated: [] }, error: null },
      { data: [envelope({ date: '2026-08-31T10:00:00Z' })], error: null },
    );
    expect(result.data?.[0].source).toBe('email');
  });
});
