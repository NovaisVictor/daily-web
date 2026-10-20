import { afterEach, describe, expect, it, vi } from 'vitest';
import { jiraRequest } from '@/lib/integrations/jiraApi';

const AUTH = { baseUrl: 'https://example.atlassian.net', header: 'Basic x' };

function refuse(status: number, body: unknown) {
  vi.stubGlobal(
    'fetch',
    vi.fn().mockResolvedValue({ ok: false, status, text: async () => JSON.stringify(body) }),
  );
}

afterEach(() => vi.unstubAllGlobals());

describe('jiraRequest refusals', () => {
  it('shows the field errors Jira gives when it rejects a write', async () => {
    refuse(400, { errorMessages: [], errors: { duedate: 'data inválida' } });
    await expect(
      jiraRequest(AUTH, '/rest/api/3/issue/TT-1', { method: 'PUT', body: {} }),
    ).rejects.toThrow('Jira respondeu 400: duedate: data inválida');
  });

  it('shows the Service Desk message, which comes in the singular errorMessage', async () => {
    refuse(400, { errorMessage: 'A aprovação já foi respondida' });
    await expect(
      jiraRequest(AUTH, '/rest/servicedeskapi/request/PDS-1/approval/1', {
        method: 'POST',
        body: { decision: 'approve' },
      }),
    ).rejects.toThrow('Jira respondeu 400: A aprovação já foi respondida');
  });

  it("shows Jira's own reason on a 403 that carries one", async () => {
    refuse(403, { errorMessages: ['Você não tem permissão para transicionar esta issue.'] });
    await expect(
      jiraRequest(AUTH, '/rest/api/3/issue/TT-1/transitions', { method: 'POST', body: {} }),
    ).rejects.toThrow('o Jira recusou: Você não tem permissão para transicionar esta issue.');
  });

  it('falls back to the generic permission sentence on a 403 without a message', async () => {
    refuse(403, {});
    await expect(jiraRequest(AUTH, '/rest/api/3/issue/TT-1', { method: 'GET' })).rejects.toThrow(
      'o API token do Jira não tem permissão para isso',
    );
  });

  it('says the issue is missing, not the domain, when the caller names it', async () => {
    refuse(404, {});
    await expect(
      jiraRequest(AUTH, '/rest/api/3/issue/TT-1', { method: 'GET', notFound: 'issue não encontrada' }),
    ).rejects.toThrow('issue não encontrada');
  });
});
