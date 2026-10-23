import type { Connection } from '@/lib/vault/connections';
import { ProviderRefusal } from '@/lib/integrations/refusal';
import { jiraAuth, jiraRequest } from '@/lib/integrations/jiraApi';
import { isJiraAccountId } from '@/lib/jiraAccount';
import { isJiraKey } from '@/lib/jiraKey';
import { DESCRIPTION_MAX, SUMMARY_MAX } from '@/lib/jiraLimits';
import { adfDocument, fail as failIn, isCalendarDate, isRecord, NOT_FOUND, requiredText } from '@/lib/integrations/jira/parse';

export interface JiraPriority {
  id: string;
  name: string;
}

export type EditChange =
  | { change: 'due'; dueDate: string | null }
  | { change: 'priority'; priorityId: string }
  | { change: 'assign-self' };

export interface NewStory {
  summary: string;
  description: string | null;
}

const STORY_TYPE_NAMES = ['história', 'story'];
const EPIC_LEVEL = 1;
const STORY_LEVEL = 0;

/** A request the panel can refuse before asking Jira: answered with 400. */
export class InvalidEdit extends ProviderRefusal {}
export class StoryTypeUnavailable extends ProviderRefusal {}

function fail(detail: string): never {
  failIn(null, detail);
}

const text = (value: unknown, what: string) => requiredText(value, null, what);

function numericId(value: unknown, what: string): string {
  const id = text(value, what);
  if (!/^\d+$/.test(id)) fail(`${what} inválido (${id})`);
  return id;
}

export function parseEditChange(body: unknown): EditChange | null {
  if (!isRecord(body)) return null;
  switch (body.change) {
    case 'due':
      if (body.dueDate === null) return { change: 'due', dueDate: null };
      return isCalendarDate(body.dueDate) ? { change: 'due', dueDate: body.dueDate } : null;
    case 'priority':
      return typeof body.priorityId === 'string' && /^\d{1,10}$/.test(body.priorityId)
        ? { change: 'priority', priorityId: body.priorityId }
        : null;
    case 'assign-self':
      return { change: 'assign-self' };
    default:
      return null;
  }
}

export function parseNewStory(body: unknown): NewStory | null {
  if (!isRecord(body)) return null;
  if (typeof body.summary !== 'string') return null;
  const summary = body.summary.trim();
  if (summary.length === 0 || summary.length > SUMMARY_MAX) return null;
  if (body.description === undefined || body.description === null) return { summary, description: null };
  if (typeof body.description !== 'string') return null;
  const description = body.description.trim();
  if (description.length > DESCRIPTION_MAX) return null;
  return { summary, description: description === '' ? null : description };
}

function parsePriority(raw: unknown): JiraPriority {
  if (!isRecord(raw)) fail('prioridade não é um objeto');
  const id = numericId(raw.id, 'id da prioridade');
  return { id, name: text(raw.name, `nome da prioridade ${id}`) };
}

export function parsePriorities(data: unknown): JiraPriority[] {
  if (!Array.isArray(data)) fail('lista de prioridades ausente');
  return data.map(parsePriority);
}

export function parseIssuePriority(data: unknown): JiraPriority | null {
  if (!isRecord(data) || !isRecord(data.fields)) fail('campos da issue ausentes');
  const { priority } = data.fields;
  return priority === null || priority === undefined ? null : parsePriority(priority);
}

export function parseMyself(data: unknown): string {
  if (!isRecord(data) || !isJiraAccountId(data.accountId)) fail('conta de quem está logado');
  return data.accountId;
}

export interface EpicInfo {
  project: string;
  hierarchyLevel: number;
}

export function parseEpicInfo(data: unknown): EpicInfo {
  if (!isRecord(data) || !isRecord(data.fields)) fail('campos da issue ausentes');
  const { project, issuetype } = data.fields;
  if (!isRecord(project) || typeof project.key !== 'string' || !/^[A-Z][A-Z0-9_]*$/.test(project.key)) {
    fail('projeto da issue');
  }
  if (!isRecord(issuetype) || typeof issuetype.hierarchyLevel !== 'number') fail('tipo da issue');
  return { project: project.key, hierarchyLevel: issuetype.hierarchyLevel };
}

/** Bug sits at the same level as a story, so the level alone does not pick it. */
export function pickStoryTypeId(data: unknown): string {
  if (!isRecord(data) || !Array.isArray(data.issueTypes)) fail('tipos de issue do projeto ausentes');
  const found = data.issueTypes.find((raw) => {
    if (!isRecord(raw)) fail('tipo de issue não é um objeto');
    if (typeof raw.hierarchyLevel !== 'number' || typeof raw.subtask !== 'boolean') {
      fail(`nível do tipo ${String(raw.id)}`);
    }
    const names = [raw.name, raw.untranslatedName]
      .filter((n): n is string => typeof n === 'string')
      .map((n) => n.trim().toLowerCase());
    return (
      raw.hierarchyLevel === STORY_LEVEL &&
      raw.subtask === false &&
      names.some((n) => STORY_TYPE_NAMES.includes(n))
    );
  });
  if (!found) throw new StoryTypeUnavailable('o projeto não tem um tipo História (ou Story) para criar no épico');
  return numericId((found as Record<string, unknown>).id, 'id do tipo História');
}

export function parseCreatedKey(data: unknown): string {
  if (!isRecord(data) || !isJiraKey(data.key)) fail('chave da issue criada');
  return String(data.key);
}

function isTimeout(err: unknown): boolean {
  const name = typeof err === 'object' && err !== null && 'name' in err ? err.name : undefined;
  return name === 'TimeoutError' || name === 'AbortError';
}

function issuePath(key: string): string {
  return `/rest/api/3/issue/${encodeURIComponent(key)}`;
}

export async function fetchPriorityOptions(
  conn: Connection,
  key: string,
): Promise<{ priorities: JiraPriority[]; current: JiraPriority | null }> {
  const auth = jiraAuth(conn);
  const [list, issue] = await Promise.all([
    jiraRequest(auth, '/rest/api/3/priority', { method: 'GET' }),
    jiraRequest(auth, `${issuePath(key)}?fields=priority`, { method: 'GET', notFound: NOT_FOUND }),
  ]);
  return { priorities: parsePriorities(list), current: parseIssuePriority(issue) };
}

export async function applyEdit(conn: Connection, key: string, edit: EditChange): Promise<void> {
  const auth = jiraAuth(conn);
  switch (edit.change) {
    case 'due':
      await jiraRequest(auth, issuePath(key), {
        method: 'PUT',
        body: { fields: { duedate: edit.dueDate } },
        notFound: NOT_FOUND,
      });
      return;
    case 'priority': {
      const priorities = parsePriorities(await jiraRequest(auth, '/rest/api/3/priority', { method: 'GET' }));
      if (!priorities.some((p) => p.id === edit.priorityId)) throw new InvalidEdit('prioridade desconhecida');
      await jiraRequest(auth, issuePath(key), {
        method: 'PUT',
        body: { fields: { priority: { id: edit.priorityId } } },
        notFound: NOT_FOUND,
      });
      return;
    }
    case 'assign-self': {
      const accountId = parseMyself(await jiraRequest(auth, '/rest/api/3/myself', { method: 'GET' }));
      await jiraRequest(auth, `${issuePath(key)}/assignee`, {
        method: 'PUT',
        body: { accountId },
        notFound: NOT_FOUND,
      });
    }
  }
}

export async function createStoryInEpic(
  conn: Connection,
  epicKey: string,
  story: NewStory,
): Promise<{ key: string; url: string }> {
  const auth = jiraAuth(conn);
  const epic = parseEpicInfo(
    await jiraRequest(auth, `${issuePath(epicKey)}?fields=project,issuetype`, { method: 'GET', notFound: NOT_FOUND }),
  );
  if (epic.hierarchyLevel !== EPIC_LEVEL) throw new InvalidEdit(`${epicKey} não é um épico`);
  const typeId = pickStoryTypeId(
    await jiraRequest(auth, `/rest/api/3/issue/createmeta/${encodeURIComponent(epic.project)}/issuetypes`, {
      method: 'GET',
      notFound: 'projeto não encontrado no Jira',
    }),
  );
  let created: unknown;
  try {
    created = await jiraRequest(auth, '/rest/api/3/issue', {
      method: 'POST',
      body: {
        fields: {
          project: { key: epic.project },
          issuetype: { id: typeId },
          summary: story.summary,
          parent: { key: epicKey },
          ...(story.description ? { description: adfDocument(story.description) } : {}),
        },
      },
      notFound: 'épico ou projeto não encontrado no Jira',
    });
  } catch (err) {
    // A create that timed out may still have happened: retrying blindly would duplicate it.
    if (isTimeout(err)) {
      throw new Error('o Jira demorou a responder — confira no épico se a história foi criada antes de tentar de novo');
    }
    throw err;
  }
  const key = parseCreatedKey(created);
  return { key, url: `${auth.baseUrl}/browse/${encodeURIComponent(key)}` };
}
