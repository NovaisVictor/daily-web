import type { Connection } from '@/lib/vault/connections';
import type { JiraStatusCategory } from '@/lib/types';
import { jiraAuth, jiraRequest, startDateField, type JiraAuth } from '@/lib/integrations/jiraApi';

/** Where a suggested start date came from: the first move into an in-progress
 *  status, or, lacking one, the day the issue was created. */
export type StartDateSource = 'changelog' | 'created';

export type StartDateSuggestion =
  | { key: string; status: 'suggested'; date: string; source: StartDateSource }
  | { key: string; status: 'failed'; error: string };

export type StartDateOutcome = 'written' | 'refused';

export interface StartDateResult {
  key: string;
  outcome: StartDateOutcome;
  error?: string;
}

export const MAX_START_DATE_KEYS = 50;
const CONCURRENCY = 4;
const CHANGELOG_PAGE = 100;
const MAX_CHANGELOG_PAGES = 5;
const NOT_FOUND = 'issue não encontrada no Jira';

const CATEGORIES: readonly JiraStatusCategory[] = ['new', 'indeterminate', 'done'];

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function fail(what: string, detail: string): never {
  throw new Error(`resposta inesperada do Jira ${what}: ${detail}`);
}

function text(value: unknown, what: string, detail: string): string {
  if (typeof value !== 'string' || value.trim() === '') fail(what, `${detail} ausente`);
  return value;
}

const TIMESTAMP = /^(\d{4}-\d{2}-\d{2})T/;

/** The calendar day as Jira wrote it, in the timestamp's own offset: converting
 *  to UTC would move a late-evening change to the next day. */
function dayOf(value: unknown, what: string): string {
  const match = TIMESTAMP.exec(text(value, what, 'data'));
  if (!match || !isCalendarDate(match[1])) fail(what, `data inválida (${String(value)})`);
  return match[1];
}

export function isCalendarDate(value: unknown): value is string {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const [year, month, day] = value.split('-').map(Number);
  const date = new Date(Date.UTC(year, month - 1, day));
  return date.getUTCFullYear() === year && date.getUTCMonth() === month - 1 && date.getUTCDate() === day;
}

/** Status id → category. The changelog only carries status ids; the
 *  transitions are where the ids meet their categories. */
export function parseStatusCategories(data: unknown): Map<string, JiraStatusCategory> {
  const what = 'nas transições';
  if (!isRecord(data) || !Array.isArray(data.transitions)) fail(what, 'lista de transições ausente');
  const categories = new Map<string, JiraStatusCategory>();
  for (const raw of data.transitions) {
    if (!isRecord(raw) || !isRecord(raw.to)) fail(what, 'destino da transição ausente');
    const id = text(raw.to.id, what, 'id do status de destino');
    const key = isRecord(raw.to.statusCategory) ? raw.to.statusCategory.key : undefined;
    const category = CATEGORIES.find((c) => c === key);
    if (!category) fail(what, `categoria de status desconhecida (${String(key)})`);
    categories.set(id, category);
  }
  return categories;
}

export interface StatusChange {
  day: string;
  toStatusIds: string[];
}

export interface ChangelogPage {
  changes: StatusChange[];
  next: number | null;
}

export function parseChangelogPage(data: unknown): ChangelogPage {
  const what = 'no histórico';
  if (!isRecord(data) || !Array.isArray(data.values)) fail(what, 'lista de alterações ausente');
  if (typeof data.isLast !== 'boolean') fail(what, 'isLast ausente');
  if (typeof data.startAt !== 'number') fail(what, 'startAt ausente');
  const changes = data.values.map((history): StatusChange => {
    if (!isRecord(history) || !Array.isArray(history.items)) fail(what, 'itens da alteração ausentes');
    const toStatusIds = history.items.flatMap((item) => {
      if (!isRecord(item)) fail(what, 'item da alteração não é um objeto');
      if (item.fieldId !== 'status' && item.field !== 'status') return [];
      return [text(item.to, what, 'status de destino')];
    });
    return { day: dayOf(history.created, what), toStatusIds };
  });
  return { changes, next: data.isLast ? null : data.startAt + data.values.length };
}

/** The day of the earliest move into an in-progress status. A status the
 *  transitions do not know is not evidence either way, so it is skipped. */
export function firstInProgressDay(
  changes: StatusChange[],
  categories: Map<string, JiraStatusCategory>,
): string | null {
  const started = changes
    .filter((change) => change.toStatusIds.some((id) => categories.get(id) === 'indeterminate'))
    .map((change) => change.day)
    .sort();
  return started[0] ?? null;
}

export function parseCreatedDay(data: unknown): string {
  if (!isRecord(data) || !isRecord(data.fields)) fail('na issue', 'campos ausentes');
  return dayOf(data.fields.created, 'na issue');
}

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

async function suggestOne(auth: JiraAuth, key: string, limit: Limit): Promise<StartDateSuggestion> {
  const issue = encodeURIComponent(key);
  const get = (path: string) => limit(() => jiraRequest(auth, path, { method: 'GET', notFound: NOT_FOUND }));

  const readChangelog = async () => {
    const changes: StatusChange[] = [];
    let startAt: number | null = 0;
    for (let page = 0; page < MAX_CHANGELOG_PAGES && startAt !== null; page += 1) {
      const parsed = parseChangelogPage(
        await get(`/rest/api/3/issue/${issue}/changelog?startAt=${startAt}&maxResults=${CHANGELOG_PAGE}`),
      );
      changes.push(...parsed.changes);
      startAt = parsed.next;
    }
    return changes;
  };

  const [changes, categories] = await Promise.all([
    readChangelog(),
    get(`/rest/api/3/issue/${issue}/transitions`).then(parseStatusCategories),
  ]);
  const started = firstInProgressDay(changes, categories);
  if (started) return { key, status: 'suggested', date: started, source: 'changelog' };

  const created = parseCreatedDay(await get(`/rest/api/3/issue/${issue}?fields=created`));
  return { key, status: 'suggested', date: created, source: 'created' };
}

export async function suggestStartDates(conn: Connection, keys: string[]): Promise<StartDateSuggestion[]> {
  const auth = jiraAuth(conn);
  const limit = limiter(CONCURRENCY);
  return Promise.all(
    keys.map((key) =>
      suggestOne(auth, key, limit).catch(
        (err: unknown): StartDateSuggestion => ({
          key,
          status: 'failed',
          error: err instanceof Error ? err.message : String(err),
        }),
      ),
    ),
  );
}

/** One issue at a time, carrying on past a refusal: each story stands alone,
 *  and one Jira says no to should not keep the others without a date. The
 *  field lookup failing is the only thing that stops all of them. */
export async function writeStartDates(
  conn: Connection,
  items: { key: string; date: string }[],
): Promise<StartDateResult[]> {
  const auth = jiraAuth(conn);
  const field = await startDateField(auth);
  const results: StartDateResult[] = [];
  for (const { key, date } of items) {
    try {
      await jiraRequest(auth, `/rest/api/3/issue/${encodeURIComponent(key)}`, {
        method: 'PUT',
        body: { fields: { [field]: date } },
        notFound: NOT_FOUND,
      });
      results.push({ key, outcome: 'written' });
    } catch (err) {
      results.push({ key, outcome: 'refused', error: err instanceof Error ? err.message : String(err) });
    }
  }
  return results;
}
