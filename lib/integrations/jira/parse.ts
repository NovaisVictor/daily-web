export const NOT_FOUND = 'issue não encontrada no Jira';

export function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

/** `where` names the read that went wrong ("nas transições"); `null` for none. */
export function unexpected(where: string | null, detail: string): Error {
  return new Error(`resposta inesperada do Jira${where ? ` ${where}` : ''}: ${detail}`);
}

export function fail(where: string | null, detail: string): never {
  throw unexpected(where, detail);
}

export function requiredText(value: unknown, where: string | null, what: string): string {
  if (typeof value !== 'string' || value.trim() === '') fail(where, `${what} ausente`);
  return value;
}

export function isCalendarDate(value: unknown): value is string {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const [year, month, day] = value.split('-').map(Number);
  const date = new Date(Date.UTC(year, month - 1, day));
  return date.getUTCFullYear() === year && date.getUTCMonth() === month - 1 && date.getUTCDate() === day;
}

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

/** The text as typed, never read as wiki markup: each line becomes a plain
 *  text node. ADF rejects empty text nodes, so blank lines are dropped. */
export function adfDocument(text: string): AdfDoc {
  return {
    type: 'doc',
    version: 1,
    content: text
      .split(/\r?\n/)
      .map((line) => line.trim())
      .filter((line) => line !== '')
      .map((line) => ({ type: 'paragraph', content: [{ type: 'text', text: line }] })),
  };
}
