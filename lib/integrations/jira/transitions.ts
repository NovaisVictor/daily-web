import type { Connection } from '@/lib/vault/connections';
import type { JiraStatusCategory } from '@/lib/types';
import { jiraAuth, jiraRequest, type JiraAuth } from '@/lib/integrations/jiraApi';
import { fail as failIn, isRecord, NOT_FOUND, requiredText } from '@/lib/integrations/jira/parse';

/** What a transition needs beyond the click. A screen means fields Jira wants
 *  filled in, which this panel does not render: those go to Jira itself. */
export type TransitionRequirement = 'nothing' | 'screen';

export interface JiraTransition {
  id: string;
  name: string;
  to: { name: string; category: JiraStatusCategory };
  requires: TransitionRequirement;
}

const CATEGORIES: readonly JiraStatusCategory[] = ['new', 'indeterminate', 'done'];

const WHERE = 'nas transições';

function fail(detail: string): never {
  failIn(WHERE, detail);
}

const text = (value: unknown, what: string) => requiredText(value, WHERE, what);

function category(value: unknown): JiraStatusCategory {
  const key = isRecord(value) ? value.key : undefined;
  const found = CATEGORIES.find((c) => c === key);
  if (!found) fail(`categoria de status desconhecida (${String(key)})`);
  return found;
}

function requirement(raw: Record<string, unknown>): TransitionRequirement {
  if (raw.hasScreen === true) return 'screen';
  const fields = raw.fields ?? {};
  if (!isRecord(fields)) fail('campos da transição');
  const asksForInput = Object.values(fields).some(
    (field) => isRecord(field) && field.required === true && field.hasDefaultValue !== true,
  );
  return asksForInput ? 'screen' : 'nothing';
}

interface ParsedTransition extends JiraTransition {
  toStatusId: string;
  available: boolean;
  looped: boolean;
}

function parseOne(raw: unknown): ParsedTransition {
  if (!isRecord(raw)) fail('transição não é um objeto');
  const id = text(raw.id, 'id da transição');
  if (!/^\d+$/.test(id)) fail(`id de transição inválido (${id})`);
  if (!isRecord(raw.to)) fail(`destino da transição ${id}`);
  return {
    id,
    name: text(raw.name, `nome da transição ${id}`),
    to: { name: text(raw.to.name, `status de destino da transição ${id}`), category: category(raw.to.statusCategory) },
    requires: requirement(raw),
    toStatusId: text(raw.to.id, `id do status de destino da transição ${id}`),
    available: raw.isAvailable !== false,
    looped: raw.isLooped === true,
  };
}

/** The transitions a person can take from where the issue is now. The one that
 *  lands on the current status changes nothing and is left out. */
export function parseTransitions(data: unknown, currentStatusId: string): JiraTransition[] {
  if (!isRecord(data) || !Array.isArray(data.transitions)) fail('lista de transições ausente');
  return data.transitions
    .map(parseOne)
    .filter((t) => t.available && !t.looped && t.toStatusId !== currentStatusId)
    .map(({ id, name, to, requires }) => ({ id, name, to, requires }));
}

export function parseCurrentStatusId(data: unknown): string {
  const status = isRecord(data) && isRecord(data.fields) ? data.fields.status : undefined;
  if (!isRecord(status)) fail('status atual da issue ausente');
  return text(status.id, 'id do status atual');
}

async function load(auth: JiraAuth, key: string): Promise<JiraTransition[]> {
  const issue = encodeURIComponent(key);
  const [transitions, current] = await Promise.all([
    jiraRequest(auth, `/rest/api/3/issue/${issue}/transitions?expand=transitions.fields`, {
      method: 'GET',
      notFound: NOT_FOUND,
    }),
    jiraRequest(auth, `/rest/api/3/issue/${issue}?fields=status`, { method: 'GET', notFound: NOT_FOUND }),
  ]);
  return parseTransitions(transitions, parseCurrentStatusId(current));
}

export async function fetchTransitions(conn: Connection, key: string): Promise<JiraTransition[]> {
  return load(jiraAuth(conn), key);
}

export class TransitionUnavailable extends Error {
  constructor() {
    super('essa transição não está mais disponível');
  }
}

/** Re-reads the transitions before writing: what the client saw may be stale,
 *  and a transition that now needs a screen would fail or skip its fields. */
export async function applyTransition(conn: Connection, key: string, transitionId: string): Promise<void> {
  const auth = jiraAuth(conn);
  const current = await load(auth, key);
  const chosen = current.find((t) => t.id === transitionId);
  if (!chosen || chosen.requires !== 'nothing') throw new TransitionUnavailable();
  await jiraRequest(auth, `/rest/api/3/issue/${encodeURIComponent(key)}/transitions`, {
    method: 'POST',
    body: { transition: { id: transitionId } },
    notFound: NOT_FOUND,
  });
}
