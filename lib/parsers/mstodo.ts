import type { ProviderTask, SubTask, TaskPriority } from '@/lib/types';

interface RawSubtask {
  id: string;
  title: string;
  completed: boolean;
}

interface RawTask {
  id: string;
  title: string;
  completed: boolean;
  due?: string;
  priority?: string;
  time?: string;
  recur?: string;
  notes?: string;
  subtasks?: RawSubtask[];
}

const VALID_PRIORITIES: readonly string[] = ['low', 'normal', 'high'];

function toPriority(value: string | undefined): TaskPriority {
  return VALID_PRIORITIES.includes(value ?? '') ? (value as TaskPriority) : 'normal';
}

export function parseTasks(json: string): ProviderTask[] {
  const raw: RawTask[] = JSON.parse(json);
  return raw.map((task) => ({
    id: task.id,
    title: task.title,
    completed: task.completed,
    due: task.due ?? '',
    priority: toPriority(task.priority),
    time: task.time ?? '',
    recur: task.recur === 'absoluteMonthly' ? 'monthly' : task.recur ?? '',
    notes: task.notes ?? '',
    subtasks: (task.subtasks ?? []).map(
      (s): SubTask => ({ id: s.id, title: s.title, completed: s.completed }),
    ),
  }));
}
