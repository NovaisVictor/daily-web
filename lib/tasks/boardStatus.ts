import { getDb } from '@/lib/db';
import type { ProviderTask, TodoTask } from '@/lib/types';
import { boardStyles } from './boardStyle';

/** Ids of the tasks this user marked "Fazendo" on the board. */
export function doingTaskIds(userId: string): Set<string> {
  const rows = getDb()
    .prepare("SELECT task_id FROM task_board_status WHERE user_id = ? AND status = 'doing'")
    .all(userId) as { task_id: string }[];
  return new Set(rows.map((r) => r.task_id));
}

export function markDoing(userId: string, taskId: string): void {
  getDb()
    .prepare(
      `INSERT INTO task_board_status (user_id, task_id, status, updated_at)
       VALUES (?, ?, 'doing', ?)
       ON CONFLICT (user_id, task_id)
       DO UPDATE SET status = excluded.status, updated_at = excluded.updated_at`,
    )
    .run(userId, taskId, new Date().toISOString());
}

export function clearBoardStatus(userId: string, taskId: string): void {
  getDb()
    .prepare('DELETE FROM task_board_status WHERE user_id = ? AND task_id = ?')
    .run(userId, taskId);
}

/**
 * Everything the board keeps beside the provider's task: "Fazendo" and the
 * note's colours. A completed task is "Feito" whatever the overlay says. The
 * row can outlive the completion when the task was completed somewhere this
 * app does not see — on the phone, in Microsoft To Do — so it is ignored here
 * rather than trusted. The colours are not tied to the column and stay.
 */
export function withBoardOverlay(userId: string, tasks: ProviderTask[]): TodoTask[] {
  if (tasks.length === 0) return [];
  const doing = doingTaskIds(userId);
  const styles = boardStyles(userId);
  return tasks.map((task) => {
    const style = styles.get(task.id);
    return {
      ...task,
      doing: !task.completed && doing.has(task.id),
      paper: style?.paper ?? null,
      pin: style?.pin ?? null,
    };
  });
}
