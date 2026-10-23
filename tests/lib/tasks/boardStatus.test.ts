import { describe, expect, it, beforeEach, afterEach } from 'vitest';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';

let dir: string;

beforeEach(async () => {
  dir = mkdtempSync(path.join(tmpdir(), 'daily-web-board-'));
  process.env.DAILY_WEB_DB_PATH = path.join(dir, 'test.db');
  const { getDb } = await import('@/lib/db');
  getDb();
});

afterEach(() => {
  rmSync(dir, { recursive: true, force: true });
});

const USER = 'user-1';
const OTHER = 'user-2';

// Sem conexão cadastrada o despachante usa o provedor local, então estes
// testes passam pelo mesmo caminho que as rotas.
describe('coluna Fazendo do quadro', () => {
  it('tarefa nova começa fora de Fazendo', async () => {
    const { addTask, fetchTasks } = await import('@/lib/tasks');
    await addTask(USER, 'Escrever relatório');
    const [task] = await fetchTasks(USER);
    expect(task.doing).toBe(false);
  });

  it('marcar e desmarcar Fazendo aparece na listagem', async () => {
    const { addTask, fetchTasks, setDoing } = await import('@/lib/tasks');
    const id = await addTask(USER, 'Escrever relatório');

    setDoing(USER, id, true);
    expect((await fetchTasks(USER))[0].doing).toBe(true);

    setDoing(USER, id, false);
    expect((await fetchTasks(USER))[0].doing).toBe(false);
  });

  it('marcar duas vezes não duplica a marcação', async () => {
    const { addTask, setDoing } = await import('@/lib/tasks');
    const { getDb } = await import('@/lib/db');
    const id = await addTask(USER, 'Escrever relatório');
    setDoing(USER, id, true);
    setDoing(USER, id, true);
    const { c } = getDb().prepare('SELECT count(*) c FROM task_board_status').get() as { c: number };
    expect(c).toBe(1);
  });

  it('concluir tira a tarefa de Fazendo, e reabrir não a devolve', async () => {
    const { addTask, fetchTasks, setDoing, setCompleted } = await import('@/lib/tasks');
    const id = await addTask(USER, 'Escrever relatório');
    setDoing(USER, id, true);

    await setCompleted(USER, id, true);
    expect((await fetchTasks(USER))[0]).toMatchObject({ completed: true, doing: false });

    await setCompleted(USER, id, false);
    expect((await fetchTasks(USER))[0]).toMatchObject({ completed: false, doing: false });
  });

  // Concluída por fora da app (no To Do do celular), a marcação continua no
  // banco; a tarefa ainda assim tem de aparecer só como feita.
  it('tarefa concluída nunca aparece como fazendo, mesmo com a marcação gravada', async () => {
    const { addTask, fetchTasks } = await import('@/lib/tasks');
    const { setCompleted: setLocalCompleted } = await import('@/lib/tasks/local');
    const { markDoing } = await import('@/lib/tasks/boardStatus');
    const id = await addTask(USER, 'Escrever relatório');
    markDoing(USER, id);
    setLocalCompleted(USER, id, true);

    expect((await fetchTasks(USER))[0]).toMatchObject({ completed: true, doing: false });
  });

  it('a marcação de um usuário não vale para outro', async () => {
    const { doingTaskIds, markDoing } = await import('@/lib/tasks/boardStatus');
    markDoing(USER, 'T1');
    expect(doingTaskIds(OTHER).size).toBe(0);
    expect([...doingTaskIds(USER)]).toEqual(['T1']);
  });

  it('apagar a tarefa apaga a marcação', async () => {
    const { addTask, deleteTask, setDoing } = await import('@/lib/tasks');
    const { doingTaskIds } = await import('@/lib/tasks/boardStatus');
    const id = await addTask(USER, 'Escrever relatório');
    setDoing(USER, id, true);
    await deleteTask(USER, id);
    expect(doingTaskIds(USER).size).toBe(0);
  });
});
