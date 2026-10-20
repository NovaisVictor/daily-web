import { afterEach, describe, expect, it, vi } from 'vitest';
import fieldsFixture from '../../fixtures/jira-write/fields-flag-start.json';
import editmetaFixture from '../../fixtures/jira-write/editmeta-story.json';
import flaggedIssueFixture from '../../fixtures/jira-write/issue-flagged.json';
import {
  fetchByKeys,
  findFlaggedField,
  flaggedFieldIds,
  toJiraItem,
  type JiraAuth,
} from '@/lib/integrations/jiraApi';
import {
  changeFlag,
  FlagCommentFailed,
  parseFlaggedFieldId,
  parseImpedimentOptionId,
} from '@/lib/integrations/jira/flag';
import { adfDocument } from '@/lib/integrations/jira/parse';
import type { Connection } from '@/lib/vault/connections';

const BASE = 'https://example.atlassian.net';
const AUTH: JiraAuth = { baseUrl: BASE, header: 'Basic x' };
const CONN = {
  id: 'c1',
  module: 'jira',
  label: 'Jira',
  values: { cloud: 'example', email: 'eu@example.com', token: 'segredo' },
} as unknown as Connection;

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

afterEach(() => {
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
  flaggedFieldIds.clear();
});

describe('findFlaggedField', () => {
  it('finds the Flagged field in the captured field list', () => {
    expect(findFlaggedField(fieldsFixture)).toBe('customfield_10021');
  });

  it('finds the field by its translated name', () => {
    expect(findFlaggedField([{ id: 'customfield_1', name: 'Sinalizado' }])).toBe('customfield_1');
  });

  it('returns null when the instance has no such field', () => {
    expect(findFlaggedField([{ id: 'customfield_10015', name: 'Data de início' }])).toBeNull();
  });
});

describe('toJiraItem impediment', () => {
  it('maps the captured flagged issue to flagged', () => {
    const raw = { ...flaggedIssueFixture, fields: { ...flaggedIssueFixture.fields, summary: 'x' } };
    expect(toJiraItem(raw, BASE, 'assignee', 'customfield_10021').impediment).toBe('flagged');
  });

  it('maps null (the captured unflagged value) to none', () => {
    expect(toJiraItem({ key: 'TT-1', fields: { customfield_10021: null } }, BASE, 'assignee', 'customfield_10021').impediment).toBe('none');
  });

  it('maps an empty list to none', () => {
    expect(toJiraItem({ key: 'TT-1', fields: { customfield_10021: [] } }, BASE, 'assignee', 'customfield_10021').impediment).toBe('none');
  });

  it('is none when the instance has no Flagged field', () => {
    expect(toJiraItem({ key: 'TT-1', fields: {} }, BASE, 'assignee', null).impediment).toBe('none');
  });

  it('treats an unexpected shape as none and warns, so one odd field does not hide the whole panel', () => {
    const warn = vi.spyOn(console, 'warn').mockImplementation(() => {});
    const item = toJiraItem({ key: 'TT-1', fields: { customfield_10021: 'Impediment' } }, BASE, 'assignee', 'customfield_10021');
    expect(item.impediment).toBe('none');
    expect(warn).toHaveBeenCalledTimes(1);
  });
});

describe('row searches and the Flagged field', () => {
  const search = (issues: unknown[]): Reply => ({ status: 200, body: { issues } });

  it('discovers the field and asks the search for it', async () => {
    const fetchMock = stubJira({
      'GET /rest/api/3/field': { status: 200, body: fieldsFixture },
      'POST /rest/api/3/search/jql': search([flaggedIssueFixture]),
    });

    const [item] = await fetchByKeys(CONN, ['TT-5007']);

    expect(item.impediment).toBe('flagged');
    const searchBody = requests(fetchMock).find((r) => r.path === '/rest/api/3/search/jql')?.body;
    expect(searchBody.fields).toContain('customfield_10021');
  });

  it('caches the field id per instance', async () => {
    const fetchMock = stubJira({
      'GET /rest/api/3/field': { status: 200, body: fieldsFixture },
      'POST /rest/api/3/search/jql': search([]),
    });

    await fetchByKeys(CONN, ['TT-1']);
    await fetchByKeys(CONN, ['TT-1']);

    expect(requests(fetchMock).filter((r) => r.path === '/rest/api/3/field')).toHaveLength(1);
  });

  it('still loads the rows when the instance has no Flagged field', async () => {
    const fetchMock = stubJira({
      'GET /rest/api/3/field': { status: 200, body: [{ id: 'summary', name: 'Resumo' }] },
      'POST /rest/api/3/search/jql': search([{ key: 'TT-1', fields: { summary: 'x' } }]),
    });

    const [item] = await fetchByKeys(CONN, ['TT-1']);

    expect(item.impediment).toBe('none');
    const searchBody = requests(fetchMock).find((r) => r.path === '/rest/api/3/search/jql')?.body;
    expect(searchBody.fields).not.toContain('customfield_10021');
  });

  it('still loads the rows when the field list fails', async () => {
    vi.spyOn(console, 'warn').mockImplementation(() => {});
    stubJira({
      'GET /rest/api/3/field': { status: 500, body: { errorMessages: ['boom'] } },
      'POST /rest/api/3/search/jql': search([{ key: 'TT-1', fields: { summary: 'x' } }]),
    });

    const [item] = await fetchByKeys(CONN, ['TT-1']);

    expect(item.impediment).toBe('none');
  });

  it('asks for the field list once when two reads start together', async () => {
    const fetchMock = stubJira({
      'GET /rest/api/3/field': { status: 200, body: fieldsFixture },
      'POST /rest/api/3/search/jql': search([]),
    });

    await Promise.all([fetchByKeys(CONN, ['TT-1']), fetchByKeys(CONN, ['TT-2'])]);

    expect(requests(fetchMock).filter((r) => r.path === '/rest/api/3/field')).toHaveLength(1);
  });

  it('remembers for a while that the instance has no Flagged field', async () => {
    const fetchMock = stubJira({
      'GET /rest/api/3/field': { status: 200, body: [{ id: 'summary', name: 'Resumo' }] },
      'POST /rest/api/3/search/jql': search([]),
    });

    await fetchByKeys(CONN, ['TT-1']);
    await fetchByKeys(CONN, ['TT-1']);

    expect(requests(fetchMock).filter((r) => r.path === '/rest/api/3/field')).toHaveLength(1);
  });

  it('asks again for the field list after a failed one', async () => {
    vi.spyOn(console, 'warn').mockImplementation(() => {});
    const fetchMock = stubJira({
      'GET /rest/api/3/field': { status: 500, body: { errorMessages: ['boom'] } },
      'POST /rest/api/3/search/jql': search([]),
    });

    await fetchByKeys(CONN, ['TT-1']);
    await fetchByKeys(CONN, ['TT-1']);

    expect(requests(fetchMock).filter((r) => r.path === '/rest/api/3/field')).toHaveLength(2);
  });
});

describe('parseFlaggedFieldId', () => {
  it('reads the field id from the captured field list', () => {
    expect(parseFlaggedFieldId(fieldsFixture)).toBe('customfield_10021');
  });

  it('fails visibly when the field does not exist', () => {
    expect(() => parseFlaggedFieldId([])).toThrow('campo "Flagged" não encontrado no Jira');
  });

  it('fails visibly on an unexpected shape', () => {
    expect(() => parseFlaggedFieldId({ fields: [] })).toThrow('resposta inesperada do Jira');
  });
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
    'GET /rest/api/3/field': { status: 200, body: fieldsFixture },
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
      { method: 'GET', path: '/rest/api/3/field', body: undefined },
      { method: 'GET', path: '/rest/api/3/issue/TT-5019/editmeta', body: undefined },
      { method: 'PUT', path: '/rest/api/3/issue/TT-5019', body: { fields: { customfield_10021: [{ id: '10019' }] } } },
      { method: 'POST', path: '/rest/api/3/issue/TT-5019/comment', body: { body: adfDocument('Impedimento: aguardando API') } },
    ]);
  });

  it('clears the field without a comment when no note is given', async () => {
    const fetchMock = stubJira({ ...discovery, 'PUT /rest/api/3/issue/TT-5019': { status: 204 } });

    await changeFlag(AUTH, 'TT-5019', { action: 'unflag', note: null });

    expect(requests(fetchMock)).toEqual([
      { method: 'GET', path: '/rest/api/3/field', body: undefined },
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
