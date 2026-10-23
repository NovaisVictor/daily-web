import type { TaskPriority, TodoTask } from '@/lib/types';

export type TaskGroupKey = 'overdue' | 'today' | 'week' | 'month' | 'later' | 'noDate';

const GROUP_LABELS: Record<TaskGroupKey, string> = {
  overdue: 'ATRASADAS',
  today: 'HOJE',
  week: 'ESTA SEMANA',
  month: 'ESTE MÊS',
  later: 'DEPOIS',
  noDate: 'SEM DATA',
};

const GROUP_ORDER: TaskGroupKey[] = ['overdue', 'today', 'week', 'month', 'later', 'noDate'];

function addDays(iso: string, days: number): string {
  const d = new Date(`${iso}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + days);
  return d.toISOString().slice(0, 10);
}

function toLocalDateString(date: Date): string {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

function groupOf(due: string, todayIso: string, weekEndIso: string, monthEndIso: string): TaskGroupKey {
  if (due === '') return 'noDate';
  if (due < todayIso) return 'overdue';
  if (due === todayIso) return 'today';
  if (due <= weekEndIso) return 'week';
  if (due <= monthEndIso) return 'month';
  return 'later';
}

const PRIORITY_RANK: Record<TaskPriority, number> = { high: 0, normal: 1, low: 2 };

export interface TaskGroupResult {
  key: TaskGroupKey;
  label: string;
  tasks: TodoTask[];
}

export function groupTasksByDueWindow(tasks: TodoTask[], today: Date = new Date()): TaskGroupResult[] {
  const todayIso = toLocalDateString(today);
  const weekEndIso = addDays(todayIso, 6);
  const monthEndIso = addDays(todayIso, 29);

  const buckets = new Map<TaskGroupKey, TodoTask[]>();
  for (const t of tasks) {
    const key = groupOf(t.due, todayIso, weekEndIso, monthEndIso);
    const list = buckets.get(key) ?? [];
    list.push(t);
    buckets.set(key, list);
  }

  for (const list of buckets.values()) {
    list.sort((a, b) => {
      if (a.completed !== b.completed) return a.completed ? 1 : -1;
      if (a.due !== b.due) return a.due < b.due ? -1 : 1;
      return PRIORITY_RANK[a.priority] - PRIORITY_RANK[b.priority];
    });
  }

  return GROUP_ORDER.filter((key) => buckets.has(key)).map((key) => ({
    key,
    label: GROUP_LABELS[key],
    tasks: buckets.get(key)!,
  }));
}

/** Late and still open. Same day boundary as the "ATRASADAS" group, so a row
 *  never says "atrasada" under a heading that disagrees. A finished task is
 *  not late any more, whatever its date says. */
export function isOverdue(task: TodoTask, today: Date = new Date()): boolean {
  return !task.completed && task.due !== '' && task.due < toLocalDateString(today);
}
