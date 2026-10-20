import type { Connection } from '@/lib/vault/connections';
import { jiraAuth, jiraRequest } from '@/lib/integrations/jiraApi';

export const COMMENT_MAX_LENGTH = 5000;

interface AdfText {
  type: 'text';
  text: string;
}

interface AdfParagraph {
  type: 'paragraph';
  content: AdfText[];
}

export interface AdfDoc {
  type: 'doc';
  version: 1;
  content: AdfParagraph[];
}

export interface CreatedComment {
  id: string;
}

/** The text as typed, never read as wiki markup: each line becomes a plain
 *  text node. ADF rejects empty text nodes, so blank lines are dropped. */
export function commentDocument(text: string): AdfDoc {
  return {
    type: 'doc',
    version: 1,
    content: text
      .split(/\r?\n/)
      .filter((line) => line.trim() !== '')
      .map((line) => ({ type: 'paragraph', content: [{ type: 'text', text: line }] })),
  };
}

/** The comment text from a request body: trimmed, 1..COMMENT_MAX_LENGTH. */
export function commentText(value: unknown): string | null {
  if (typeof value !== 'string') return null;
  const text = value.trim();
  return text.length >= 1 && text.length <= COMMENT_MAX_LENGTH ? text : null;
}

export function parseCreatedComment(data: unknown): CreatedComment {
  const id = typeof data === 'object' && data !== null ? (data as Record<string, unknown>).id : undefined;
  if (typeof id !== 'string' || !/^\d+$/.test(id)) {
    throw new Error('resposta inesperada do Jira ao comentar: id do comentário ausente');
  }
  return { id };
}

export async function addComment(conn: Connection, key: string, text: string): Promise<CreatedComment> {
  const data = await jiraRequest(jiraAuth(conn), `/rest/api/3/issue/${encodeURIComponent(key)}/comment`, {
    method: 'POST',
    body: { body: commentDocument(text) },
    notFound: 'issue não encontrada no Jira',
  });
  return parseCreatedComment(data);
}
