import { instanceMeta, jiraRequest, type JiraAuth } from '@/lib/integrations/jiraApi';
import { postComment } from '@/lib/integrations/jira/comments';
import { fail as failIn, isRecord, NOT_FOUND } from '@/lib/integrations/jira/parse';

export type FlagChange = { action: 'flag'; reason: string } | { action: 'unflag'; note: string | null };

const IMPEDIMENT_VALUE = 'Impediment';

function fail(detail: string): never {
  failIn('no impedimento', detail);
}

/** The option that means "flagged". The id is per instance, so it comes from
 *  the issue's own edit metadata rather than a constant. */
export function parseImpedimentOptionId(data: unknown, fieldId: string): string {
  if (!isRecord(data) || !isRecord(data.fields)) fail('metadados de edição ausentes');
  const field = data.fields[fieldId];
  if (!isRecord(field)) throw new Error('o campo "Flagged" não pode ser editado nesta issue');
  if (!Array.isArray(field.allowedValues)) fail('opções do campo "Flagged" ausentes');
  const option = field.allowedValues.find((v) => isRecord(v) && v.value === IMPEDIMENT_VALUE);
  if (!isRecord(option)) fail(`opção "${IMPEDIMENT_VALUE}" ausente no campo "Flagged"`);
  if (typeof option.id !== 'string' || !/^\d+$/.test(option.id)) fail('id da opção "Impediment" inválido');
  return option.id;
}

function parseEdit(data: unknown): void {
  if (data !== null) fail('edição da issue devolveu corpo');
}

/** The flag changed but the comment did not: the person needs to know the
 *  issue is in a state they did not fully ask for. */
export class FlagCommentFailed extends Error {
  constructor(change: FlagChange['action'], cause: unknown) {
    const what = change === 'flag' ? 'marcado' : 'removido';
    const detail = cause instanceof Error ? cause.message : String(cause);
    super(`o impedimento foi ${what}, mas o comentário não foi gravado: ${detail}`);
  }
}

async function flaggedFieldId(auth: JiraAuth): Promise<string> {
  const { flaggedField } = await instanceMeta(auth);
  if (!flaggedField) throw new Error('campo "Flagged" não encontrado no Jira');
  return flaggedField;
}

export async function changeFlag(auth: JiraAuth, key: string, change: FlagChange): Promise<void> {
  const issue = `/rest/api/3/issue/${encodeURIComponent(key)}`;
  const fieldId = await flaggedFieldId(auth);

  let value: { id: string }[] = [];
  if (change.action === 'flag') {
    const meta = await jiraRequest(auth, `${issue}/editmeta`, { method: 'GET', notFound: NOT_FOUND });
    value = [{ id: parseImpedimentOptionId(meta, fieldId) }];
  }

  parseEdit(
    await jiraRequest(auth, issue, { method: 'PUT', body: { fields: { [fieldId]: value } }, notFound: NOT_FOUND }),
  );

  const text =
    change.action === 'flag'
      ? `Impedimento: ${change.reason}`
      : change.note
        ? `Impedimento removido: ${change.note}`
        : null;
  if (!text) return;

  try {
    await postComment(auth, key, text);
  } catch (err) {
    throw new FlagCommentFailed(change.action, err);
  }
}
