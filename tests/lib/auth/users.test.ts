import { describe, expect, it, beforeEach, afterEach, vi } from 'vitest';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';

let dir: string;
const ORIGINAL_ENV = { ...process.env };

beforeEach(() => {
  dir = mkdtempSync(path.join(tmpdir(), 'daily-web-users-'));
  process.env.DAILY_WEB_DB_PATH = path.join(dir, 'test.db');
  process.env.DAILY_WEB_SECRET_KEY = Buffer.alloc(32, 11).toString('base64');
  vi.resetModules();
});

afterEach(() => {
  rmSync(dir, { recursive: true, force: true });
  process.env = { ...ORIGINAL_ENV };
});

describe('cadastro de usuários', () => {
  it('cria um usuário e o encontra pelo username', async () => {
    const { createUser, findUserByUsername } = await import('@/lib/auth/users');
    const created = await createUser('maria', 'senha-da-maria');
    const found = findUserByUsername('maria');
    expect(found?.id).toBe(created.id);
    expect(found?.username).toBe('maria');
  });

  it('guarda a senha como hash, nunca em texto claro', async () => {
    const { createUser, findUserByUsername } = await import('@/lib/auth/users');
    await createUser('maria', 'senha-da-maria');
    expect(findUserByUsername('maria')?.passwordHash).not.toContain('senha-da-maria');
  });

  it('dá ids diferentes para usuários diferentes', async () => {
    const { createUser } = await import('@/lib/auth/users');
    const a = await createUser('maria', 'x1234567');
    const b = await createUser('joao', 'y1234567');
    expect(a.id).not.toBe(b.id);
  });

  it('recusa username repetido', async () => {
    const { createUser } = await import('@/lib/auth/users');
    await createUser('maria', 'x1234567');
    await expect(createUser('maria', 'outra-senha')).rejects.toThrow(/já existe/i);
  });

  it('recusa senha curta demais', async () => {
    const { createUser } = await import('@/lib/auth/users');
    await expect(createUser('maria', 'curta')).rejects.toThrow(/8 caracteres/i);
  });

  it('devolve null para username inexistente', async () => {
    const { findUserByUsername } = await import('@/lib/auth/users');
    expect(findUserByUsername('ninguem')).toBeNull();
  });

  it('remove um usuário', async () => {
    const { createUser, removeUser, findUserByUsername } = await import('@/lib/auth/users');
    await createUser('maria', 'x1234567');
    expect(removeUser('maria')).toBe(true);
    expect(findUserByUsername('maria')).toBeNull();
  });

  it('troca a senha sem mudar o id', async () => {
    const { createUser, setUserPassword, findUserByUsername } = await import('@/lib/auth/users');
    const created = await createUser('maria', 'x1234567');
    const before = findUserByUsername('maria')?.passwordHash;
    await setUserPassword('maria', 'nova-senha-123');
    const after = findUserByUsername('maria');
    expect(after?.id).toBe(created.id);
    expect(after?.passwordHash).not.toBe(before);
  });
});

describe('busca por id', () => {
  it('encontra pelo id', async () => {
    const { createUser, findUserById } = await import('@/lib/auth/users');
    const created = await createUser('maria', 'x1234567');
    expect(findUserById(created.id)?.username).toBe('maria');
  });

  it('devolve null para id inexistente', async () => {
    const { findUserById } = await import('@/lib/auth/users');
    expect(findUserById('nao-existe')).toBeNull();
  });
});

// Sem esta regra dá para ficar com um banco só de não-admins: ninguém
// consegue mais cadastrar nem promover ninguém, e o sistema fica travado.
describe('proteção do último admin', () => {
  it('recusa remover o único admin', async () => {
    const { createUser, removeUser } = await import('@/lib/auth/users');
    await createUser('joao', 'x1234567', true);
    await createUser('maria', 'y1234567');
    expect(() => removeUser('joao')).toThrow(/último admin/i);
  });

  it('permite remover um admin quando existe outro', async () => {
    const { createUser, removeUser, listUsers } = await import('@/lib/auth/users');
    await createUser('joao', 'x1234567', true);
    await createUser('ana', 'y1234567', true);
    expect(removeUser('joao')).toBe(true);
    expect(listUsers().map((u) => u.username)).toEqual(['ana']);
  });

  it('permite remover um não-admin sem restrição', async () => {
    const { createUser, removeUser } = await import('@/lib/auth/users');
    await createUser('joao', 'x1234567', true);
    await createUser('maria', 'y1234567');
    expect(removeUser('maria')).toBe(true);
  });
});

describe('bootstrap do primeiro admin', () => {
  it('semeia o operador a partir do env quando a tabela está vazia', async () => {
    process.env.DASHBOARD_USER = 'joao';
    process.env.DASHBOARD_PASSWORD_HASH = '$2a$10$hashquejaexistia';
    const { bootstrapFirstUser, findUserByUsername } = await import('@/lib/auth/users');
    bootstrapFirstUser();
    const seeded = findUserByUsername('joao');
    // O hash antigo é reaproveitado: a senha que ele já usa continua valendo.
    expect(seeded?.passwordHash).toBe('$2a$10$hashquejaexistia');
    expect(seeded?.isAdmin).toBe(true);
  });

  it('não semeia de novo quando já existe alguém', async () => {
    process.env.DASHBOARD_USER = 'joao';
    process.env.DASHBOARD_PASSWORD_HASH = '$2a$10$hashquejaexistia';
    const { createUser, bootstrapFirstUser, listUsers } = await import('@/lib/auth/users');
    await createUser('maria', 'x1234567');
    bootstrapFirstUser();
    expect(listUsers().map((u) => u.username)).toEqual(['maria']);
  });

  it('não faz nada quando o env não tem as variáveis de semente', async () => {
    delete process.env.DASHBOARD_USER;
    delete process.env.DASHBOARD_PASSWORD_HASH;
    const { bootstrapFirstUser, listUsers } = await import('@/lib/auth/users');
    bootstrapFirstUser();
    expect(listUsers()).toEqual([]);
  });
});

describe('remoção de usuário leva os dados junto', () => {
  it('apaga conexões, tarefas, subtarefas, cache e notificações da pessoa', async () => {
    const { createUser, removeUser } = await import('@/lib/auth/users');
    const { saveConnection } = await import('@/lib/vault/connections');
    const local = await import('@/lib/tasks/local');
    const { putCachedBody } = await import('@/lib/emailCache');
    const { markRead } = await import('@/lib/notifications');
    const { markDoing } = await import('@/lib/tasks/boardStatus');
    const { setBoardStyle } = await import('@/lib/tasks/boardStyle');
    const { getDb } = await import('@/lib/db');

    const admin = await createUser('chefe', 'senha-boa-123', true);
    const alvo = await createUser('temporario', 'senha-boa-123');

    saveConnection(alvo.id, 'jira', 'Jira', { cloud: 'a', email: 'e', token: 'segredo' });
    const taskId = local.addTask(alvo.id, 'Tarefa dele');
    local.addSubtask(alvo.id, taskId, 'Etapa');
    markDoing(alvo.id, taskId);
    setBoardStyle(alvo.id, taskId, { paper: 'pink', pin: 'blue' });
    putCachedBody(alvo.id, 'mail-1', '1', 'corpo');
    markRead(alvo.id, 'jira_mention', 'X-1');

    expect(removeUser('temporario')).toBe(true);

    const db = getDb();
    const count = (sql: string) => (db.prepare(sql).get(alvo.id) as { c: number }).c;
    expect(count('SELECT count(*) c FROM connections WHERE user_id = ?')).toBe(0);
    expect(count('SELECT count(*) c FROM tasks WHERE user_id = ?')).toBe(0);
    expect(count('SELECT count(*) c FROM task_board_status WHERE user_id = ?')).toBe(0);
    expect(count('SELECT count(*) c FROM task_board_style WHERE user_id = ?')).toBe(0);
    expect(count('SELECT count(*) c FROM email_bodies WHERE user_id = ?')).toBe(0);
    expect(count('SELECT count(*) c FROM notifications_read WHERE user_id = ?')).toBe(0);
    expect(
      (db.prepare('SELECT count(*) c FROM subtasks WHERE task_id = ?').get(taskId) as { c: number })
        .c,
    ).toBe(0);

    // O resto da instalação fica intacto.
    expect(db.prepare('SELECT count(*) c FROM users').get()).toEqual({ c: 1 });
    expect(admin.username).toBe('chefe');
  });

  it('não mexe nos dados de quem fica', async () => {
    const { createUser, removeUser } = await import('@/lib/auth/users');
    const { saveConnection, listConnections } = await import('@/lib/vault/connections');

    const fica = await createUser('fica', 'senha-boa-123', true);
    const sai = await createUser('sai', 'senha-boa-123');
    saveConnection(fica.id, 'jira', 'Jira', { cloud: 'a', email: 'e', token: 't' });
    saveConnection(sai.id, 'jira', 'Jira', { cloud: 'b', email: 'f', token: 'u' });

    removeUser('sai');

    expect(listConnections(fica.id, 'jira')).toHaveLength(1);
  });
});
