import { afterEach, describe, expect, it, vi } from 'vitest';
import {
  addComment,
  commentText,
  parseCreatedComment,
} from '@/lib/integrations/jira/comments';
import { adfDocument } from '@/lib/integrations/jira/parse';
import type { Connection } from '@/lib/vault/connections';

// Shape of the documented 201 answer of POST /rest/api/3/issue/{key}/comment,
// sanitized like the captured fixtures. No write was made to capture it.
const CREATED = {
  self: 'https://example.atlassian.net/rest/api/3/issue/10010/comment/10000',
  id: '10000',
  author: { accountId: '557058:00000000-0000-0000-0000-000000000001', displayName: 'Pessoa 1', active: true },
  body: { type: 'doc', version: 1, content: [{ type: 'paragraph', content: [{ type: 'text', text: 'oi' }] }] },
  created: '2026-10-20T16:10:02.227-0300',
  updated: '2026-10-20T16:10:02.227-0300',
  jsdPublic: true,
};

const conn = { values: { cloud: 'example', email: 'pessoa-1@example.com', token: 't' } } as unknown as Connection;

afterEach(() => vi.unstubAllGlobals());

describe('commentText', () => {
  it('trims and accepts 1..5000 characters', () => {
    expect(commentText('  oi  ')).toBe('oi');
    expect(commentText('a'.repeat(5000))).toHaveLength(5000);
  });

  it('rejects empty, blank, too long and non-string values', () => {
    expect(commentText('')).toBeNull();
    expect(commentText(' \n ')).toBeNull();
    expect(commentText('a'.repeat(5001))).toBeNull();
    expect(commentText(42)).toBeNull();
  });
});

describe('parseCreatedComment', () => {
  it('reads the id of the created comment', () => {
    expect(parseCreatedComment(CREATED)).toEqual({ id: '10000' });
  });

  it('fails visibly when the id is missing or not a string', () => {
    expect(() => parseCreatedComment({ ...CREATED, id: undefined })).toThrow(/id do comentário ausente/);
    expect(() => parseCreatedComment({ ...CREATED, id: 10000 })).toThrow(/id do comentário ausente/);
    expect(() => parseCreatedComment(null)).toThrow(/id do comentário ausente/);
  });
});

describe('addComment', () => {
  it('posts the ADF body to the issue comment endpoint', async () => {
    const fetchMock = vi.fn().mockResolvedValue({ ok: true, status: 201, json: async () => CREATED });
    vi.stubGlobal('fetch', fetchMock);

    expect(await addComment(conn, 'TT-123', 'linha 1\nlinha 2')).toEqual({ id: '10000' });

    const [url, init] = fetchMock.mock.calls[0];
    expect(url).toBe('https://example.atlassian.net/rest/api/3/issue/TT-123/comment');
    expect(init.method).toBe('POST');
    expect(JSON.parse(init.body)).toEqual({ body: adfDocument('linha 1\nlinha 2') });
  });
});
