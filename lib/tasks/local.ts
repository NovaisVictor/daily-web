import { randomUUID } from 'node:crypto';
import { getDb } from '@/lib/db';
import type { ProviderTask, SubTask, TaskPriority } from '@/lib/types';
import type { EditTaskInput, Recur } from './types';

interface TaskRow {
  id: string;
  title: string;
  completed: number;
  due: string;
  time: string;
  priority: string;
  recur: string;
  notes: string;
}

interface SubtaskRow {
  id: string;
  task_id: string;
  title: string;
  completed: number;
}

function nextPosition(table: 'tasks' | 'subtasks', column: string, value: string): number {
  const row = getDb()
    .prepare(`SELECT COALESCE(MAX(position), 0) + 1 AS next FROM ${table} WHERE ${column} = ?`)
    .get(value) as { next: number };
  return row.next;
}

export function listTasks(userId: string): ProviderTask[] {
  const db = getDb();
  const rows = db
    .prepare('SELECT * FROM tasks WHERE user_id = ? ORDER BY position')
    .all(userId) as TaskRow[];
  if (rows.length === 0) return [];

  const placeholders = rows.map(() => '?').join(', ');
  const subtasks = db
    .prepare(`SELECT * FROM subtasks WHERE task_id IN (${placeholders}) ORDER BY position`)
    .all(...rows.map((r) => r.id)) as SubtaskRow[];

  const byTask = new Map<string, SubTask[]>();
  for (const sub of subtasks) {
    const list = byTask.get(sub.task_id) ?? [];
    list.push({ id: sub.id, title: sub.title, completed: sub.completed === 1 });
    byTask.set(sub.task_id, list);
  }

  return rows.map((row) => ({
    id: row.id,
    title: row.title,
    completed: row.completed === 1,
    due: cleared(row.due),
    time: cleared(row.time),
    priority: row.priority as TaskPriority,
    recur: cleared(row.recur),
    notes: row.notes,
    subtasks: byTask.get(row.id) ?? [],
  }));
}

export function addTask(userId: string, title: string): string {
  const id = randomUUID();
  getDb()
    .prepare(
      `INSERT INTO tasks (id, user_id, title, position, created_at)
       VALUES (?, ?, ?, ?, ?)`,
    )
    .run(id, userId, title, nextPosition('tasks', 'user_id', userId), new Date().toISOString());
  return id;
}

/** Avança a data no intervalo pedido. Uma tarefa que repete não "termina" ao
 *  ser concluída: ela volta na próxima data. */
export function advanceDue(due: string, recur: Recur): string {
  if (!due || recur === 'none' || !recur) return '';
  const [year, month, day] = due.split('-').map(Number);
  if (!year || !month || !day) return '';
  const next = new Date(year, month - 1, day);
  if (recur === 'daily') next.setDate(next.getDate() + 1);
  else if (recur === 'weekly') next.setDate(next.getDate() + 7);
  else if (recur === 'monthly') next.setMonth(next.getMonth() + 1);
  else return '';

  const pad = (n: number) => String(n).padStart(2, '0');
  return `${next.getFullYear()}-${pad(next.getMonth() + 1)}-${pad(next.getDate())}`;
}

function ownedTask(userId: string, id: string): TaskRow | null {
  const row = getDb()
    .prepare('SELECT * FROM tasks WHERE user_id = ? AND id = ?')
    .get(userId, id) as TaskRow | undefined;
  return row ?? null;
}

export function setCompleted(userId: string, id: string, completed: boolean): void {
  const task = ownedTask(userId, id);
  if (!task) return;

  const rolled = completed ? advanceDue(task.due, task.recur as Recur) : '';
  if (rolled) {
    // Uma recorrente concluída reaparece na data seguinte, com as subtarefas
    // destravadas — que é o comportamento de quem usa "toda segunda".
    getDb().prepare('UPDATE tasks SET due = ?, completed = 0 WHERE id = ?').run(rolled, id);
    getDb().prepare('UPDATE subtasks SET completed = 0 WHERE task_id = ?').run(id);
    return;
  }
  getDb().prepare('UPDATE tasks SET completed = ? WHERE id = ?').run(completed ? 1 : 0, id);
}

const EDITABLE: Record<keyof EditTaskInput, string> = {
  title: 'title',
  due: 'due',
  time: 'time',
  recur: 'recur',
  priority: 'priority',
};

/**
 * 'none' is how callers say "clear this field": it is the mstodo CLI's
 * convention, and parseDueInput returns it for a date with no time. This
 * store used to translate it for recur only, so due and time kept the literal
 * word, the panel showed "24/10 none", and a cleared due sorted as a date
 * after every real one. Reads go through it too, for rows written before.
 */
function cleared(value: string): string {
  return value === 'none' ? '' : value;
}

export function editTask(userId: string, id: string, input: EditTaskInput): void {
  const assignments: string[] = [];
  const values: string[] = [];
  for (const [field, column] of Object.entries(EDITABLE)) {
    const value = input[field as keyof EditTaskInput];
    if (value === undefined) continue;
    assignments.push(`${column} = ?`);
    values.push(cleared(value));
  }
  if (assignments.length === 0) return;
  getDb()
    .prepare(`UPDATE tasks SET ${assignments.join(', ')} WHERE user_id = ? AND id = ?`)
    .run(...values, userId, id);
}

export function deleteTask(userId: string, id: string): void {
  const db = getDb();
  db.transaction(() => {
    const changes = db.prepare('DELETE FROM tasks WHERE user_id = ? AND id = ?').run(userId, id)
      .changes;
    if (changes > 0) db.prepare('DELETE FROM subtasks WHERE task_id = ?').run(id);
  })();
}

export function addSubtask(userId: string, taskId: string, title: string): void {
  if (!ownedTask(userId, taskId)) return;
  getDb()
    .prepare('INSERT INTO subtasks (id, task_id, title, position) VALUES (?, ?, ?, ?)')
    .run(randomUUID(), taskId, title, nextPosition('subtasks', 'task_id', taskId));
}

export function editSubtask(userId: string, taskId: string, itemId: string, title: string): void {
  if (!ownedTask(userId, taskId)) return;
  getDb().prepare('UPDATE subtasks SET title = ? WHERE id = ? AND task_id = ?').run(title, itemId, taskId);
}

export function deleteSubtask(userId: string, taskId: string, itemId: string): void {
  if (!ownedTask(userId, taskId)) return;
  getDb().prepare('DELETE FROM subtasks WHERE id = ? AND task_id = ?').run(itemId, taskId);
}

export function checkSubtask(
  userId: string,
  taskId: string,
  itemId: string,
  checked: boolean,
): void {
  if (!ownedTask(userId, taskId)) return;
  getDb()
    .prepare('UPDATE subtasks SET completed = ? WHERE id = ? AND task_id = ?')
    .run(checked ? 1 : 0, itemId, taskId);
}
