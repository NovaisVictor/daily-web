import type { Connection } from '@/lib/vault/connections';
import { jiraAuth, jiraRequest, type JiraAuth } from '@/lib/integrations/jiraApi';
import { COMMENT_MAX } from '@/lib/jiraLimits';
import { adfDocument, fail, isRecord, NOT_FOUND } from '@/lib/integrations/jira/parse';

export interface CreatedComment {
  id: string;
}

/** The comment text from a request body: trimmed, 1..COMMENT_MAX. */
export function commentText(value: unknown): string | null {
  if (typeof value !== 'string') return null;
  const text = value.trim();
  return text.length >= 1 && text.length <= COMMENT_MAX ? text : null;
}

export function parseCreatedComment(data: unknown): CreatedComment {
  const id = isRecord(data) ? data.id : undefined;
  if (typeof id !== 'string' || !/^\d+$/.test(id)) fail('ao comentar', 'id do comentário ausente');
  return { id };
}

export async function postComment(auth: JiraAuth, key: string, text: string): Promise<CreatedComment> {
  const data = await jiraRequest(auth, `/rest/api/3/issue/${encodeURIComponent(key)}/comment`, {
    method: 'POST',
    body: { body: adfDocument(text) },
    notFound: NOT_FOUND,
  });
  return parseCreatedComment(data);
}

export async function addComment(conn: Connection, key: string, text: string): Promise<CreatedComment> {
  return postComment(jiraAuth(conn), key, text);
}
