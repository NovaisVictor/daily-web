import { describe, expect, it, beforeEach, afterEach, vi } from 'vitest';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import Database from 'better-sqlite3';

let dir: string;
let dbFile: string;
const ORIGINAL_ENV = { ...process.env };

beforeEach(() => {
  dir = mkdtempSync(path.join(tmpdir(), 'daily-web-migrate-'));
  dbFile = path.join(dir, 'test.db');
  process.env.DAILY_WEB_DB_PATH = dbFile;
  vi.resetModules();
});

afterEach(() => {
  rmSync(dir, { recursive: true, force: true });
  process.env = { ...ORIGINAL_ENV };
});

// Simula o banco como ele existia antes do multiusuário.
function seedLegacyDatabase(): string {
  const legacy = new Database(dbFile);
  legacy.exec(`
    CREATE TABLE notifications_read (
      source TEXT NOT NULL, external_id TEXT NOT NULL, read_at TEXT NOT NULL,
      PRIMARY KEY (source, external_id)
    );
    CREATE TABLE email_bodies (
      account TEXT NOT NULL, message_id TEXT NOT NULL, body TEXT NOT NULL, cached_at TEXT NOT NULL,
      PRIMARY KEY (account, message_id)
    );
    CREATE TABLE users (
      id TEXT PRIMARY KEY, username TEXT NOT NULL UNIQUE, password_hash TEXT NOT NULL,
      is_admin INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL
    );
  `);
  legacy.prepare('INSERT INTO users VALUES (?,?,?,?,?)').run('u-joao', 'joao', 'hash', 1, '2026-01-01');
  legacy.prepare('INSERT INTO email_bodies VALUES (?,?,?,?)').run('work', '42', 'corpo antigo', '2026-01-01');
  legacy.prepare('INSERT INTO notifications_read VALUES (?,?,?)').run('jira_mention', 'X-1', '2026-01-01');
  legacy.close();
  return 'u-joao';
}

// Uma credencial como ela era guardada entre o estágio 2 e o multiusuário
// completo: uma linha por provedor.
function seedLegacyCredential(userId: string, provider: string, ciphertext: string): void {
  const legacy = new Database(dbFile);
  legacy.exec(`
    CREATE TABLE IF NOT EXISTS credentials (
      user_id TEXT NOT NULL, provider TEXT NOT NULL, ciphertext TEXT NOT NULL,
      updated_at TEXT NOT NULL, PRIMARY KEY (user_id, provider)
    );
  `);
  legacy
    .prepare('INSERT INTO credentials VALUES (?,?,?,?)')
    .run(userId, provider, ciphertext, '2026-01-02');
  legacy.close();
}

describe('migração para escopo por usuário', () => {
  it('preserva as notificações lidas, atribuindo ao primeiro admin', async () => {
    const owner = seedLegacyDatabase();
    const { getDb } = await import('@/lib/db');

    const read = getDb()
      .prepare('SELECT user_id, external_id FROM notifications_read')
      .get() as { user_id: string };
    expect(read.user_id).toBe(owner);
  });

  // As caixas deixaram de ser 'work'/'personal' e viraram conexões com id
  // próprio: um corpo indexado pelo nome antigo não pertence a conexão
  // nenhuma. Descartar é mais barato do que adivinhar — o cache se refaz no
  // primeiro ciclo do refresher.
  it('descarta o cache de e-mail preso aos nomes de conta antigos', async () => {
    seedLegacyDatabase();
    const { getDb } = await import('@/lib/db');
    const count = getDb().prepare('SELECT count(*) c FROM email_bodies').get() as { c: number };
    expect(count.c).toBe(0);
  });

  it('cria as tabelas de conexões e de módulos', async () => {
    seedLegacyDatabase();
    const { getDb } = await import('@/lib/db');
    const conn = getDb().prepare('PRAGMA table_info(connections)').all() as { name: string }[];
    expect(conn.map((c) => c.name)).toEqual([
      'id',
      'user_id',
      'module',
      'label',
      'ciphertext',
      'created_at',
      'updated_at',
    ]);
    const mods = getDb().prepare('PRAGMA table_info(module_settings)').all() as { name: string }[];
    expect(mods.map((c) => c.name)).toEqual(['user_id', 'module', 'enabled', 'updated_at']);
  });

  it('leva a credencial antiga para a conexão do módulo correspondente', async () => {
    const owner = seedLegacyDatabase();
    seedLegacyCredential(owner, 'github', 'cifrado-github');

    const { getDb } = await import('@/lib/db');
    const row = getDb()
      .prepare('SELECT module, ciphertext FROM connections WHERE user_id = ?')
      .get(owner) as { module: string; ciphertext: string };
    // O ciphertext é copiado sem ser aberto: a migração roda na subida,
    // quando a chave pode nem estar no ambiente.
    expect(row).toEqual({ module: 'pulls', ciphertext: 'cifrado-github' });
  });

  it('roda uma vez só — reabrir não duplica nem apaga dados', async () => {
    const owner = seedLegacyDatabase();
    seedLegacyCredential(owner, 'jira', 'cifrado-jira');
    const { getDb } = await import('@/lib/db');
    const version = getDb().pragma('user_version', { simple: true });

    vi.resetModules();
    const again = await import('@/lib/db');
    const db = again.getDb();
    expect(db.pragma('user_version', { simple: true })).toBe(version);
    expect((db.prepare('SELECT count(*) c FROM connections').get() as { c: number }).c).toBe(1);
    expect((db.prepare('SELECT count(*) c FROM notifications_read').get() as { c: number }).c).toBe(1);
  });

  it('banco novo já nasce migrado', async () => {
    const { getDb } = await import('@/lib/db');
    const cols = getDb().prepare('PRAGMA table_info(email_bodies)').all() as { name: string }[];
    expect(cols.map((c) => c.name)).toContain('user_id');
  });
});

describe('cópia das notas no Drive', () => {
  // O banco como ficou depois da migração das notas e antes da cópia no Drive.
  function seedNotesDatabase(): void {
    const legacy = new Database(dbFile);
    legacy.exec(`
      CREATE TABLE notes (
        id TEXT PRIMARY KEY, user_id TEXT NOT NULL, title TEXT NOT NULL DEFAULT '',
        body TEXT NOT NULL DEFAULT '', position INTEGER NOT NULL,
        created_at TEXT NOT NULL, updated_at TEXT NOT NULL
      );
      INSERT INTO notes VALUES ('n-1', 'u-1', 'Antiga', 'texto', 0, '2026-08-01', '2026-08-01');
    `);
    legacy.pragma('user_version = 7');
    legacy.close();
  }

  // As notas que já existiam não são despejadas no Drive ao conectar.
  it('notas anteriores entram como já enviadas', async () => {
    seedNotesDatabase();
    const { pendingNotes, countPendingSync, listNotes } = await import('@/lib/notes');

    expect(listNotes('u-1').map((n) => n.body)).toEqual(['texto']);
    expect(pendingNotes('u-1')).toEqual([]);
    expect(countPendingSync('u-1')).toBe(0);
  });

  it('nota anterior editada depois passa a subir', async () => {
    seedNotesDatabase();
    const { pendingNotes, updateNote } = await import('@/lib/notes');

    updateNote('u-1', 'n-1', { body: 'editada' });

    expect(pendingNotes('u-1').map((n) => n.body)).toEqual(['editada']);
  });
});

describe('pastas das notas', () => {
  it('a nota que já existia continua lá, agora sem pasta', async () => {
    const legacy = new Database(dbFile);
    legacy.exec(`
      CREATE TABLE notes (
        id TEXT PRIMARY KEY, user_id TEXT NOT NULL, title TEXT NOT NULL DEFAULT '',
        body TEXT NOT NULL DEFAULT '', position INTEGER NOT NULL,
        created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
        revision INTEGER NOT NULL DEFAULT 1, synced_revision INTEGER NOT NULL DEFAULT 0
      );
      CREATE TABLE note_deletions (
        user_id TEXT NOT NULL, note_id TEXT NOT NULL, deleted_at TEXT NOT NULL,
        PRIMARY KEY (user_id, note_id)
      );
      INSERT INTO notes VALUES ('n-1', 'u-1', 'Antiga', 'texto', 0, '2026-08-01', '2026-08-01', 1, 1);
    `);
    legacy.pragma('user_version = 12');
    legacy.close();

    const { listNotes } = await import('@/lib/notes');
    const { listFolders } = await import('@/lib/noteFolders');

    expect(listNotes('u-1')).toEqual([
      {
        id: 'n-1',
        title: 'Antiga',
        body: 'texto',
        position: 0,
        updatedAt: '2026-08-01',
        folderId: null,
      },
    ]);
    expect(listFolders('u-1')).toEqual([]);
  });

  it('a migração das pastas roda uma vez só', async () => {
    const { getDb } = await import('@/lib/db');
    const { createFolder, listFolders } = await import('@/lib/noteFolders');
    createFolder('u-1', 'Trabalho');
    const version = getDb().pragma('user_version', { simple: true });

    // Uma segunda abertura do mesmo arquivo não repete o ALTER TABLE nem
    // perde o que já estava gravado.
    const again = new Database(dbFile);
    again.close();
    process.env.DAILY_WEB_DB_PATH = dbFile;
    vi.resetModules();
    const { getDb: reopen } = await import('@/lib/db');
    expect(reopen().pragma('user_version', { simple: true })).toBe(version);
    const { listFolders: relist } = await import('@/lib/noteFolders');
    expect(relist('u-1')).toHaveLength(1);
  });
});

describe('coluna Fazendo do quadro de tarefas', () => {
  // O banco como ficou depois das pastas das notas, com tarefas de verdade.
  function seedTasksDatabase(): void {
    const legacy = new Database(dbFile);
    legacy.exec(`
      CREATE TABLE tasks (
        id TEXT PRIMARY KEY, user_id TEXT NOT NULL, title TEXT NOT NULL,
        completed INTEGER NOT NULL DEFAULT 0, due TEXT NOT NULL DEFAULT '',
        time TEXT NOT NULL DEFAULT '', priority TEXT NOT NULL DEFAULT 'normal',
        recur TEXT NOT NULL DEFAULT '', notes TEXT NOT NULL DEFAULT '',
        position INTEGER NOT NULL, created_at TEXT NOT NULL
      );
      CREATE TABLE subtasks (
        id TEXT PRIMARY KEY, task_id TEXT NOT NULL, title TEXT NOT NULL,
        completed INTEGER NOT NULL DEFAULT 0, position INTEGER NOT NULL
      );
      INSERT INTO tasks (id, user_id, title, completed, position, created_at)
        VALUES ('t-1', 'u-1', 'Aberta', 0, 1, '2026-09-01'), ('t-2', 'u-1', 'Feita', 1, 2, '2026-09-01');
      INSERT INTO subtasks VALUES ('s-1', 't-1', 'Etapa', 1, 1);
    `);
    legacy.pragma('user_version = 13');
    legacy.close();
  }

  it('as tarefas que já existiam continuam lá, todas fora de Fazendo', async () => {
    seedTasksDatabase();
    const { listTasks } = await import('@/lib/tasks/local');
    const { withBoardOverlay } = await import('@/lib/tasks/boardStatus');

    const tasks = withBoardOverlay('u-1', listTasks('u-1'));
    expect(tasks.map((t) => [t.title, t.completed, t.doing])).toEqual([
      ['Aberta', false, false],
      ['Feita', true, false],
    ]);
    expect(tasks[0].subtasks).toEqual([{ id: 's-1', title: 'Etapa', completed: true }]);
  });

  it('a migração roda uma vez só e não perde a marcação gravada', async () => {
    seedTasksDatabase();
    const { getDb } = await import('@/lib/db');
    const { markDoing } = await import('@/lib/tasks/boardStatus');
    markDoing('u-1', 't-1');
    const version = getDb().pragma('user_version', { simple: true });
    expect(version).toBe(15);

    vi.resetModules();
    const { getDb: reopen } = await import('@/lib/db');
    expect(reopen().pragma('user_version', { simple: true })).toBe(version);
    const { doingTaskIds } = await import('@/lib/tasks/boardStatus');
    expect([...doingTaskIds('u-1')]).toEqual(['t-1']);
  });

  it('recusa um status que não é fazendo', async () => {
    const { getDb } = await import('@/lib/db');
    expect(() =>
      getDb()
        .prepare("INSERT INTO task_board_status VALUES ('u-1', 't-1', 'feito', '2026-10-23')")
        .run(),
    ).toThrow();
  });
});

describe('cor das notas do quadro de tarefas', () => {
  // O banco como ficou depois da coluna Fazendo, com tarefas e uma marcação.
  function seedBoardDatabase(): void {
    const legacy = new Database(dbFile);
    legacy.exec(`
      CREATE TABLE tasks (
        id TEXT PRIMARY KEY, user_id TEXT NOT NULL, title TEXT NOT NULL,
        completed INTEGER NOT NULL DEFAULT 0, due TEXT NOT NULL DEFAULT '',
        time TEXT NOT NULL DEFAULT '', priority TEXT NOT NULL DEFAULT 'normal',
        recur TEXT NOT NULL DEFAULT '', notes TEXT NOT NULL DEFAULT '',
        position INTEGER NOT NULL, created_at TEXT NOT NULL
      );
      CREATE TABLE subtasks (
        id TEXT PRIMARY KEY, task_id TEXT NOT NULL, title TEXT NOT NULL,
        completed INTEGER NOT NULL DEFAULT 0, position INTEGER NOT NULL
      );
      CREATE TABLE task_board_status (
        user_id TEXT NOT NULL, task_id TEXT NOT NULL,
        status TEXT NOT NULL CHECK (status IN ('doing')), updated_at TEXT NOT NULL,
        PRIMARY KEY (user_id, task_id)
      );
      INSERT INTO tasks (id, user_id, title, completed, priority, position, created_at)
        VALUES ('t-1', 'u-1', 'Aberta', 0, 'high', 1, '2026-09-01'),
               ('t-2', 'u-1', 'Feita', 1, 'normal', 2, '2026-09-01');
      INSERT INTO task_board_status VALUES ('u-1', 't-1', 'doing', '2026-10-23');
    `);
    legacy.pragma('user_version = 14');
    legacy.close();
  }

  it('as tarefas e a marcação de Fazendo continuam, todas com cor automática', async () => {
    seedBoardDatabase();
    const { getDb } = await import('@/lib/db');
    expect(getDb().pragma('user_version', { simple: true })).toBe(15);
    const { listTasks } = await import('@/lib/tasks/local');
    const { withBoardOverlay } = await import('@/lib/tasks/boardStatus');

    const tasks = withBoardOverlay('u-1', listTasks('u-1'));
    expect(tasks.map((t) => [t.title, t.doing, t.paper, t.pin])).toEqual([
      ['Aberta', true, null, null],
      ['Feita', false, null, null],
    ]);
  });

  it('a migração roda uma vez só e não perde a cor gravada', async () => {
    seedBoardDatabase();
    const { setBoardStyle } = await import('@/lib/tasks/boardStyle');
    setBoardStyle('u-1', 't-1', { paper: 'grey', pin: 'red' });

    vi.resetModules();
    const { getDb: reopen } = await import('@/lib/db');
    expect(reopen().pragma('user_version', { simple: true })).toBe(15);
    const { boardStyleOf } = await import('@/lib/tasks/boardStyle');
    expect(boardStyleOf('u-1', 't-1')).toEqual({ paper: 'grey', pin: 'red' });
  });

  // CREATE TABLE IF NOT EXISTS: um banco que já tem a tabela (uma migração
  // interrompida depois do CREATE) não quebra ao rodar de novo.
  it('rodar a migração sobre uma tabela que já existe não falha nem apaga linhas', async () => {
    seedBoardDatabase();
    const half = new Database(dbFile);
    half.exec(`
      CREATE TABLE task_board_style (
        user_id TEXT NOT NULL, task_id TEXT NOT NULL, paper TEXT, pin TEXT,
        updated_at TEXT NOT NULL, PRIMARY KEY (user_id, task_id)
      );
      INSERT INTO task_board_style VALUES ('u-1', 't-2', 'white', NULL, '2026-10-23');
    `);
    half.close();
    const { getDb } = await import('@/lib/db');
    expect(getDb().pragma('user_version', { simple: true })).toBe(15);
    const { boardStyleOf } = await import('@/lib/tasks/boardStyle');
    expect(boardStyleOf('u-1', 't-2')).toEqual({ paper: 'white', pin: null });
  });
});
