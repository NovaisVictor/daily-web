import { count } from './format';

const DAY_MS = 86_400_000;

export const STALE_UPDATE_MS = 3 * DAY_MS;

export const STALE_REVIEW_MS = DAY_MS;

export function elapsedMs(iso: string, now: Date): number | null {
  if (!iso) return null;
  const time = new Date(iso).getTime();
  if (Number.isNaN(time)) return null;
  return Math.max(0, now.getTime() - time);
}

/** One rule for "parado" everywhere: the stale filter and the row badge agree. */
export function isStaleUpdate(updatedAt: string, now: Date): boolean {
  const idle = elapsedMs(updatedAt, now);
  return idle !== null && idle > STALE_UPDATE_MS;
}

export function formatDays(ms: number): string {
  return count(Math.floor(ms / DAY_MS), 'dia', 'dias');
}

export interface PullAge {
  opened: string;
  stalled: string | null;
}

export function pullAge(
  item: { createdAt: string; updatedAt: string },
  now: Date = new Date(),
): PullAge | null {
  const open = elapsedMs(item.createdAt, now);
  if (open === null) return null;
  const idle = elapsedMs(item.updatedAt, now);
  return {
    opened: open < DAY_MS ? 'aberto hoje' : `aberto há ${formatDays(open)}`,
    stalled: idle !== null && isStaleUpdate(item.updatedAt, now) ? `parado há ${formatDays(idle)}` : null,
  };
}
