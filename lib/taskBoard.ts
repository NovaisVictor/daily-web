import type { NotePaper, PinColor, TodoTask } from '@/lib/types';

export type { NotePaper, PinColor };

export type BoardColumn = 'todo' | 'doing' | 'done';

export const BOARD_COLUMNS: { key: BoardColumn; label: string }[] = [
  { key: 'todo', label: 'A fazer' },
  { key: 'doing', label: 'Fazendo' },
  { key: 'done', label: 'Feito' },
];

export const TASK_BOARD_DRAG_TYPE = 'application/x-daily-web-task';

export function columnLabel(column: BoardColumn): string {
  return BOARD_COLUMNS.find((c) => c.key === column)?.label ?? column;
}

/** Completed wins over "doing": the provider's flag is the source of truth,
 *  and the overlay may be stale when the task was completed elsewhere. */
export function columnOf(task: TodoTask): BoardColumn {
  if (task.completed) return 'done';
  return task.doing ? 'doing' : 'todo';
}

/** Keeps the order the tasks came in, which is the provider's own order. */
export function groupByColumn(tasks: TodoTask[]): Record<BoardColumn, TodoTask[]> {
  const columns: Record<BoardColumn, TodoTask[]> = { todo: [], doing: [], done: [] };
  for (const task of tasks) columns[columnOf(task)].push(task);
  return columns;
}

/** The columns either side of this one, for the keyboard move buttons. */
export function neighbours(column: BoardColumn): { previous: BoardColumn | null; next: BoardColumn | null } {
  const index = BOARD_COLUMNS.findIndex((c) => c.key === column);
  return {
    previous: index > 0 ? BOARD_COLUMNS[index - 1].key : null,
    next: index < BOARD_COLUMNS.length - 1 ? BOARD_COLUMNS[index + 1].key : null,
  };
}

/**
 * The requests a move needs, in order. "Feito" is the provider's completion,
 * so leaving it reopens the task first; the status write that follows also
 * clears a "doing" row that may have outlived a completion made elsewhere.
 */
export type MoveStep = { kind: 'complete'; completed: boolean } | { kind: 'status'; status: 'todo' | 'doing' };

export function planMove(task: TodoTask, to: BoardColumn): MoveStep[] {
  const from = columnOf(task);
  if (from === to) return [];
  if (to === 'done') return [{ kind: 'complete', completed: true }];
  const steps: MoveStep[] = [];
  if (from === 'done') steps.push({ kind: 'complete', completed: false });
  steps.push({ kind: 'status', status: to });
  return steps;
}

/** A stable number per task, so a note keeps its look across refreshes: a
 *  random one would make the whole board shuffle on every poll. */
function idHash(id: string): number {
  let hash = 0;
  for (let i = 0; i < id.length; i += 1) hash = (hash * 31 + id.charCodeAt(i)) | 0;
  return Math.abs(hash);
}

/** A small tilt, the same for a task every time it is drawn. Range is -2deg to 2deg. */
export function noteTilt(id: string): number {
  const steps = idHash(id) % 41;
  return Math.round((steps / 10 - 2) * 10) / 10;
}

/** In the order the colour picker shows them: the classic yellow first, the
 *  priority colours next, then the neutral ones. */
export const NOTE_PAPERS: NotePaper[] = ['yellow', 'pink', 'blue', 'green', 'white', 'grey'];

export const PIN_COLORS: PinColor[] = ['red', 'blue', 'yellow', 'green'];

export const PAPER_LABEL: Record<NotePaper, string> = {
  yellow: 'amarelo',
  pink: 'rosa',
  blue: 'azul',
  green: 'verde',
  white: 'branco',
  grey: 'cinza',
};

export const PIN_LABEL: Record<PinColor, string> = {
  red: 'vermelho',
  blue: 'azul',
  yellow: 'amarelo',
  green: 'verde',
};

/** Finished notes go green; open ones take their colour from priority, with
 *  the classic yellow for the common case. Priority is also written on the
 *  note, so the colour is never the only signal. */
export function derivedPaper(task: Pick<TodoTask, 'completed' | 'priority'>): NotePaper {
  if (task.completed) return 'green';
  if (task.priority === 'high') return 'pink';
  if (task.priority === 'low') return 'blue';
  return 'yellow';
}

/** A chosen paper wins even over the green of a finished note: the "Feito"
 *  column and the struck-through title already say it is done, and forcing
 *  green would erase the colour exactly where notes pile up. */
export function notePaper(task: TodoTask): NotePaper {
  return task.paper ?? derivedPaper(task);
}

/** The pins a paper colour would swallow: a yellow pin vanishes on a yellow
 *  note, red reads as a smudge on pink, and yellow is too close in lightness
 *  to white and grey to stand out from them. */
export const CLASHES: Record<NotePaper, PinColor[]> = {
  yellow: ['yellow'],
  pink: ['red'],
  blue: ['blue'],
  green: ['green'],
  white: ['yellow'],
  grey: ['yellow'],
};

export function pinClashes(pin: PinColor, paper: NotePaper): boolean {
  return CLASHES[paper].includes(pin);
}

/** A pin colour per note, varied across the board like a real one, but never
 *  the colour the note's paper would hide. The paper is the one on screen, so
 *  a chosen paper moves the automatic pin off it too. A chosen pin is kept
 *  even when it clashes: the picker warns, and the person decides. */
export function notePin(task: TodoTask): PinColor {
  if (task.pin) return task.pin;
  const paper = notePaper(task);
  const options = PIN_COLORS.filter((c) => !pinClashes(c, paper));
  // A different stride from the tilt, so pin and angle do not move together.
  return options[Math.floor(idHash(task.id) / 7) % options.length];
}

/** About one note in three has its bottom corner peeling off the board. */
export function noteCurls(id: string): boolean {
  return Math.floor(idHash(id) / 3) % 3 === 0;
}
