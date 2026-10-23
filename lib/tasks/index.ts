import { listConnections } from '@/lib/vault/connections';
import type { Connection } from '@/lib/vault/connections';
import type { TodoTask } from '@/lib/types';
import type { EditTaskInput } from './types';
import * as local from './local';
import * as mstodo from '@/lib/cli/mstodo';
import { clearBoardStatus, markDoing, withBoardOverlay } from './boardStatus';
import { clearBoardStyle, setBoardStyle, type BoardStyle, type BoardStylePatch } from './boardStyle';

export type { EditTaskInput, Recur } from './types';
export type { BoardStyle, BoardStylePatch } from './boardStyle';

/** Sem conexão cadastrada as tarefas ficam no banco da app. É o que faz o
 *  painel funcionar no primeiro login, antes de configurar coisa alguma. */
function taskConnection(userId: string): Connection | null {
  return listConnections(userId, 'tasks')[0] ?? null;
}

function usesMstodo(userId: string): boolean {
  return taskConnection(userId)?.values.provider === 'mstodo';
}

function mstodoEnv(userId: string): Record<string, string> {
  const conn = taskConnection(userId);
  const env: Record<string, string> = {};
  if (conn?.values.clientId) env.DAILY_TUI_TODO_CLIENT_ID = conn.values.clientId;
  if (conn?.values.list) env.DAILY_TUI_TODO_LIST = conn.values.list;
  return env;
}

export async function fetchTasks(userId: string): Promise<TodoTask[]> {
  const tasks = usesMstodo(userId)
    ? await mstodo.fetchTasks(mstodoEnv(userId))
    : local.listTasks(userId);
  return withBoardOverlay(userId, tasks);
}

export async function addTask(userId: string, title: string): Promise<string> {
  if (usesMstodo(userId)) return mstodo.addTask(mstodoEnv(userId), title);
  return local.addTask(userId, title);
}

export async function setCompleted(
  userId: string,
  id: string,
  completed: boolean,
): Promise<void> {
  if (usesMstodo(userId)) {
    const env = mstodoEnv(userId);
    if (completed) await mstodo.completeTask(env, id);
    else await mstodo.reopenTask(env, id);
  } else {
    local.setCompleted(userId, id, completed);
  }
  // Completing ends "Fazendo". Cleared only after the provider accepted, so a
  // failed completion leaves the card where it was. A recurring task rolls
  // over to its next date and comes back as "A fazer", not still in progress.
  if (completed) clearBoardStatus(userId, id);
}

/** Moves a task between "A fazer" and "Fazendo". "Feito" is not a status
 *  here: it is `setCompleted`, so the provider stays the source of truth. */
export function setDoing(userId: string, id: string, doing: boolean): void {
  if (doing) markDoing(userId, id);
  else clearBoardStatus(userId, id);
}

/** The note's paper and pin colour. Like "Fazendo" it lives beside the
 *  provider's task, so it never costs a call to Microsoft To Do. */
export function setTaskStyle(userId: string, id: string, patch: BoardStylePatch): BoardStyle {
  return setBoardStyle(userId, id, patch);
}

export async function editTask(
  userId: string,
  id: string,
  input: EditTaskInput,
): Promise<void> {
  if (usesMstodo(userId)) {
    await mstodo.editTask(mstodoEnv(userId), id, input);
    return;
  }
  local.editTask(userId, id, input);
}

export async function deleteTask(userId: string, id: string): Promise<void> {
  if (usesMstodo(userId)) {
    await mstodo.deleteTask(mstodoEnv(userId), id);
  } else {
    local.deleteTask(userId, id);
  }
  clearBoardStatus(userId, id);
  clearBoardStyle(userId, id);
}

export async function addSubtask(userId: string, taskId: string, title: string): Promise<void> {
  if (usesMstodo(userId)) {
    await mstodo.addSubtask(mstodoEnv(userId), taskId, title);
    return;
  }
  local.addSubtask(userId, taskId, title);
}

export async function editSubtask(
  userId: string,
  taskId: string,
  itemId: string,
  title: string,
): Promise<void> {
  if (usesMstodo(userId)) {
    await mstodo.editSubtask(mstodoEnv(userId), taskId, itemId, title);
    return;
  }
  local.editSubtask(userId, taskId, itemId, title);
}

export async function deleteSubtask(
  userId: string,
  taskId: string,
  itemId: string,
): Promise<void> {
  if (usesMstodo(userId)) {
    await mstodo.deleteSubtask(mstodoEnv(userId), taskId, itemId);
    return;
  }
  local.deleteSubtask(userId, taskId, itemId);
}

export async function checkSubtask(
  userId: string,
  taskId: string,
  itemId: string,
  checked: boolean,
): Promise<void> {
  if (usesMstodo(userId)) {
    await mstodo.checkSubtask(mstodoEnv(userId), taskId, itemId, checked);
    return;
  }
  local.checkSubtask(userId, taskId, itemId, checked);
}
