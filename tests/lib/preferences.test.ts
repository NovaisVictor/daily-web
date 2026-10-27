import { describe, expect, it, beforeEach, afterEach } from 'vitest';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';

let dir: string;
const USER = 'user-1';
const OTHER = 'user-2';

beforeEach(async () => {
  dir = mkdtempSync(path.join(tmpdir(), 'daily-web-prefs-'));
  process.env.DAILY_WEB_DB_PATH = path.join(dir, 'test.db');
  const { getDb } = await import('@/lib/db');
  getDb();
});

afterEach(() => {
  rmSync(dir, { recursive: true, force: true });
});

describe('período da agenda', () => {
  it('começa no padrão para quem nunca escolheu', async () => {
    const { agendaDays } = await import('@/lib/preferences');
    const { DEFAULT_AGENDA_DAYS } = await import('@/lib/agendaWindow');
    expect(agendaDays(USER)).toBe(DEFAULT_AGENDA_DAYS);
  });

  it('guarda e devolve a escolha', async () => {
    const { agendaDays, setAgendaDays } = await import('@/lib/preferences');
    setAgendaDays(USER, 1);
    expect(agendaDays(USER)).toBe(1);
  });

  it('sobrescreve a escolha anterior em vez de acumular', async () => {
    const { agendaDays, setAgendaDays } = await import('@/lib/preferences');
    setAgendaDays(USER, 1);
    setAgendaDays(USER, 7);
    expect(agendaDays(USER)).toBe(7);
  });

  // É o ponto do pedido: cada pessoa escolhe o próprio período.
  it('é por usuário', async () => {
    const { agendaDays, setAgendaDays } = await import('@/lib/preferences');
    const { DEFAULT_AGENDA_DAYS } = await import('@/lib/agendaWindow');
    setAgendaDays(USER, 1);
    setAgendaDays(OTHER, 7);

    expect(agendaDays(USER)).toBe(1);
    expect(agendaDays(OTHER)).toBe(7);

    const { deleteUserPreferences } = await import('@/lib/preferences');
    deleteUserPreferences(OTHER);
    expect(agendaDays(USER)).toBe(1);
    expect(agendaDays(OTHER)).toBe(DEFAULT_AGENDA_DAYS);
  });

  // Um valor escrito à mão no banco, ou vindo de uma versão anterior, não
  // pode virar uma janela de mil dias.
  it('ignora valor fora da lista conhecida', async () => {
    const { agendaDays, setPreference } = await import('@/lib/preferences');
    const { DEFAULT_AGENDA_DAYS } = await import('@/lib/agendaWindow');

    for (const ruim of ['999', 'abc', '', '-1']) {
      setPreference(USER, 'agendaDays', ruim);
      expect(agendaDays(USER)).toBe(DEFAULT_AGENDA_DAYS);
    }
  });
});

describe('remoção de usuário', () => {
  it('leva as preferências junto', async () => {
    const { createUser, removeUser } = await import('@/lib/auth/users');
    const { setAgendaDays, agendaDays } = await import('@/lib/preferences');
    const { DEFAULT_AGENDA_DAYS } = await import('@/lib/agendaWindow');

    await createUser('chefe', 'senha-boa-123', true);
    const alvo = await createUser('temporario', 'senha-boa-123');
    setAgendaDays(alvo.id, 14);

    removeUser('temporario');
    expect(agendaDays(alvo.id)).toBe(DEFAULT_AGENDA_DAYS);
  });
});

describe('visualização das tarefas', () => {
  it('quem nunca escolheu vê o quadro', async () => {
    const { tasksView } = await import('@/lib/preferences');
    expect(tasksView(USER)).toBe('board');
  });

  // The default moved from the list to the board; whoever had already chosen
  // the list must not be moved along with it.
  it('quem já escolheu a lista continua na lista', async () => {
    const { tasksView, setTasksView } = await import('@/lib/preferences');
    setTasksView(USER, 'list');
    expect(tasksView(USER)).toBe('list');
    expect(tasksView(OTHER)).toBe('board');
  });

  it('um valor gravado à mão que não existe vira o quadro', async () => {
    const { tasksView, setPreference, TASKS_VIEW } = await import('@/lib/preferences');
    setPreference(USER, TASKS_VIEW, 'kanban');
    expect(tasksView(USER)).toBe('board');
  });
});

describe('boas-vindas', () => {
  it('trata como primeiro acesso quem ainda não tem login registrado', async () => {
    const { welcomeKind } = await import('@/lib/preferences');
    expect(welcomeKind(USER)).toBe('first');
  });

  it('continua primeiro acesso depois do primeiro login e passa a "de volta" no segundo', async () => {
    const { recordLogin, welcomeKind } = await import('@/lib/preferences');

    recordLogin(USER);
    expect(welcomeKind(USER)).toBe('first');

    recordLogin(USER);
    expect(welcomeKind(USER)).toBe('returning');

    recordLogin(USER);
    expect(welcomeKind(USER)).toBe('returning');
  });

  it('conta por pessoa: o login de uma não muda a outra', async () => {
    const { recordLogin, welcomeKind } = await import('@/lib/preferences');

    recordLogin(USER);
    recordLogin(USER);

    expect(welcomeKind(USER)).toBe('returning');
    expect(welcomeKind(OTHER)).toBe('first');
  });

  it('não quebra com um valor ilegível gravado à mão', async () => {
    const { welcomeKind, setPreference, LOGIN_COUNT } = await import('@/lib/preferences');
    setPreference(USER, LOGIN_COUNT, 'abc');
    expect(welcomeKind(USER)).toBe('first');
  });
});
