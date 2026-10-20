import { describe, expect, it } from 'vitest';
import { adfDocument, isCalendarDate, requiredText } from '@/lib/integrations/jira/parse';

describe('isCalendarDate', () => {
  it('accepts real dates and rejects impossible ones', () => {
    expect(isCalendarDate('2024-02-29')).toBe(true);
    expect(isCalendarDate('2026-02-29')).toBe(false);
    expect(isCalendarDate('2026-1-01')).toBe(false);
    expect(isCalendarDate(20260101)).toBe(false);
  });
});

describe('adfDocument', () => {
  it('writes one trimmed plain-text paragraph per non-empty line', () => {
    expect(adfDocument('primeira\r\n\n  \n segunda ')).toEqual({
      type: 'doc',
      version: 1,
      content: [
        { type: 'paragraph', content: [{ type: 'text', text: 'primeira' }] },
        { type: 'paragraph', content: [{ type: 'text', text: 'segunda' }] },
      ],
    });
  });

  it('keeps wiki markup as literal text', () => {
    const doc = adfDocument('*negrito* [link|https://x] {code}');
    expect(doc.content[0].content).toEqual([{ type: 'text', text: '*negrito* [link|https://x] {code}' }]);
  });
});

describe('requiredText', () => {
  it('fails visibly, naming where, when the text is missing', () => {
    expect(() => requiredText('  ', 'nas transições', 'nome')).toThrow(
      'resposta inesperada do Jira nas transições: nome ausente',
    );
  });
});
