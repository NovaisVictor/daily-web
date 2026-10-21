import { describe, expect, it, beforeEach, afterEach, vi } from 'vitest';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';

vi.mock('@/lib/integrations/imap', () => ({ fetchBodies: vi.fn() }));
vi.mock('@/lib/email/inbox', () => ({ loadInbox: vi.fn() }));
vi.mock('@/lib/integrations/ics', () => ({ fetchAgenda: vi.fn() }));
vi.mock('@/lib/integrations/githubApi', () => ({ fetchPulls: vi.fn(), fetchMyPulls: vi.fn() }));
vi.mock('@/lib/integrations/jiraApi', () => ({
  fetchIssues: vi.fn(),
  fetchMentions: vi.fn(),
  fetchAncestors: vi.fn(async () => []),
  fetchProblems: vi.fn(async () => []),
  fetchByKeys: vi.fn(async () => []),
}));
vi.mock('@/lib/tasks', () => ({ fetchTasks: vi.fn() }));

import { loadInbox } from '@/lib/email/inbox';
import { fetchAgenda } from '@/lib/integrations/ics';
import { fetchMyPulls, fetchPulls } from '@/lib/integrations/githubApi';
import { fetchByKeys, fetchIssues, fetchMentions, fetchProblems } from '@/lib/integrations/jiraApi';
import { fetchTasks } from '@/lib/tasks';
import type { JiraItem, JiraProblem, JiraProblemItem } from '@/lib/types';

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
  vi.mocked(fetchPulls).mockResolvedValue({ items: [], errors: [], defaultBranches: [], truncated: [] });
  vi.mocked(fetchMyPulls).mockResolvedValue({ items: [], truncated: false, total: 0 });
  vi.mocked(fetchIssues).mockResolvedValue([]);
  vi.mocked(fetchMentions).mockResolvedValue([]);
  vi.mocked(fetchProblems).mockResolvedValue([]);
  vi.mocked(fetchByKeys).mockResolvedValue([]);
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

describe('aba de problemas do Jira', () => {
  const problema = (key: string, problems: JiraProblem[]): JiraProblemItem => ({
    key,
    summary: key,
    status: 'Em andamento',
    statusCategory: 'indeterminate',
    project: 'TT',
    url: `https://acme.atlassian.net/browse/${key}`,
    parent: null,
    role: 'assignee',
    awaitingApproval: false,
    kind: 'História',
    subtask: false,
    hierarchyLevel: 0,
    updatedAt: '',
    dueDate: '',
    priority: null,
    flag: 'none',
    problems,
  });

  beforeEach(async () => {
    await connect(USER, 'jira', { cloud: 'acme', email: 'a@x.com', token: 't' });
  });

  afterEach(() => vi.useRealTimers());

  it('o relógio reaproveita a busca por meia hora', async () => {
    vi.useFakeTimers({ toFake: ['Date'] });
    const { refreshAll } = await import('@/lib/refresher');
    await refreshAll(USER);
    await refreshAll(USER);
    expect(fetchProblems).toHaveBeenCalledTimes(1);

    vi.setSystemTime(Date.now() + 31 * 60 * 1000);
    await refreshAll(USER);
    expect(fetchProblems).toHaveBeenCalledTimes(2);
  });

  it('searches the problems again on the next timer cycle after a write', async () => {
    const { refreshAll, invalidate } = await import('@/lib/refresher');
    await refreshAll(USER);
    invalidate(USER);
    await refreshAll(USER);
    expect(fetchProblems).toHaveBeenCalledTimes(2);
  });

  it('o botão de atualizar busca de novo', async () => {
    const { refreshAll } = await import('@/lib/refresher');
    await refreshAll(USER);
    await refreshAll(USER, 'user');
    expect(fetchProblems).toHaveBeenCalledTimes(2);
  });

  it('não guarda a busca que falhou', async () => {
    vi.mocked(fetchProblems).mockRejectedValueOnce(new Error('Jira fora'));
    const { refreshAll } = await import('@/lib/refresher');
    const primeiro = await refreshAll(USER);
    expect(primeiro.jiraProblems.error).toBe('Jira fora');

    await refreshAll(USER);
    expect(fetchProblems).toHaveBeenCalledTimes(2);
  });

  it('a correção sai da tela e não volta no ciclo seguinte', async () => {
    vi.mocked(fetchProblems).mockResolvedValue([
      problema('TT-1', ['story-in-progress-without-start', 'story-without-epic']),
      problema('TT-2', ['story-without-epic']),
    ]);
    const { refreshAll, resolveJiraProblem, getCachedState } = await import('@/lib/refresher');
    await refreshAll(USER);

    resolveJiraProblem(USER, 'TT-1', ['story-in-progress-without-start']);
    resolveJiraProblem(USER, 'TT-2', ['story-without-epic']);
    const depois = getCachedState(USER)!.jiraProblems.data!;
    expect(depois.map((i) => [i.key, i.problems])).toEqual([['TT-1', ['story-without-epic']]]);

    const ciclo = await refreshAll(USER);
    expect(fetchProblems).toHaveBeenCalledTimes(1);
    expect(ciclo.jiraProblems.data!.map((i) => i.key)).toEqual(['TT-1']);
  });

  it('a correção de um usuário não mexe na lista do outro', async () => {
    await connect(OTHER, 'jira', { cloud: 'acme', email: 'b@x.com', token: 'u' });
    vi.mocked(fetchProblems).mockResolvedValue([problema('TT-1', ['story-without-epic'])]);
    const { refreshAll, resolveJiraProblem, getCachedState } = await import('@/lib/refresher');
    await refreshAll(USER);
    await refreshAll(OTHER);

    resolveJiraProblem(USER, 'TT-1', ['story-without-epic']);
    expect(getCachedState(USER)!.jiraProblems.data).toEqual([]);
    expect(getCachedState(OTHER)!.jiraProblems.data!.map((i) => i.key)).toEqual(['TT-1']);
  });
});

describe('cards do Jira nos PRs', () => {
  const pr = (title: string) => ({
    repo: 'acme/app',
    number: 7,
    title,
    url: 'https://github.com/acme/app/pull/7',
    author: 'eu',
    draft: false,
    awaitingYou: false,
    mine: true,
    isPullRequest: true,
    id: 'PR_test',
    createdAt: '',
    ci: 'none' as const,
    failedChecks: [],
    review: 'none' as const,
    pendingReviewers: [],
    reviewers: [],
    reviewRequestedAt: null,
    merge: 'unknown' as const,
    size: { additions: 1, deletions: 1, files: 1 },
    headRef: 'feature/x',
    baseRef: 'main',
    headSha: 'abc123',
    updatedAt: '2026-10-20T10:00:00Z',
  });

  it('busca os cards citados nos títulos e põe o status no PR', async () => {
    await connect(USER, 'pulls', { token: 'gh', repos: 'acme/app' });
    await connect(USER, 'jira', { cloud: 'acme', email: 'a@x.com', token: 't' });
    vi.mocked(fetchPulls).mockResolvedValue({ items: [pr('feat: login (TT-42)')], errors: [], defaultBranches: [], truncated: [] });
    vi.mocked(fetchByKeys).mockResolvedValue([
      { ...problemaBase('TT-42'), status: 'Code Review PR', statusCategory: 'indeterminate' },
    ]);

    const { refreshAll } = await import('@/lib/refresher');
    const state = await refreshAll(USER);

    expect(vi.mocked(fetchByKeys).mock.calls[0][1]).toEqual(['TT-42']);
    expect(state.pulls.data!.items[0].jira).toEqual([
      { key: 'TT-42', url: 'https://acme.atlassian.net/browse/TT-42', status: 'Code Review PR', statusCategory: 'indeterminate' },
    ]);
  });

  it('the PRs you opened arrive in the same cycle with their Jira cards', async () => {
    await connect(USER, 'pulls', { token: 'gh', repos: 'acme/app' });
    await connect(USER, 'jira', { cloud: 'acme', email: 'a@x.com', token: 't' });
    vi.mocked(fetchMyPulls).mockResolvedValue({ items: [pr('feat: login (TT-77)')], truncated: false, total: 1 });
    vi.mocked(fetchByKeys).mockResolvedValue([
      { ...problemaBase('TT-77'), status: 'Code Review PR', statusCategory: 'indeterminate' },
    ]);

    const { refreshAll } = await import('@/lib/refresher');
    const state = await refreshAll(USER);

    expect(state.myPulls.data!.items[0].jira?.map((j) => j.key)).toEqual(['TT-77']);
  });

  it('sem o Jira o PR chega sem card, e a falha da busca não derruba o PR', async () => {
    await connect(USER, 'pulls', { token: 'gh', repos: 'acme/app' });
    vi.mocked(fetchPulls).mockResolvedValue({ items: [pr('feat: login (TT-42)')], errors: [], defaultBranches: [], truncated: [] });
    const { refreshAll, dropCache } = await import('@/lib/refresher');

    const semJira = await refreshAll(USER);
    expect(fetchByKeys).not.toHaveBeenCalled();
    expect(semJira.pulls.data!.items[0].jira).toBeUndefined();

    await connect(USER, 'jira', { cloud: 'acme', email: 'a@x.com', token: 't' });
    vi.mocked(fetchByKeys).mockRejectedValueOnce(new Error('Jira fora'));
    dropCache(USER);
    const comFalha = await refreshAll(USER);
    expect(comFalha.pulls.error).toBeNull();
    expect(comFalha.pulls.data!.items[0].jira).toBeUndefined();
  });
});

function problemaBase(key: string): JiraItem {
  return {
    key,
    summary: key,
    status: '',
    statusCategory: 'new',
    project: key.split('-')[0],
    url: `https://acme.atlassian.net/browse/${key}`,
    parent: null,
    role: 'assignee',
    awaitingApproval: false,
    kind: 'História',
    subtask: false,
    hierarchyLevel: 0,
    updatedAt: '',
    dueDate: '',
    priority: null,
    flag: 'none',
  };
}
