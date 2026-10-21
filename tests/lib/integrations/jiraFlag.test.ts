import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import editmetaFixture from '../../fixtures/jira-write/editmeta-story.json';
import { setInstanceMetaForTests, type JiraAuth } from '@/lib/integrations/jiraApi';
import { changeFlag, FlagCommentFailed, parseImpedimentOptionId } from '@/lib/integrations/jira/flag';
import { adfDocument } from '@/lib/integrations/jira/parse';

const BASE = 'https://example.atlassian.net';
const AUTH: JiraAuth = { baseUrl: BASE, header: 'Basic x' };

function knownMeta(flaggedField: string | null) {
  setInstanceMetaForTests(BASE, { startField: 'customfield_10015', flaggedField, priorityRank: new Map() });
}

type Reply = { status: number; body?: unknown };

/** Answers by method and path; records every request for exact assertions. */
function stubJira(routes: Record<string, Reply>) {
  const fetchMock = vi.fn(async (url: string, init: RequestInit) => {
    const path = url.replace(BASE, '');
    const reply = routes[`${init.method} ${path}`];
    if (!reply) throw new Error(`unexpected request ${init.method} ${path}`);
    const text = reply.body === undefined ? '' : JSON.stringify(reply.body);
    return {
      ok: reply.status < 400,
      status: reply.status,
      headers: { get: () => (reply.body === undefined ? '0' : null) },
      json: async () => reply.body,
      text: async () => text,
    };
  });
  vi.stubGlobal('fetch', fetchMock);
  return fetchMock;
}

const requests = (fetchMock: ReturnType<typeof stubJira>) =>
  fetchMock.mock.calls.map(([url, init]) => ({
    method: init.method,
    path: String(url).replace(BASE, ''),
    body: init.body === undefined ? undefined : JSON.parse(String(init.body)),
  }));

beforeEach(() => knownMeta('customfield_10021'));

afterEach(() => {
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
  setInstanceMetaForTests(BASE, null);
});

describe('parseImpedimentOptionId', () => {
  it('reads the Impediment option from the captured editmeta', () => {
    expect(parseImpedimentOptionId(editmetaFixture, 'customfield_10021')).toBe('10019');
  });

  it('fails visibly when the Impediment option is absent', () => {
    const meta = { fields: { customfield_10021: { allowedValues: [{ id: '1', value: 'Outro' }] } } };
    expect(() => parseImpedimentOptionId(meta, 'customfield_10021')).toThrow('opção "Impediment" ausente');
  });

  it('fails visibly when the field is not editable on the issue', () => {
    expect(() => parseImpedimentOptionId({ fields: {} }, 'customfield_10021')).toThrow('não pode ser editado');
  });

  it('fails visibly on an unexpected shape', () => {
    expect(() => parseImpedimentOptionId([], 'customfield_10021')).toThrow('resposta inesperada do Jira');
  });
});

describe('changeFlag', () => {
  const discovery = {
    'GET /rest/api/3/issue/TT-5019/editmeta': { status: 200, body: editmetaFixture },
  };

  it('sets the Impediment option and comments the reason', async () => {
    const fetchMock = stubJira({
      ...discovery,
      'PUT /rest/api/3/issue/TT-5019': { status: 204 },
      'POST /rest/api/3/issue/TT-5019/comment': { status: 201, body: { id: '900' } },
    });

    await changeFlag(AUTH, 'TT-5019', { action: 'flag', reason: 'aguardando API' });

    expect(requests(fetchMock)).toEqual([
      { method: 'GET', path: '/rest/api/3/issue/TT-5019/editmeta', body: undefined },
      { method: 'PUT', path: '/rest/api/3/issue/TT-5019', body: { fields: { customfield_10021: [{ id: '10019' }] } } },
      { method: 'POST', path: '/rest/api/3/issue/TT-5019/comment', body: { body: adfDocument('Impedimento: aguardando API') } },
    ]);
  });

  it('refuses before writing when the instance has no Flagged field', async () => {
    knownMeta(null);
    const fetchMock = stubJira({});

    await expect(changeFlag(AUTH, 'TT-5019', { action: 'flag', reason: 'x' })).rejects.toThrow(
      'campo "Flagged" não encontrado no Jira',
    );
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it('clears the field without a comment when no note is given', async () => {
    const fetchMock = stubJira({ ...discovery, 'PUT /rest/api/3/issue/TT-5019': { status: 204 } });

    await changeFlag(AUTH, 'TT-5019', { action: 'unflag', note: null });

    expect(requests(fetchMock)).toEqual([
      { method: 'PUT', path: '/rest/api/3/issue/TT-5019', body: { fields: { customfield_10021: [] } } },
    ]);
  });

  it('comments the note when unflagging with one', async () => {
    const fetchMock = stubJira({
      ...discovery,
      'PUT /rest/api/3/issue/TT-5019': { status: 204 },
      'POST /rest/api/3/issue/TT-5019/comment': { status: 201, body: { id: '901' } },
    });

    await changeFlag(AUTH, 'TT-5019', { action: 'unflag', note: 'API liberada' });

    expect(requests(fetchMock).at(-1)).toEqual({
      method: 'POST',
      path: '/rest/api/3/issue/TT-5019/comment',
      body: { body: adfDocument('Impedimento removido: API liberada') },
    });
  });

  it('says the flag changed when only the comment fails', async () => {
    stubJira({
      ...discovery,
      'PUT /rest/api/3/issue/TT-5019': { status: 204 },
      'POST /rest/api/3/issue/TT-5019/comment': { status: 400, body: { errorMessages: ['comentário recusado'] } },
    });

    const result = changeFlag(AUTH, 'TT-5019', { action: 'flag', reason: 'x' });

    await expect(result).rejects.toBeInstanceOf(FlagCommentFailed);
    await expect(result).rejects.toThrow('o impedimento foi marcado, mas o comentário não foi gravado: Jira respondeu 400: comentário recusado');
  });

  it('does not comment when the edit is refused', async () => {
    const fetchMock = stubJira({
      ...discovery,
      'PUT /rest/api/3/issue/TT-5019': { status: 400, body: { errors: { customfield_10021: 'campo fora da tela' } } },
    });

    await expect(changeFlag(AUTH, 'TT-5019', { action: 'flag', reason: 'x' })).rejects.toThrow(
      'Jira respondeu 400: customfield_10021: campo fora da tela',
    );
    expect(requests(fetchMock).some((r) => r.path.endsWith('/comment'))).toBe(false);
  });
});
