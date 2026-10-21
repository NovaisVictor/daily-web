import type { Connection } from '@/lib/vault/connections';
import {
  jiraAuth,
  setStartDate,
  startDateField,
  suggestStartDate,
  type StartDateBasis,
} from '@/lib/integrations/jiraApi';

export type StartDateSuggestion =
  | { key: string; status: 'suggested'; date: string; basis: StartDateBasis }
  | { key: string; status: 'failed'; error: string };

export type StartDateOutcome = 'written' | 'refused';

export interface StartDateResult {
  key: string;
  outcome: StartDateOutcome;
  error?: string;
}

// Each suggestion runs two reads at once before the changelog, so two issues
// at a time keep at most four requests in flight.
const CONCURRENCY = 2;

const NO_HISTORY = 'o histórico não diz quando começou';

type Limit = <T>(task: () => Promise<T>) => Promise<T>;

function limiter(max: number): Limit {
  let active = 0;
  const waiting: (() => void)[] = [];
  return async (task) => {
    if (active >= max) await new Promise<void>((resolve) => waiting.push(resolve));
    active += 1;
    try {
      return await task();
    } finally {
      active -= 1;
      waiting.shift()?.();
    }
  };
}

const message = (err: unknown) => (err instanceof Error ? err.message : String(err));

export async function suggestStartDates(conn: Connection, keys: string[]): Promise<StartDateSuggestion[]> {
  const limit = limiter(CONCURRENCY);
  return Promise.all(
    keys.map(async (key): Promise<StartDateSuggestion> => {
      try {
        const suggestion = await limit(() => suggestStartDate(conn, key));
        return suggestion
          ? { key, status: 'suggested', date: suggestion.date, basis: suggestion.basis }
          : { key, status: 'failed', error: NO_HISTORY };
      } catch (err) {
        return { key, status: 'failed', error: message(err) };
      }
    }),
  );
}

/** One issue at a time, carrying on past a refusal: each story stands alone,
 *  and one Jira says no to should not keep the others without a date. The
 *  field lookup failing is the only thing that stops all of them. */
export async function writeStartDates(
  conn: Connection,
  items: { key: string; date: string }[],
): Promise<StartDateResult[]> {
  await startDateField(jiraAuth(conn));
  const results: StartDateResult[] = [];
  for (const { key, date } of items) {
    try {
      await setStartDate(conn, key, date);
      results.push({ key, outcome: 'written' });
    } catch (err) {
      results.push({ key, outcome: 'refused', error: message(err) });
    }
  }
  return results;
}
