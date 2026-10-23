import { describe, expect, it, beforeEach, afterEach } from 'vitest';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';

let dir: string;

beforeEach(async () => {
  dir = mkdtempSync(path.join(tmpdir(), 'daily-web-tasks-'));
  process.env.DAILY_WEB_DB_PATH = path.join(dir, 'test.db');
  const { getDb } = await import('@/lib/db');
  getDb();
});

afterEach(() => {
  rmSync(dir, { recursive: true, force: true });
});

const USER = 'user-1';
const OTHER = 'user-2';

describe('tarefas locais', () => {
  it('começa vazio', async () => {
    const { listTasks } = await import('@/lib/tasks/local');
    expect(listTasks(USER)).toEqual([]);
  });

  it('cria e lista uma tarefa', async () => {
    const { addTask, listTasks } = await import('@/lib/tasks/local');
    addTask(USER, 'Comprar pão');
    const [task] = listTasks(USER);
    expect(task.title).toBe('Comprar pão');
    expect(task.completed).toBe(false);
    expect(task.priority).toBe('normal');
    expect(task.subtasks).toEqual([]);
  });

  it('mantém a ordem de criação', async () => {
    const { addTask, listTasks } = await import('@/lib/tasks/local');
    addTask(USER, 'Primeira');
    addTask(USER, 'Segunda');
    expect(listTasks(USER).map((t) => t.title)).toEqual(['Primeira', 'Segunda']);
  });

  it('não mistura tarefas de usuários diferentes', async () => {
    const { addTask, listTasks } = await import('@/lib/tasks/local');
    addTask(USER, 'Minha');
    addTask(OTHER, 'Dele');
    expect(listTasks(USER).map((t) => t.title)).toEqual(['Minha']);
  });

  it('edita os campos informados e deixa o resto', async () => {
    const { addTask, editTask, listTasks } = await import('@/lib/tasks/local');
    const id = addTask(USER, 'Tarefa');
    editTask(USER, id, { due: '2026-09-01', priority: 'high' });

    const [task] = listTasks(USER);
    expect(task.due).toBe('2026-09-01');
    expect(task.priority).toBe('high');
    expect(task.title).toBe('Tarefa');
  });

  // parseDueInput answers 'none' for a date with no time, and the store kept
  // the word: the panel showed "24/10 none".
  it('treats "none" as clearing the due date, time and recurrence', async () => {
    const { addTask, editTask, listTasks } = await import('@/lib/tasks/local');
    const id = addTask(USER, 'Tarefa');
    editTask(USER, id, { due: '2026-09-01', time: '14:00', recur: 'weekly' });
    editTask(USER, id, { due: 'none', time: 'none', recur: 'none' });

    const [task] = listTasks(USER);
    expect(task).toMatchObject({ due: '', time: '', recur: '' });
  });

  it('keeps a date and drops a "none" time written before the fix', async () => {
    const { addTask, listTasks } = await import('@/lib/tasks/local');
    const { getDb } = await import('@/lib/db');
    const id = addTask(USER, 'Antiga');
    getDb().prepare("UPDATE tasks SET due = '2026-09-01', time = 'none' WHERE id = ?").run(id);

    const [task] = listTasks(USER);
    expect(task).toMatchObject({ due: '2026-09-01', time: '' });
  });

  it('não deixa um usuário editar a tarefa do outro', async () => {
    const { addTask, editTask, listTasks } = await import('@/lib/tasks/local');
    const id = addTask(USER, 'Minha');
    editTask(OTHER, id, { title: 'Invadida' });
    expect(listTasks(USER)[0].title).toBe('Minha');
  });

  it('não deixa um usuário apagar a tarefa do outro', async () => {
    const { addTask, deleteTask, listTasks } = await import('@/lib/tasks/local');
    const id = addTask(USER, 'Minha');
    deleteTask(OTHER, id);
    expect(listTasks(USER)).toHaveLength(1);
  });

  it('conclui e reabre', async () => {
    const { addTask, setCompleted, listTasks } = await import('@/lib/tasks/local');
    const id = addTask(USER, 'Tarefa');
    setCompleted(USER, id, true);
    expect(listTasks(USER)[0].completed).toBe(true);
    setCompleted(USER, id, false);
    expect(listTasks(USER)[0].completed).toBe(false);
  });

  it('apaga a tarefa junto com as subtarefas', async () => {
    const { addTask, addSubtask, deleteTask, listTasks } = await import('@/lib/tasks/local');
    const id = addTask(USER, 'Tarefa');
    addSubtask(USER, id, 'Etapa');
    deleteTask(USER, id);
    expect(listTasks(USER)).toEqual([]);
  });
});

describe('subtarefas locais', () => {
  it('acrescenta e marca', async () => {
    const { addTask, addSubtask, checkSubtask, listTasks } = await import('@/lib/tasks/local');
    const id = addTask(USER, 'Tarefa');
    addSubtask(USER, id, 'Etapa');

    const subtaskId = listTasks(USER)[0].subtasks[0].id;
    checkSubtask(USER, id, subtaskId, true);
    expect(listTasks(USER)[0].subtasks[0].completed).toBe(true);
  });

  it('mantém a ordem de criação', async () => {
    const { addTask, addSubtask, listTasks } = await import('@/lib/tasks/local');
    const id = addTask(USER, 'Tarefa');
    addSubtask(USER, id, 'Primeira');
    addSubtask(USER, id, 'Segunda');
    expect(listTasks(USER)[0].subtasks.map((s) => s.title)).toEqual(['Primeira', 'Segunda']);
  });

  it('não deixa acrescentar subtarefa na tarefa de outro usuário', async () => {
    const { addTask, addSubtask, listTasks } = await import('@/lib/tasks/local');
    const id = addTask(USER, 'Minha');
    addSubtask(OTHER, id, 'Invasora');
    expect(listTasks(USER)[0].subtasks).toEqual([]);
  });

  it('renomeia e apaga', async () => {
    const { addTask, addSubtask, editSubtask, deleteSubtask, listTasks } = await import(
      '@/lib/tasks/local'
    );
    const id = addTask(USER, 'Tarefa');
    addSubtask(USER, id, 'Etapa');
    const subtaskId = listTasks(USER)[0].subtasks[0].id;

    editSubtask(USER, id, subtaskId, 'Etapa nova');
    expect(listTasks(USER)[0].subtasks[0].title).toBe('Etapa nova');

    deleteSubtask(USER, id, subtaskId);
    expect(listTasks(USER)[0].subtasks).toEqual([]);
  });
});

describe('advanceDue', () => {
  it('avança um dia, uma semana e um mês', async () => {
    const { advanceDue } = await import('@/lib/tasks/local');
    expect(advanceDue('2026-08-25', 'daily')).toBe('2026-08-26');
    expect(advanceDue('2026-08-25', 'weekly')).toBe('2026-09-01');
    expect(advanceDue('2026-08-25', 'monthly')).toBe('2026-09-25');
  });

  it('atravessa a virada do mês', async () => {
    const { advanceDue } = await import('@/lib/tasks/local');
    expect(advanceDue('2026-08-31', 'daily')).toBe('2026-09-01');
  });

  it('devolve vazio quando não repete ou não tem data', async () => {
    const { advanceDue } = await import('@/lib/tasks/local');
    expect(advanceDue('2026-08-25', 'none')).toBe('');
    expect(advanceDue('', 'daily')).toBe('');
  });
});

describe('tarefa recorrente', () => {
  it('reaparece na próxima data em vez de ser concluída', async () => {
    const { addTask, editTask, setCompleted, listTasks } = await import('@/lib/tasks/local');
    const id = addTask(USER, 'Reunião semanal');
    editTask(USER, id, { due: '2026-08-25', recur: 'weekly' });
    setCompleted(USER, id, true);

    const [task] = listTasks(USER);
    expect(task.completed).toBe(false);
    expect(task.due).toBe('2026-09-01');
  });

  it('destrava as subtarefas no próximo ciclo', async () => {
    const { addTask, editTask, addSubtask, checkSubtask, setCompleted, listTasks } = await import(
      '@/lib/tasks/local'
    );
    const id = addTask(USER, 'Rotina');
    editTask(USER, id, { due: '2026-08-25', recur: 'daily' });
    addSubtask(USER, id, 'Etapa');
    const subtaskId = listTasks(USER)[0].subtasks[0].id;
    checkSubtask(USER, id, subtaskId, true);

    setCompleted(USER, id, true);
    expect(listTasks(USER)[0].subtasks[0].completed).toBe(false);
  });

  it('conclui de vez quando não tem data para avançar', async () => {
    const { addTask, editTask, setCompleted, listTasks } = await import('@/lib/tasks/local');
    const id = addTask(USER, 'Sem data');
    editTask(USER, id, { recur: 'weekly' });
    setCompleted(USER, id, true);
    expect(listTasks(USER)[0].completed).toBe(true);
  });
});
