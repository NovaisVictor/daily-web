import { describe, expect, it, beforeEach, afterEach, vi } from 'vitest';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';

vi.mock('@/lib/integrations/imap', () => ({ fetchBodies: vi.fn() }));
vi.mock('@/lib/email/inbox', () => ({ loadInbox: vi.fn() }));
vi.mock('@/lib/integrations/ics', () => ({ fetchAgenda: vi.fn() }));
vi.mock('@/lib/integrations/githubApi', () => ({ fetchPulls: vi.fn() }));
vi.mock('@/lib/integrations/jiraApi', () => ({
  fetchIssues: vi.fn(),
  fetchMentions: vi.fn(),
  fetchAncestors: vi.fn(async () => []),
}));
vi.mock('@/lib/tasks', () => ({ fetchTasks: vi.fn() }));

import { loadInbox } from '@/lib/email/inbox';
import { fetchAgenda } from '@/lib/integrations/ics';
import { fetchPulls } from '@/lib/integrations/githubApi';
import { fetchIssues, fetchMentions } from '@/lib/integrations/jiraApi';
import { fetchTasks } from '@/lib/tasks';

let dir: string;

const USER = 'user-1';
const OTHER = 'user-2';

function envelope(over: Partial<Record<string, unknown>> = {}) {
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

beforeEach(async () => {
  dir = mkdtempSync(path.join(tmpdir(), 'daily-web-refresh-'));
  process.env.DAILY_WEB_DB_PATH = path.join(dir, 'test.db');
  process.env.DAILY_WEB_SECRET_KEY = Buffer.alloc(32, 3).toString('base64');
  vi.clearAllMocks();

  const { getDb } = await import('@/lib/db');
  getDb();
  const { resetCachesForTests } = await import('@/lib/refresher');
  resetCachesForTests();

  vi.mocked(loadInbox).mockResolvedValue([]);
  vi.mocked(fetchAgenda).mockResolvedValue([]);
  vi.mocked(fetchPulls).mockResolvedValue({ items: [], errors: [] });
  vi.mocked(fetchIssues).mockResolvedValue([]);
  vi.mocked(fetchMentions).mockResolvedValue([]);
  vi.mocked(fetchTasks).mockResolvedValue([]);
});

afterEach(() => {
  rmSync(dir, { recursive: true, force: true });
});

async function connect(userId: string, moduleId: 'email' | 'agenda' | 'jira' | 'pulls', values: Record<string, string>) {
  const { saveConnection } = await import('@/lib/vault/connections');
  return saveConnection(userId, moduleId, moduleId, values);
}

describe('módulos desligados', () => {
  it('não chama integração de módulo que o usuário não ligou', async () => {
    const { refreshAll } = await import('@/lib/refresher');
    await refreshAll(USER);

    expect(loadInbox).not.toHaveBeenCalled();
    expect(fetchAgenda).not.toHaveBeenCalled();
    expect(fetchIssues).not.toHaveBeenCalled();
    expect(fetchPulls).not.toHaveBeenCalled();
  });

  // Painel desligado não é "vazio" nem "com erro": é ausência. A tela usa
  // isso para não desenhar a seção.
  it('devolve dado e erro nulos para o módulo desligado', async () => {
    const { refreshAll } = await import('@/lib/refresher');
    const state = await refreshAll(USER);

    expect(state.email).toEqual({ data: null, error: null });
    expect(state.modules).not.toContain('email');
  });

  it('anuncia os módulos ligados no estado', async () => {
    await connect(USER, 'agenda', { icsUrl: 'https://x/a.ics' });
    const { refreshAll } = await import('@/lib/refresher');
    const state = await refreshAll(USER);

    expect(state.modules).toContain('agenda');
    expect(fetchAgenda).toHaveBeenCalledTimes(1);
  });
});

describe('várias conexões no mesmo módulo', () => {
  it('junta os e-mails das duas caixas', async () => {
    await connect(USER, 'email', { preset: 'gmail', user: 'a@x.com', password: 's' });
    await connect(USER, 'email', { preset: 'gmail', user: 'b@x.com', password: 's' });

    vi.mocked(loadInbox)
      .mockResolvedValueOnce([envelope({ id: '1' })])
      .mockResolvedValueOnce([envelope({ id: '2' })]);

    const { refreshAll } = await import('@/lib/refresher');
    const state = await refreshAll(USER);

    expect(state.email.data).toHaveLength(2);
    expect(state.email.error).toBeNull();
    expect(state.mailboxes).toHaveLength(2);
  });

  // Uma caixa fora do ar não pode apagar da tela os e-mails da outra.
  it('mantém os dados da caixa que funcionou e reporta o erro da outra', async () => {
    await connect(USER, 'email', { preset: 'gmail', user: 'a@x.com', password: 's' });
    await connect(USER, 'email', { preset: 'gmail', user: 'b@x.com', password: 's' });

    vi.mocked(loadInbox)
      .mockResolvedValueOnce([envelope({ id: '1' })])
      .mockRejectedValueOnce(new Error('Pessoal: senha recusada'));

    const { refreshAll } = await import('@/lib/refresher');
    const state = await refreshAll(USER);

    expect(state.email.data).toHaveLength(1);
    expect(state.email.error).toContain('senha recusada');
  });

  it('só reporta erro quando nenhuma caixa respondeu', async () => {
    await connect(USER, 'email', { preset: 'gmail', user: 'a@x.com', password: 's' });
    vi.mocked(loadInbox).mockRejectedValue(new Error('caiu'));

    const { refreshAll } = await import('@/lib/refresher');
    const state = await refreshAll(USER);

    expect(state.email.data).toBeNull();
    expect(state.email.error).toContain('caiu');
  });
});

describe('isolamento entre usuários', () => {
  it('usa a conexão do próprio usuário, não a de outro', async () => {
    await connect(USER, 'jira', { cloud: 'acme-do-joao', email: 'a@x.com', token: 't' });
    await connect(OTHER, 'jira', { cloud: 'acme-da-maria', email: 'b@x.com', token: 'u' });

    const { refreshAll } = await import('@/lib/refresher');
    await refreshAll(OTHER);

    expect(fetchIssues).toHaveBeenCalledTimes(1);
    expect(vi.mocked(fetchIssues).mock.calls[0][0].values.cloud).toBe('acme-da-maria');
  });

  it('não devolve para um usuário o cache do outro', async () => {
    await connect(USER, 'email', { preset: 'gmail', user: 'a@x.com', password: 's' });
    vi.mocked(loadInbox).mockResolvedValue([envelope()]);

    const { refreshAll, getCachedState } = await import('@/lib/refresher');
    await refreshAll(USER);

    expect(getCachedState(USER)?.email.data).toHaveLength(1);
    expect(getCachedState(OTHER)).toBeNull();
  });

  it('dropCache derruba só o cache pedido', async () => {
    await connect(USER, 'email', { preset: 'gmail', user: 'a@x.com', password: 's' });
    await connect(OTHER, 'email', { preset: 'gmail', user: 'b@x.com', password: 's' });

    const { refreshAll, getCachedState, dropCache } = await import('@/lib/refresher');
    await refreshAll(USER);
    await refreshAll(OTHER);
    dropCache(USER);

    expect(getCachedState(USER)).toBeNull();
    expect(getCachedState(OTHER)).not.toBeNull();
  });
});

describe('invalidate after an external write', () => {
  it('keeps a refresh started before the write from caching or serving the old state', async () => {
    await connect(USER, 'email', { preset: 'gmail', user: 'a@x.com', password: 's' });
    const { refreshAll, getCachedState, invalidate } = await import('@/lib/refresher');

    let releaseOld: (envelopes: unknown[]) => void = () => {};
    vi.mocked(loadInbox).mockReturnValueOnce(
      new Promise((resolve) => {
        releaseOld = resolve as (envelopes: unknown[]) => void;
      }) as ReturnType<typeof loadInbox>,
    );
    const old = refreshAll(USER);

    invalidate(USER);
    vi.mocked(loadInbox).mockResolvedValue([envelope({ id: 'after-write' })]);
    const fresh = await refreshAll(USER);

    releaseOld([envelope({ id: 'before-write' })]);
    await old;

    expect(fresh.email.data?.map((e) => e.id)).toEqual(['after-write']);
    expect(getCachedState(USER)?.email.data?.map((e) => e.id)).toEqual(['after-write']);
  });
});

describe('notificações', () => {
  it('só busca menções quando o Jira está conectado', async () => {
    const { refreshAll } = await import('@/lib/refresher');
    await refreshAll(USER);
    expect(fetchMentions).not.toHaveBeenCalled();

    await connect(USER, 'jira', { cloud: 'acme', email: 'a@x.com', token: 't' });
    await refreshAll(USER);
    expect(fetchMentions).toHaveBeenCalledTimes(1);
  });
});

describe('ação concorrente com um refresh em voo', () => {
  // O refresh lê a caixa no começo e só grava o cache no fim. Uma exclusão
  // feita nesse meio-tempo era desfeita pela gravação: o e-mail voltava para
  // a tela e o usuário precisava apagar de novo.
  it('não ressuscita o e-mail apagado durante o refresh', async () => {
    await connect(USER, 'email', { preset: 'gmail', user: 'a@x.com', password: 's' });
    vi.mocked(loadInbox).mockResolvedValue([envelope({ id: '1' })]);

    const { refreshAll, getCachedState, patchCachedState } = await import('@/lib/refresher');
    await refreshAll(USER);

    let liberar: (v: unknown[]) => void = () => {};
    vi.mocked(loadInbox).mockImplementation(
      () => new Promise((resolve) => (liberar = resolve as (v: unknown[]) => void)) as never,
    );

    const emVoo = refreshAll(USER);
    const { removeEmails } = await import('@/lib/statePatches');
    patchCachedState(USER, (state) => removeEmails(state, [{ account: 'mail-1', id: '1' }]));

    liberar([envelope({ id: '1' })]);
    await emVoo;

    expect(getCachedState(USER)?.email.data).toEqual([]);
  });
});

describe('refresh simultâneo', () => {
  // Cada rodada extra abre um login novo em cada caixa e o servidor recusa os
  // seguintes. O clique no botão durante o ciclo do timer precisa aproveitar o
  // que já está em curso em vez de abrir uma segunda leitura.
  it('reaproveita o refresh em curso em vez de abrir outro', async () => {
    await connect(USER, 'email', { preset: 'gmail', user: 'a@x.com', password: 's' });
    const { refreshAll } = await import('@/lib/refresher');

    let liberar: (envelopes: unknown[]) => void = () => {};
    vi.mocked(loadInbox).mockReturnValue(
      new Promise((resolve) => {
        liberar = resolve as (envelopes: unknown[]) => void;
      }) as ReturnType<typeof loadInbox>,
    );

    const primeiro = refreshAll(USER);
    const segundo = refreshAll(USER);
    liberar([envelope()]);

    expect(await primeiro).toBe(await segundo);
    expect(loadInbox).toHaveBeenCalledTimes(1);
  });

  it('volta a ler o servidor depois que o refresh anterior termina', async () => {
    await connect(USER, 'email', { preset: 'gmail', user: 'a@x.com', password: 's' });
    const { refreshAll } = await import('@/lib/refresher');

    await refreshAll(USER);
    await refreshAll(USER);

    expect(loadInbox).toHaveBeenCalledTimes(2);
  });

  // Um usuário esperando o IMAP não pode segurar o refresh do outro.
  it('não junta o refresh de usuários diferentes', async () => {
    await connect(USER, 'email', { preset: 'gmail', user: 'a@x.com', password: 's' });
    await connect(OTHER, 'email', { preset: 'gmail', user: 'b@x.com', password: 's' });
    const { refreshAll } = await import('@/lib/refresher');

    await Promise.all([refreshAll(USER), refreshAll(OTHER)]);

    expect(loadInbox).toHaveBeenCalledTimes(2);
  });
});

describe('intervalo do ciclo', () => {
  it('usa cinco minutos quando REFRESH_SECONDS não foi definido', async () => {
    const { refreshIntervalSeconds } = await import('@/lib/refresher');
    expect(refreshIntervalSeconds(undefined)).toBe(300);
  });

  it('respeita um valor válido vindo do ambiente', async () => {
    const { refreshIntervalSeconds } = await import('@/lib/refresher');
    expect(refreshIntervalSeconds('120')).toBe(120);
  });

  // Number('lixo') é NaN, e setInterval com NaN dispara a cada milissegundo.
  it.each(['', 'abc', '0', '-5', 'Infinity'])('cai no padrão com valor inválido %j', async (raw) => {
    const { refreshIntervalSeconds } = await import('@/lib/refresher');
    expect(refreshIntervalSeconds(raw)).toBe(300);
  });
});

describe('próximo ciclo agendado', () => {
  afterEach(() => {
    vi.useRealTimers();
  });

  it('não anuncia horário enquanto o ciclo não foi iniciado', async () => {
    const { refreshAll, getCachedState } = await import('@/lib/refresher');
    await refreshAll(USER);

    expect(getCachedState(USER)?.nextRefreshAt).toBeNull();
  });

  it('anuncia o próximo ciclo e o avança a cada tique', async () => {
    vi.useFakeTimers({ now: new Date('2026-09-11T12:00:00Z') });
    const { refreshAll, getCachedState, startRefreshLoop } = await import('@/lib/refresher');
    await refreshAll(USER);

    startRefreshLoop(600);
    expect(getCachedState(USER)?.nextRefreshAt).toBe('2026-09-11T12:10:00.000Z');

    await vi.advanceTimersByTimeAsync(600_000);
    expect(getCachedState(USER)?.nextRefreshAt).toBe('2026-09-11T12:20:00.000Z');
  });

  it('devolve o próximo ciclo também no resultado do refresh manual', async () => {
    vi.useFakeTimers({ now: new Date('2026-09-11T12:00:00Z') });
    const { refreshAll, startRefreshLoop } = await import('@/lib/refresher');
    startRefreshLoop(600);

    const state = await refreshAll(USER);
    expect(state.nextRefreshAt).toBe('2026-09-11T12:10:00.000Z');
  });

  // Um ciclo que passa do intervalo não pode ter outro começando por cima.
  it('descarta o tique que chega com o ciclo anterior ainda em curso', async () => {
    vi.useFakeTimers({ now: new Date('2026-09-11T12:00:00Z') });
    const { createUser } = await import('@/lib/auth/users');
    const ana = await createUser('ana', 'uma-senha-longa-o-bastante');
    await connect(ana.id, 'email', { preset: 'gmail', user: 'a@x.com', password: 's' });

    let liberar: (envelopes: unknown[]) => void = () => {};
    vi.mocked(loadInbox).mockReturnValue(
      new Promise((resolve) => {
        liberar = resolve as (envelopes: unknown[]) => void;
      }) as ReturnType<typeof loadInbox>,
    );

    const { startRefreshLoop } = await import('@/lib/refresher');
    startRefreshLoop(600);
    await vi.advanceTimersByTimeAsync(0);
    expect(loadInbox).toHaveBeenCalledTimes(1);

    await vi.advanceTimersByTimeAsync(600_000);
    expect(loadInbox).toHaveBeenCalledTimes(1);

    liberar([]);
    await vi.advanceTimersByTimeAsync(600_000);
    expect(loadInbox).toHaveBeenCalledTimes(2);
  });
});

// No build de produção o instrumentation e as rotas carregam cópias separadas
// deste módulo. O ciclo roda numa cópia e a tela lê de outra: estado guardado
// só no módulo nunca chegava à rota.
describe('estado compartilhado entre cópias do módulo', () => {
  afterEach(() => {
    vi.useRealTimers();
  });

  it('a cópia das rotas enxerga o cache e o agendamento do ciclo de fundo', async () => {
    vi.useFakeTimers({ now: new Date('2026-09-11T12:00:00Z') });
    const doCiclo = await import('@/lib/refresher');
    vi.resetModules();
    const daRota = await import('@/lib/refresher');
    expect(daRota).not.toBe(doCiclo);

    await doCiclo.refreshAll(USER);
    doCiclo.startRefreshLoop(600);

    const state = daRota.getCachedState(USER);
    expect(state).not.toBeNull();
    expect(state?.nextRefreshAt).toBe('2026-09-11T12:10:00.000Z');
  });
});
