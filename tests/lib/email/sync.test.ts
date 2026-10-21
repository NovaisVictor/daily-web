import { describe, expect, it, beforeEach, afterEach, vi } from 'vitest';
import { NextRequest } from 'next/server';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';

// A ação local precisa vencer o retrato do servidor. O IMAP é dublê aqui
// justamente para que o retrato possa estar velho de propósito: é assim que o
// e-mail apagado voltava para a tela.
vi.mock('@/lib/email/inbox', () => ({ loadInbox: vi.fn() }));
vi.mock('@/lib/integrations/imap', () => ({
  fetchBodies: vi.fn(),
  setSeen: vi.fn(),
  applyTag: vi.fn(),
  deleteEmails: vi.fn(),
  listFolders: vi.fn(),
  sendReply: vi.fn(),
  fetchBody: vi.fn(),
}));
vi.mock('@/lib/integrations/ics', () => ({ fetchAgenda: vi.fn() }));
vi.mock('@/lib/integrations/githubApi', () => ({ fetchPulls: vi.fn() }));
vi.mock('@/lib/integrations/jiraApi', () => ({ fetchIssues: vi.fn(), fetchMentions: vi.fn() }));
vi.mock('@/lib/tasks', () => ({ fetchTasks: vi.fn() }));

const currentUser = vi.fn();
vi.mock('@/lib/auth/currentUser', () => ({ getCurrentUser: () => currentUser() }));

import { setSeen, deleteEmails } from '@/lib/integrations/imap';
import { loadInbox } from '@/lib/email/inbox';
import { fetchAgenda } from '@/lib/integrations/ics';
import { fetchPulls } from '@/lib/integrations/githubApi';
import { fetchIssues, fetchMentions } from '@/lib/integrations/jiraApi';
import { fetchTasks } from '@/lib/tasks';
import { POST as markRoute } from '@/app/api/email/mark/route';
import { POST as batchRoute } from '@/app/api/email/batch/route';

const ME = { id: 'u-1', username: 'joao', passwordHash: 'x', isAdmin: true, createdAt: '' };

let dir: string;
let mailId: string;

function envelope(over: Record<string, unknown> = {}) {
  return {
    id: '1',
    account: mailId,
    accountLabel: 'Trabalho',
    from: 'Alguém',
    subject: 'Assunto',
    unread: true,
    date: '2026-09-12T10:00:00Z',
    messageId: '<a@b>',
    references: [],
    labels: [],
    mailbox: 'inbox' as const,
    folder: 'INBOX',
    ...over,
  };
}

function req(body: unknown): NextRequest {
  return new NextRequest('http://localhost/api', { method: 'POST', body: JSON.stringify(body) });
}

async function emailsNoCache(): Promise<unknown[]> {
  const { getCachedState } = await import('@/lib/refresher');
  return getCachedState(ME.id)?.email.data ?? [];
}

beforeEach(async () => {
  dir = mkdtempSync(path.join(tmpdir(), 'daily-web-email-sync-'));
  process.env.DAILY_WEB_DB_PATH = path.join(dir, 'test.db');
  process.env.DAILY_WEB_SECRET_KEY = Buffer.alloc(32, 7).toString('base64');
  vi.clearAllMocks();
  currentUser.mockResolvedValue(ME);

  const { getDb } = await import('@/lib/db');
  getDb();
  const { resetCachesForTests } = await import('@/lib/refresher');
  resetCachesForTests();

  const { saveConnection } = await import('@/lib/vault/connections');
  mailId = saveConnection(ME.id, 'email', 'Trabalho', {
    preset: 'gmail',
    user: 'a@x.com',
    password: 's',
  });

  vi.mocked(loadInbox).mockResolvedValue([]);
  vi.mocked(fetchAgenda).mockResolvedValue([]);
  vi.mocked(fetchPulls).mockResolvedValue({ items: [], errors: [], defaultBranches: [], truncated: [] });
  vi.mocked(fetchIssues).mockResolvedValue([]);
  vi.mocked(fetchMentions).mockResolvedValue([]);
  vi.mocked(fetchTasks).mockResolvedValue([]);
  vi.mocked(setSeen).mockResolvedValue(undefined);
  vi.mocked(deleteEmails).mockResolvedValue(undefined);
});

afterEach(() => {
  rmSync(dir, { recursive: true, force: true });
});

describe('a ação local vence o retrato do servidor', () => {
  // O retrato do IMAP continua trazendo a mensagem depois da exclusão: ou
  // porque o ciclo leu a caixa antes da escrita chegar, ou porque o provedor
  // ainda não a propagou. Gravar esse retrato cru desfazia a exclusão.
  it('não traz de volta o e-mail apagado quando o retrato ainda o contém', async () => {
    vi.mocked(loadInbox).mockResolvedValue([envelope()] as never);
    const { refreshAll } = await import('@/lib/refresher');
    await refreshAll(ME.id);

    await batchRoute(req({ targets: [{ account: mailId, id: '1' }], action: 'delete' }));
    expect(await emailsNoCache()).toEqual([]);

    // O servidor ainda devolve a mensagem no ciclo seguinte.
    await refreshAll(ME.id);

    expect(await emailsNoCache()).toEqual([]);
  });

  // Abrir a mensagem dispara a marcação de lido, que abre a sua própria
  // conexão IMAP. A exclusão logo em seguida abre outra na mesma conta e o
  // provedor recusa o login excedente — e era aí que o e-mail voltava.
  it('não traz de volta o e-mail quando a exclusão falha depois de marcar como lido', async () => {
    vi.mocked(loadInbox).mockResolvedValue([envelope()] as never);
    const { refreshAll } = await import('@/lib/refresher');
    await refreshAll(ME.id);

    await markRoute(req({ account: mailId, id: '1', seen: true }));
    vi.mocked(deleteEmails).mockRejectedValueOnce(
      new Error('Trabalho: too many simultaneous connections'),
    );
    await batchRoute(req({ targets: [{ account: mailId, id: '1' }], action: 'delete' }));

    await refreshAll(ME.id);

    expect(await emailsNoCache()).toEqual([]);
  });

  // O deploy reinicia o serviço a cada publicação. Uma intenção guardada só em
  // memória morria ali e a mensagem voltava na primeira leitura.
  it('preserva a exclusão através de um reinício do processo', async () => {
    vi.mocked(loadInbox).mockResolvedValue([envelope()] as never);
    const { refreshAll, resetCachesForTests } = await import('@/lib/refresher');
    await refreshAll(ME.id);
    await batchRoute(req({ targets: [{ account: mailId, id: '1' }], action: 'delete' }));

    resetCachesForTests();
    await refreshAll(ME.id);

    expect(await emailsNoCache()).toEqual([]);
  });

  // Marcar como lido também é intenção: o retrato velho traz `unread`.
  it('mantém a mensagem lida enquanto o retrato ainda a traz como não lida', async () => {
    vi.mocked(loadInbox).mockResolvedValue([envelope()] as never);
    const { refreshAll } = await import('@/lib/refresher');
    await refreshAll(ME.id);

    await markRoute(req({ account: mailId, id: '1', seen: true }));
    await refreshAll(ME.id);

    expect(await emailsNoCache()).toEqual([expect.objectContaining({ id: '1', unread: false })]);
  });
});

describe('a intenção é confirmada ou falha em definitivo', () => {
  it('esquece a exclusão depois que o servidor concorda com ela', async () => {
    vi.mocked(loadInbox).mockResolvedValue([envelope()] as never);
    const { refreshAll } = await import('@/lib/refresher');
    await refreshAll(ME.id);
    await batchRoute(req({ targets: [{ account: mailId, id: '1' }], action: 'delete' }));

    vi.mocked(loadInbox).mockResolvedValue([] as never);
    await refreshAll(ME.id);

    const { listPendingActions } = await import('@/lib/email/pendingActions');
    expect(listPendingActions(ME.id)).toEqual([]);
  });

  // Esgotadas as tentativas, esconder a mensagem seria mentir sobre a caixa:
  // ela não foi apagada. Ela volta, com o erro à mostra.
  it('devolve a mensagem com o erro quando as tentativas se esgotam', async () => {
    vi.mocked(loadInbox).mockResolvedValue([envelope()] as never);
    const { refreshAll } = await import('@/lib/refresher');
    await refreshAll(ME.id);

    vi.mocked(deleteEmails).mockRejectedValue(new Error('caixa recusou a conexão'));
    await batchRoute(req({ targets: [{ account: mailId, id: '1' }], action: 'delete' }));

    const { replayPendingActions } = await import('@/lib/email/replay');
    const { listConnections } = await import('@/lib/vault/connections');
    const conns = listConnections(ME.id, 'email');
    // Uma tentativa por ciclo, sem esperar o backoff de verdade.
    for (let i = 0; i < 10; i += 1) {
      await replayPendingActions(ME.id, conns, new Date(Date.now() + i * 3_600_000));
    }
    await refreshAll(ME.id);

    expect(await emailsNoCache()).toEqual([
      expect.objectContaining({ id: '1', actionError: expect.stringContaining('recusou') }),
    ]);
  });

  // A exclusão que desistiu continua sendo o que o usuário pediu. Quando a
  // mensagem enfim some do retrato, o pedido está cumprido: a linha de erro
  // não pode ficar na fila para sempre.
  it('esquece a exclusão que tinha desistido quando a mensagem some do retrato', async () => {
    vi.mocked(loadInbox).mockResolvedValue([envelope(), envelope({ id: '2', messageId: '<b@b>' })] as never);
    const { refreshAll } = await import('@/lib/refresher');
    await refreshAll(ME.id);

    vi.mocked(deleteEmails).mockRejectedValue(new Error('caixa recusou a conexão'));
    await batchRoute(req({ targets: [{ account: mailId, id: '1' }], action: 'delete' }));
    const { replayPendingActions } = await import('@/lib/email/replay');
    const { listConnections } = await import('@/lib/vault/connections');
    const conns = listConnections(ME.id, 'email');
    for (let i = 0; i < 10; i += 1) {
      await replayPendingActions(ME.id, conns, new Date(Date.now() + i * 3_600_000));
    }
    const { listPendingActions } = await import('@/lib/email/pendingActions');
    expect(listPendingActions(ME.id)).toEqual([expect.objectContaining({ state: 'failed' })]);

    vi.mocked(loadInbox).mockResolvedValue([envelope({ id: '2', messageId: '<b@b>' })] as never);
    await refreshAll(ME.id);

    expect(listPendingActions(ME.id)).toEqual([]);
    expect(await emailsNoCache()).toEqual([expect.objectContaining({ id: '2' })]);
  });

  it('mantém a exclusão que desistiu enquanto a mensagem continua no retrato', async () => {
    vi.mocked(loadInbox).mockResolvedValue([envelope()] as never);
    const { refreshAll } = await import('@/lib/refresher');
    await refreshAll(ME.id);

    vi.mocked(deleteEmails).mockRejectedValue(new Error('caixa recusou a conexão'));
    await batchRoute(req({ targets: [{ account: mailId, id: '1' }], action: 'delete' }));
    const { replayPendingActions } = await import('@/lib/email/replay');
    const { listConnections } = await import('@/lib/vault/connections');
    const conns = listConnections(ME.id, 'email');
    for (let i = 0; i < 10; i += 1) {
      await replayPendingActions(ME.id, conns, new Date(Date.now() + i * 3_600_000));
    }
    await refreshAll(ME.id);

    const { listPendingActions } = await import('@/lib/email/pendingActions');
    expect(listPendingActions(ME.id)).toEqual([expect.objectContaining({ state: 'failed' })]);
  });
});

describe('uma conexão IMAP por conta de cada vez', () => {
  // Listagem e ação disputavam o mesmo login e o provedor recusava o excedente.
  it('serializa as operações da mesma conta', async () => {
    const { runExclusive } = await import('@/lib/email/queue');
    const ordem: string[] = [];
    const primeira = runExclusive(mailId, async () => {
      ordem.push('entrou-1');
      await new Promise((r) => setTimeout(r, 20));
      ordem.push('saiu-1');
    });
    const segunda = runExclusive(mailId, async () => {
      ordem.push('entrou-2');
    });

    await Promise.all([primeira, segunda]);

    expect(ordem).toEqual(['entrou-1', 'saiu-1', 'entrou-2']);
  });

  it('deixa contas diferentes correrem em paralelo', async () => {
    const { runExclusive } = await import('@/lib/email/queue');
    const ordem: string[] = [];
    const primeira = runExclusive('conta-a', async () => {
      ordem.push('entrou-a');
      await new Promise((r) => setTimeout(r, 20));
      ordem.push('saiu-a');
    });
    const segunda = runExclusive('conta-b', async () => {
      ordem.push('entrou-b');
    });

    await Promise.all([primeira, segunda]);

    expect(ordem).toEqual(['entrou-a', 'entrou-b', 'saiu-a']);
  });

  // Nada sem limite: uma fila que cresce à vontade vira memória presa e
  // operações que ninguém mais espera.
  it('recusa a operação quando a fila da conta está cheia', async () => {
    const { runExclusive, MAX_QUEUED_PER_ACCOUNT } = await import('@/lib/email/queue');
    const presa = runExclusive('conta-c', () => new Promise((r) => setTimeout(r, 50)));
    const enfileiradas = Array.from({ length: MAX_QUEUED_PER_ACCOUNT - 1 }, () =>
      runExclusive('conta-c', async () => {}),
    );

    await expect(runExclusive('conta-c', async () => {})).rejects.toThrow(/fila/i);

    await Promise.all([presa, ...enfileiradas]);
  });
});
