import Database from 'better-sqlite3';
import path from 'node:path';
import fs from 'node:fs';

function resolveDbPath(): string {
  return process.env.DAILY_WEB_DB_PATH ?? path.join(process.cwd(), 'data', 'daily-web.db');
}

let db: Database.Database | null = null;
let dbPath: string | null = null;

// Schema base. Idempotente: vale tanto para um banco novo quanto para um que
// já existia antes das migrações numeradas abaixo.
const BASE_SCHEMA = `
  CREATE TABLE IF NOT EXISTS notifications_read (
    source TEXT NOT NULL,
    external_id TEXT NOT NULL,
    read_at TEXT NOT NULL,
    PRIMARY KEY (source, external_id)
  );

  CREATE TABLE IF NOT EXISTS email_bodies (
    account TEXT NOT NULL,
    message_id TEXT NOT NULL,
    body TEXT NOT NULL,
    cached_at TEXT NOT NULL,
    PRIMARY KEY (account, message_id)
  );

  CREATE TABLE IF NOT EXISTS users (
    id TEXT PRIMARY KEY,
    username TEXT NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    is_admin INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL
  );
`;

// SQLite não altera chave primária com ALTER TABLE, então acrescentar user_id
// à PK exige reconstruir a tabela. As linhas que já existiam são do dono da
// instalação — o primeiro admin — e vão para ele em vez de serem descartadas.
function addUserScope(instance: Database.Database): void {
  const owner =
    (instance.prepare('SELECT id FROM users WHERE is_admin = 1 ORDER BY created_at').get() as
      | { id: string }
      | undefined)?.id ?? null;

  instance.exec(`
    CREATE TABLE email_bodies_new (
      user_id TEXT NOT NULL,
      account TEXT NOT NULL,
      message_id TEXT NOT NULL,
      body TEXT NOT NULL,
      cached_at TEXT NOT NULL,
      PRIMARY KEY (user_id, account, message_id)
    );
    CREATE TABLE notifications_read_new (
      user_id TEXT NOT NULL,
      source TEXT NOT NULL,
      external_id TEXT NOT NULL,
      read_at TEXT NOT NULL,
      PRIMARY KEY (user_id, source, external_id)
    );
  `);

  if (owner) {
    instance
      .prepare(
        `INSERT INTO email_bodies_new (user_id, account, message_id, body, cached_at)
         SELECT ?, account, message_id, body, cached_at FROM email_bodies`,
      )
      .run(owner);
    instance
      .prepare(
        `INSERT INTO notifications_read_new (user_id, source, external_id, read_at)
         SELECT ?, source, external_id, read_at FROM notifications_read`,
      )
      .run(owner);
  }

  instance.exec(`
    DROP TABLE email_bodies;
    DROP TABLE notifications_read;
    ALTER TABLE email_bodies_new RENAME TO email_bodies;
    ALTER TABLE notifications_read_new RENAME TO notifications_read;

    CREATE TABLE IF NOT EXISTS credentials (
      user_id TEXT NOT NULL,
      provider TEXT NOT NULL,
      ciphertext TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      PRIMARY KEY (user_id, provider)
    );
  `);
}

// Uma credencial por provedor não comporta duas caixas de e-mail nem duas
// agendas. `connections` guarda N conexões por módulo, cada uma com rótulo
// próprio. O ciphertext das credenciais antigas é copiado sem ser aberto: a
// migração roda na subida, quando DAILY_WEB_SECRET_KEY pode nem estar no env.
const CREDENTIAL_TO_MODULE: Record<string, string> = {
  jira: 'jira',
  github: 'pulls',
  mstodo: 'tasks',
};

function addConnections(instance: Database.Database): void {
  instance.exec(`
    CREATE TABLE IF NOT EXISTS connections (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      module TEXT NOT NULL,
      label TEXT NOT NULL,
      ciphertext TEXT NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );
    CREATE INDEX IF NOT EXISTS idx_connections_user_module
      ON connections (user_id, module);

    CREATE TABLE IF NOT EXISTS module_settings (
      user_id TEXT NOT NULL,
      module TEXT NOT NULL,
      enabled INTEGER NOT NULL,
      updated_at TEXT NOT NULL,
      PRIMARY KEY (user_id, module)
    );
  `);

  const hasCredentials = instance
    .prepare(`SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'credentials'`)
    .get();
  if (!hasCredentials) return;

  const rows = instance
    .prepare('SELECT user_id, provider, ciphertext, updated_at FROM credentials')
    .all() as { user_id: string; provider: string; ciphertext: string; updated_at: string }[];

  const insert = instance.prepare(
    `INSERT INTO connections (id, user_id, module, label, ciphertext, created_at, updated_at)
     VALUES (?, ?, ?, ?, ?, ?, ?)`,
  );
  for (const row of rows) {
    const moduleId = CREDENTIAL_TO_MODULE[row.provider];
    if (!moduleId) continue;
    insert.run(
      `${row.user_id}:${moduleId}`,
      row.user_id,
      moduleId,
      moduleId,
      row.ciphertext,
      row.updated_at,
      row.updated_at,
    );
  }
}

// As caixas de e-mail deixam de ser 'work'/'personal' fixos e passam a ser
// conexões com id próprio. Os corpos em cache estão indexados pelo nome
// antigo, que não corresponde a conexão nenhuma: descartar é mais barato e
// mais correto do que adivinhar um dono — o cache se reconstrói sozinho.
function dropLegacyEmailCache(instance: Database.Database): void {
  instance.exec('DELETE FROM email_bodies');
}

// Tarefas guardadas na própria app. É o provedor padrão: quem clona o repo
// não tem a CLI mstodo, e um dashboard cujo painel principal exige instalar
// uma ferramenta externa não serve para quem está começando.
function addLocalTasks(instance: Database.Database): void {
  instance.exec(`
    CREATE TABLE IF NOT EXISTS tasks (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      title TEXT NOT NULL,
      completed INTEGER NOT NULL DEFAULT 0,
      due TEXT NOT NULL DEFAULT '',
      time TEXT NOT NULL DEFAULT '',
      priority TEXT NOT NULL DEFAULT 'normal',
      recur TEXT NOT NULL DEFAULT '',
      notes TEXT NOT NULL DEFAULT '',
      position INTEGER NOT NULL,
      created_at TEXT NOT NULL
    );
    CREATE INDEX IF NOT EXISTS idx_tasks_user ON tasks (user_id, position);

    CREATE TABLE IF NOT EXISTS subtasks (
      id TEXT PRIMARY KEY,
      task_id TEXT NOT NULL,
      title TEXT NOT NULL,
      completed INTEGER NOT NULL DEFAULT 0,
      position INTEGER NOT NULL
    );
    CREATE INDEX IF NOT EXISTS idx_subtasks_task ON subtasks (task_id, position);
  `);
}

// Preferências de visualização, por usuário. Diferente de `module_settings`,
// que liga e desliga um módulo: aqui fica o como, não o se — por enquanto
// quantos dias a agenda mostra. Chave-valor porque cada preferência nova não
// deve custar uma migração.
function addPreferences(instance: Database.Database): void {
  instance.exec(`
    CREATE TABLE IF NOT EXISTS preferences (
      user_id TEXT NOT NULL,
      key TEXT NOT NULL,
      value TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      PRIMARY KEY (user_id, key)
    );
  `);
}

// Migrações numeradas, aplicadas em ordem a partir do `user_version` do banco.
// Cada uma roda no máximo uma vez, em transação.
// O uid do IMAP é por caixa: o mesmo número aponta para mensagens diferentes
// na entrada e nos enviados. Sem a caixa na chave, o corpo de uma serviria a
// outra. O que já está gravado veio todo da entrada.
function addMailboxToBodyCache(instance: Database.Database): void {
  instance.exec(`
    CREATE TABLE email_bodies_new (
      user_id TEXT NOT NULL,
      account TEXT NOT NULL,
      mailbox TEXT NOT NULL,
      message_id TEXT NOT NULL,
      body TEXT NOT NULL,
      cached_at TEXT NOT NULL,
      PRIMARY KEY (user_id, account, mailbox, message_id)
    );
    INSERT INTO email_bodies_new (user_id, account, mailbox, message_id, body, cached_at)
      SELECT user_id, account, 'inbox', message_id, body, cached_at FROM email_bodies;
    DROP TABLE email_bodies;
    ALTER TABLE email_bodies_new RENAME TO email_bodies;
  `);
}

// Notas rápidas: uma linha por aba, do usuário. Ficam no servidor para
// aparecerem em qualquer máquina onde ele entrar.
function addNotes(instance: Database.Database): void {
  instance.exec(`
    CREATE TABLE IF NOT EXISTS notes (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      title TEXT NOT NULL DEFAULT '',
      body TEXT NOT NULL DEFAULT '',
      position INTEGER NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );
    CREATE INDEX IF NOT EXISTS idx_notes_user ON notes (user_id, position);
  `);
}

// Cópia das notas no Google Drive. `revision` sobe a cada gravação e
// `synced_revision` guarda a última que chegou ao Drive: a nota está pendente
// enquanto as duas diferem. Um contador, e não o `updated_at`, porque
// reordenar muda a nota sem mudar o texto. As notas que já existiam entram
// como enviadas — não são despejadas no Drive ao conectar; sobem na próxima
// vez que forem editadas.
// Apagar uma nota que já subiu deixa um registro em `note_deletions` até o
// arquivo ir para a lixeira do Drive; sem ele a nota voltaria na restauração.
function addNoteSync(instance: Database.Database): void {
  instance.exec(`
    ALTER TABLE notes ADD COLUMN revision INTEGER NOT NULL DEFAULT 1;
    ALTER TABLE notes ADD COLUMN synced_revision INTEGER NOT NULL DEFAULT 0;
    UPDATE notes SET synced_revision = revision;
    CREATE TABLE IF NOT EXISTS note_deletions (
      user_id TEXT NOT NULL,
      note_id TEXT NOT NULL,
      deleted_at TEXT NOT NULL,
      PRIMARY KEY (user_id, note_id)
    );
  `);
}

// O que o usuário pediu, guardado antes de a ação chegar ao servidor. Sem
// isto a intenção vivia num cache de memória: o retrato seguinte do IMAP
// desfazia a exclusão e o reinício do serviço apagava o que ainda não tinha
// chegado ao servidor. `uidvalidity` entra na chave porque o uid só tem
// sentido enquanto ele não muda.
function addEmailPendingActions(instance: Database.Database): void {
  instance.exec(`
    CREATE TABLE IF NOT EXISTS email_pending_actions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id TEXT NOT NULL,
      account TEXT NOT NULL,
      mailbox TEXT NOT NULL,
      uidvalidity TEXT NOT NULL DEFAULT '',
      uid TEXT NOT NULL,
      action TEXT NOT NULL,
      payload TEXT,
      created_at TEXT NOT NULL,
      applied_at TEXT,
      attempts INTEGER NOT NULL DEFAULT 0,
      next_attempt_at TEXT NOT NULL,
      state TEXT NOT NULL DEFAULT 'pending',
      last_error TEXT
    );
    CREATE UNIQUE INDEX IF NOT EXISTS idx_email_pending_key
      ON email_pending_actions (user_id, account, mailbox, uidvalidity, uid, action);
    CREATE INDEX IF NOT EXISTS idx_email_pending_due
      ON email_pending_actions (user_id, state, next_attempt_at);
  `);
}

// A árvore de pastas de cada conta, com o que cada uma tem dentro. Listar
// pastas e contar mensagem é uma ida ao servidor por pasta: guardada aqui, a
// árvore abre na hora e só é refeita quando envelhece.
function addEmailMailboxes(instance: Database.Database): void {
  instance.exec(`
    CREATE TABLE IF NOT EXISTS email_mailboxes (
      user_id TEXT NOT NULL,
      account TEXT NOT NULL,
      path TEXT NOT NULL,
      name TEXT NOT NULL,
      delimiter TEXT NOT NULL DEFAULT '/',
      parent TEXT,
      special_use TEXT,
      uidvalidity TEXT NOT NULL DEFAULT '',
      total INTEGER NOT NULL DEFAULT 0,
      unread INTEGER NOT NULL DEFAULT 0,
      position INTEGER NOT NULL DEFAULT 0,
      synced_at TEXT NOT NULL,
      PRIMARY KEY (user_id, account, path)
    );
  `);
}

// As mensagens que já foram lidas do servidor, por pasta. Guardá-las é o que
// permite pedir só o que chegou depois do último uid conhecido, em vez de
// reler a caixa inteira a cada ciclo. `uidvalidity` entra na chave porque uma
// reindexação do servidor reaproveita os números para outras mensagens.
function addEmailMessages(instance: Database.Database): void {
  instance.exec(`
    CREATE TABLE IF NOT EXISTS email_messages (
      user_id TEXT NOT NULL,
      account TEXT NOT NULL,
      folder TEXT NOT NULL,
      uidvalidity TEXT NOT NULL,
      uid INTEGER NOT NULL,
      mailbox TEXT NOT NULL,
      account_label TEXT NOT NULL,
      sender TEXT NOT NULL,
      subject TEXT NOT NULL,
      unread INTEGER NOT NULL,
      date TEXT NOT NULL,
      message_id TEXT NOT NULL,
      refs TEXT NOT NULL,
      labels TEXT NOT NULL,
      PRIMARY KEY (user_id, account, folder, uidvalidity, uid)
    );
    CREATE INDEX IF NOT EXISTS idx_email_messages_folder
      ON email_messages (user_id, account, folder, uidvalidity, date DESC);
    ALTER TABLE email_mailboxes ADD COLUMN last_uid INTEGER NOT NULL DEFAULT 0;
  `);
}

// `move` passou a ser mudança de pasta de verdade; a cópia que o Gmail chama
// de etiqueta virou `tag`. O que já estava gravado era cópia.
function renameCopyActionToTag(instance: Database.Database): void {
  instance.exec("UPDATE email_pending_actions SET action = 'tag' WHERE action = 'move'");
}

// Pastas das notas. A nota guarda o id da pasta, ou NULL quando está solta —
// as notas que já existiam começam sem pasta, que é "Sem pasta" na tela.
// `revision`/`synced_revision` seguem o mesmo contrato das notas: a pasta está
// pendente enquanto as duas diferem, e apagar uma que já subiu deixa registro
// até a pasta espelhada ir para a lixeira do Drive.
function addNoteFolders(instance: Database.Database): void {
  instance.exec(`
    CREATE TABLE IF NOT EXISTS note_folders (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      parent_id TEXT,
      name TEXT NOT NULL,
      position INTEGER NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      revision INTEGER NOT NULL DEFAULT 1,
      synced_revision INTEGER NOT NULL DEFAULT 0
    );
    CREATE INDEX IF NOT EXISTS idx_note_folders_user
      ON note_folders (user_id, parent_id, position);

    CREATE TABLE IF NOT EXISTS note_folder_deletions (
      user_id TEXT NOT NULL,
      folder_id TEXT NOT NULL,
      deleted_at TEXT NOT NULL,
      PRIMARY KEY (user_id, folder_id)
    );

    ALTER TABLE notes ADD COLUMN folder_id TEXT;
    CREATE INDEX IF NOT EXISTS idx_notes_folder ON notes (user_id, folder_id, position);
  `);
}

// "In progress" for the kanban board. Neither provider has it — Microsoft To
// Do only knows open and completed — so it lives here, beside the task rather
// than inside it, keyed by the provider's own task id. That is what lets the
// same board work for local and mstodo tasks. Only "doing" is stored: "to do"
// is the absence of a row, and "done" stays the provider's completed flag.
function addTaskBoardStatus(instance: Database.Database): void {
  instance.exec(`
    CREATE TABLE IF NOT EXISTS task_board_status (
      user_id TEXT NOT NULL,
      task_id TEXT NOT NULL,
      status TEXT NOT NULL CHECK (status IN ('doing')),
      updated_at TEXT NOT NULL,
      PRIMARY KEY (user_id, task_id)
    );
  `);
}

// The paper and pin colour a person picked for a note on the board. A table
// of its own rather than columns on task_board_status: a missing row there
// means "A fazer" and the row is deleted on every completion and move back,
// which would take the colour with it. No CHECK on the colours, on purpose:
// SQLite cannot alter one, so every new colour would cost a table rebuild;
// the API validates on the way in and the read drops unknown values. NULL is
// "automatic", and a row with both NULL is deleted rather than kept.
function addTaskBoardStyle(instance: Database.Database): void {
  instance.exec(`
    CREATE TABLE IF NOT EXISTS task_board_style (
      user_id TEXT NOT NULL,
      task_id TEXT NOT NULL,
      paper TEXT,
      pin TEXT,
      updated_at TEXT NOT NULL,
      PRIMARY KEY (user_id, task_id)
    );
  `);
}

const MIGRATIONS: ((instance: Database.Database) => void)[] = [
  addUserScope,
  addConnections,
  dropLegacyEmailCache,
  addLocalTasks,
  addPreferences,
  addMailboxToBodyCache,
  addNotes,
  addNoteSync,
  addEmailPendingActions,
  addEmailMailboxes,
  addEmailMessages,
  renameCopyActionToTag,
  addNoteFolders,
  addTaskBoardStatus,
  addTaskBoardStyle,
];

function migrate(instance: Database.Database): void {
  const current = instance.pragma('user_version', { simple: true }) as number;
  for (let version = current; version < MIGRATIONS.length; version += 1) {
    instance.transaction(() => {
      MIGRATIONS[version](instance);
      instance.pragma(`user_version = ${version + 1}`);
    })();
  }
}

export function getDb(): Database.Database {
  const currentPath = resolveDbPath();
  if (db && dbPath === currentPath) return db;

  fs.mkdirSync(path.dirname(currentPath), { recursive: true });
  db = new Database(currentPath);
  dbPath = currentPath;
  db.pragma('journal_mode = WAL');
  db.exec(BASE_SCHEMA);
  migrate(db);
  return db;
}
