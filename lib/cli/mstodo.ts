import { runCli } from './run';
import { parseTasks } from '@/lib/parsers/mstodo';
import type { ProviderTask } from '@/lib/types';
import type { EditTaskInput } from '@/lib/tasks/types';

// Provedor opcional de tarefas. Continua sendo uma CLI da máquina porque o
// Microsoft To Do só fala OAuth: quem já usa a CLI mantém a sincronia com o
// celular, e quem não tem cai no provedor local, que é o padrão.
type Env = Record<string, string>;

export async function fetchTasks(env: Env): Promise<ProviderTask[]> {
  const { stdout } = await runCli('mstodo', ['list'], { env });
  return parseTasks(stdout);
}

export function buildEditArgs(id: string, input: EditTaskInput): string[] {
  const args = [id];
  if (input.title !== undefined) args.push('--title', input.title);
  if (input.due !== undefined) args.push('--due', input.due);
  if (input.time !== undefined) args.push('--time', input.time);
  if (input.recur !== undefined) args.push('--recur', input.recur);
  if (input.priority !== undefined) args.push('--priority', input.priority);
  return args;
}

export async function addTask(env: Env, title: string): Promise<string> {
  const { stdout } = await runCli('mstodo', ['add', title], { env });
  return stdout.trim();
}

export async function completeTask(env: Env, id: string): Promise<void> {
  await runCli('mstodo', ['complete', id], { env });
}

export async function reopenTask(env: Env, id: string): Promise<void> {
  await runCli('mstodo', ['reopen', id], { env });
}

export async function editTask(env: Env, id: string, input: EditTaskInput): Promise<void> {
  await runCli('mstodo', ['edit', ...buildEditArgs(id, input)], { env });
}

export async function deleteTask(env: Env, id: string): Promise<void> {
  await runCli('mstodo', ['delete', id], { env });
}

export async function addSubtask(env: Env, taskId: string, title: string): Promise<void> {
  await runCli('mstodo', ['subtask', taskId, title], { env });
}

export async function editSubtask(
  env: Env,
  taskId: string,
  itemId: string,
  title: string,
): Promise<void> {
  await runCli('mstodo', ['subtask-edit', taskId, itemId, title], { env });
}

export async function deleteSubtask(env: Env, taskId: string, itemId: string): Promise<void> {
  await runCli('mstodo', ['subtask-delete', taskId, itemId], { env });
}

export async function checkSubtask(
  env: Env,
  taskId: string,
  itemId: string,
  checked: boolean,
): Promise<void> {
  await runCli('mstodo', [checked ? 'check' : 'uncheck', taskId, itemId], { env });
}

/** A CLI só existe na máquina de quem a instalou; a tela de configuração usa
 *  isto para não oferecer um provedor que vai falhar na primeira leitura. */
export async function isAvailable(): Promise<boolean> {
  try {
    await runCli('mstodo', ['--help'], { timeoutMs: 5_000 });
    return true;
  } catch (err) {
    return !/comando não encontrado/.test(err instanceof Error ? err.message : '');
  }
}
