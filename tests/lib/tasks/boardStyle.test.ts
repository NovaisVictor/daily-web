import { describe, expect, it, beforeEach, afterEach } from 'vitest';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';

let dir: string;

beforeEach(async () => {
  dir = mkdtempSync(path.join(tmpdir(), 'daily-web-board-style-'));
  process.env.DAILY_WEB_DB_PATH = path.join(dir, 'test.db');
  const { getDb } = await import('@/lib/db');
  getDb();
});

afterEach(() => {
  rmSync(dir, { recursive: true, force: true });
});

const USER = 'user-1';
const OTHER = 'user-2';

async function rows(): Promise<number> {
  const { getDb } = await import('@/lib/db');
  return (getDb().prepare('SELECT count(*) c FROM task_board_style').get() as { c: number }).c;
}

// Sem conexão cadastrada o despachante usa o provedor local, então estes
// testes passam pelo mesmo caminho que as rotas.
describe('cor da nota no quadro', () => {
  it('tarefa nova começa com papel e alfinete automáticos', async () => {
    const { addTask, fetchTasks } = await import('@/lib/tasks');
    await addTask(USER, 'Escrever relatório');
    expect((await fetchTasks(USER))[0]).toMatchObject({ paper: null, pin: null });
  });

  it('a cor escolhida aparece na listagem', async () => {
    const { addTask, fetchTasks, setTaskStyle } = await import('@/lib/tasks');
    const id = await addTask(USER, 'Escrever relatório');
    expect(setTaskStyle(USER, id, { paper: 'pink', pin: 'blue' })).toEqual({ paper: 'pink', pin: 'blue' });
    expect((await fetchTasks(USER))[0]).toMatchObject({ paper: 'pink', pin: 'blue' });
  });

  it('mudança parcial: o campo ausente fica como está e null volta ao automático', async () => {
    const { addTask, setTaskStyle } = await import('@/lib/tasks');
    const { boardStyleOf } = await import('@/lib/tasks/boardStyle');
    const id = await addTask(USER, 'Escrever relatório');
    setTaskStyle(USER, id, { paper: 'grey' });
    setTaskStyle(USER, id, { pin: 'green' });
    expect(boardStyleOf(USER, id)).toEqual({ paper: 'grey', pin: 'green' });

    setTaskStyle(USER, id, { paper: null });
    expect(boardStyleOf(USER, id)).toEqual({ paper: null, pin: 'green' });
    expect(await rows()).toBe(1);
  });

  it('os dois de volta ao automático apagam a linha', async () => {
    const { addTask, setTaskStyle } = await import('@/lib/tasks');
    const id = await addTask(USER, 'Escrever relatório');
    setTaskStyle(USER, id, { paper: 'white', pin: 'red' });
    setTaskStyle(USER, id, { paper: null, pin: null });
    expect(await rows()).toBe(0);
  });

  // Ao contrário de Fazendo, a cor não é a coluna: concluir, reabrir e mover
  // não podem levar a escolha embora.
  it('concluir, reabrir e mover não apagam a cor', async () => {
    const { addTask, fetchTasks, setCompleted, setDoing, setTaskStyle } = await import('@/lib/tasks');
    const id = await addTask(USER, 'Escrever relatório');
    setTaskStyle(USER, id, { paper: 'blue', pin: 'yellow' });
    setDoing(USER, id, true);
    setDoing(USER, id, false);
    await setCompleted(USER, id, true);
    expect((await fetchTasks(USER))[0]).toMatchObject({ completed: true, paper: 'blue', pin: 'yellow' });
    await setCompleted(USER, id, false);
    expect((await fetchTasks(USER))[0]).toMatchObject({ completed: false, paper: 'blue', pin: 'yellow' });
  });

  it('apagar a tarefa apaga a cor', async () => {
    const { addTask, deleteTask, setTaskStyle } = await import('@/lib/tasks');
    const id = await addTask(USER, 'Escrever relatório');
    setTaskStyle(USER, id, { paper: 'pink' });
    await deleteTask(USER, id);
    expect(await rows()).toBe(0);
  });

  it('a cor de um usuário não vale para outro', async () => {
    const { setBoardStyle, boardStyles } = await import('@/lib/tasks/boardStyle');
    setBoardStyle(USER, 'T1', { paper: 'green' });
    expect(boardStyles(OTHER).size).toBe(0);
    expect(boardStyles(USER).get('T1')).toEqual({ paper: 'green', pin: null });
  });

  // Sem CHECK no banco, uma cor que saiu da paleta (ou gravada à mão) ainda
  // pode estar lá; ela tem de chegar à tela como automática.
  it('uma cor desconhecida gravada no banco é lida como automática', async () => {
    const { getDb } = await import('@/lib/db');
    const { boardStyles } = await import('@/lib/tasks/boardStyle');
    getDb()
      .prepare("INSERT INTO task_board_style VALUES (?, 'T1', 'teal', 'purple', '2026-10-23')")
      .run(USER);
    getDb()
      .prepare("INSERT INTO task_board_style VALUES (?, 'T2', 'pink', 'magenta', '2026-10-23')")
      .run(USER);
    expect(boardStyles(USER).get('T1')).toEqual({ paper: null, pin: null });
    expect(boardStyles(USER).get('T2')).toEqual({ paper: 'pink', pin: null });
  });
});
