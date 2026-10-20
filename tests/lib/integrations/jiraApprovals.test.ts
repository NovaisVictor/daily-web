import { afterEach, describe, expect, it, vi } from 'vitest';
import captured from '@/tests/fixtures/jira-write/approvals-pending.json';
import single from '@/tests/fixtures/jira-write/approval-single.json';
import {
  answerApproval,
  fetchPendingApprovals,
  parseApproval,
  parseApprovalPage,
} from '@/lib/integrations/jira/approvals';
import type { JiraAuth } from '@/lib/integrations/jiraApi';

const AUTH: JiraAuth = { baseUrl: 'https://acme.atlassian.net', header: 'Basic x' };

const decidedPage = captured.decidedRequest.response;
const emptyPage = captured.nonServiceDeskIssue.response;

/** No pending approval existed when the fixtures were captured, so this takes
 *  the captured approval and flips only `canAnswerApproval` and `finalDecision`. */
function pendingFromCaptured(overrides: Record<string, unknown> = {}) {
  return { ...single, canAnswerApproval: true, finalDecision: 'pending', ...overrides };
}

function pageOf(values: unknown[], isLastPage = true) {
  return { ...decidedPage, size: values.length, values, isLastPage };
}

function stubResponses(...bodies: unknown[]) {
  const fetchMock = vi.fn();
  for (const body of bodies) {
    fetchMock.mockResolvedValueOnce({ ok: true, status: 200, headers: new Headers(), json: async () => body });
  }
  vi.stubGlobal('fetch', fetchMock);
  return fetchMock;
}

afterEach(() => vi.unstubAllGlobals());

describe('parseApprovalPage', () => {
  it('reads the captured decided approval', () => {
    expect(parseApprovalPage(decidedPage)).toEqual({
      values: [{ id: '3516', name: 'Aprovação', finalDecision: 'approved', canAnswerApproval: false }],
      isLastPage: true,
    });
  });

  it('reads the empty list of a non-service-desk issue', () => {
    expect(parseApprovalPage(emptyPage)).toEqual({ values: [], isLastPage: true });
  });

  it('fails visibly when the page has no values', () => {
    expect(() => parseApprovalPage({ isLastPage: true })).toThrow(/resposta inesperada do Jira/);
  });

  it('fails visibly on an unknown final decision', () => {
    expect(() => parseApproval({ ...single, finalDecision: 'maybe' })).toThrow(/decisão desconhecida "maybe"/);
  });

  it('fails visibly when canAnswerApproval is missing', () => {
    const { canAnswerApproval: _omit, ...rest } = single;
    expect(() => parseApproval(rest)).toThrow(/canAnswerApproval/);
  });
});

describe('fetchPendingApprovals', () => {
  it('asks the service desk approval list of the issue', async () => {
    const fetchMock = stubResponses(emptyPage);
    await fetchPendingApprovals(AUTH, 'PDS-2763');
    expect(fetchMock.mock.calls[0][0]).toBe(
      'https://acme.atlassian.net/rest/servicedeskapi/request/PDS-2763/approval?start=0&limit=50',
    );
    expect(fetchMock.mock.calls[0][1].method).toBe('GET');
  });

  it('keeps only approvals the user can still answer', async () => {
    stubResponses(pageOf([single, pendingFromCaptured({ id: '3517', name: 'Gestor' })]));
    expect(await fetchPendingApprovals(AUTH, 'PDS-2763')).toEqual([{ id: '3517', name: 'Gestor' }]);
  });

  it('drops an answerable approval that is no longer pending', async () => {
    stubResponses(pageOf([pendingFromCaptured({ finalDecision: 'declined' })]));
    expect(await fetchPendingApprovals(AUTH, 'PDS-2763')).toEqual([]);
  });

  it('follows the pages until the last one', async () => {
    const fetchMock = stubResponses(
      pageOf([pendingFromCaptured({ id: '1' })], false),
      pageOf([pendingFromCaptured({ id: '2' })], true),
    );
    const result = await fetchPendingApprovals(AUTH, 'PDS-2763');
    expect(result.map((a) => a.id)).toEqual(['1', '2']);
    expect(fetchMock.mock.calls[1][0]).toContain('?start=50&limit=50');
  });
});

describe('answerApproval', () => {
  it('posts the decision to the approval', async () => {
    const fetchMock = stubResponses(pendingFromCaptured({ finalDecision: 'approved', canAnswerApproval: false }));
    await answerApproval(AUTH, 'PDS-2763', '3516', 'approve');
    const [url, init] = fetchMock.mock.calls[0];
    expect(url).toBe('https://acme.atlassian.net/rest/servicedeskapi/request/PDS-2763/approval/3516');
    expect(init.method).toBe('POST');
    expect(JSON.parse(init.body)).toEqual({ decision: 'approve' });
  });
});
