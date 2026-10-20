import { afterEach, describe, expect, it, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, within } from '@testing-library/react';
import { BulkStartDate } from '@/components/jira/actions/BulkStartDate';
import { JiraActionsProvider, type JiraViewer } from '@/components/jira/actions/context';
import type { JiraProblem, JiraProblemItem } from '@/lib/types';

function issue(key: string, summary: string, problems: JiraProblem[]): JiraProblemItem {
  return {
    key,
    summary,
    status: 'Em Andamento',
    statusCategory: 'indeterminate',
    updatedAt: '2026-10-20T10:00:00.000-0300',
    dueDate: '',
    project: 'TT',
    url: `https://acme.atlassian.net/browse/${key}`,
    parent: null,
    role: 'assignee',
    awaitingApproval: false,
    kind: 'História',
    subtask: false,
    hierarchyLevel: 0,
    impediment: 'none',
    problems,
  };
}

const PROBLEMS = [
  issue('TT-1', 'Login novo', ['story-in-progress-without-start']),
  issue('TT-2', 'Relatório', ['story-done-without-start']),
  issue('TT-3', 'Sem épico', ['story-without-epic']),
];

const SUGGESTIONS = {
  suggestions: [
    { key: 'TT-1', status: 'suggested', date: '2026-10-09', source: 'changelog' },
    { key: 'TT-2', status: 'suggested', date: '2026-09-01', source: 'created' },
  ],
};

const json = (status: number, body: unknown) => ({ ok: status < 400, status, json: async () => body });

function stubServer(postResponse: ReturnType<typeof json> = json(200, { ok: true, results: [] })) {
  const fetchMock = vi.fn(async (url: string, init?: RequestInit) =>
    init?.method === 'POST' ? postResponse : json(200, SUGGESTIONS),
  );
  vi.stubGlobal('fetch', fetchMock);
  return fetchMock;
}

function renderBulk(
  { problems = PROBLEMS, viewer = { kind: 'self' } as JiraViewer, onChanged = vi.fn() } = {},
) {
  render(
    <JiraActionsProvider value={{ viewer, onChanged }}>
      <BulkStartDate problems={problems} />
    </JiraActionsProvider>,
  );
  return { onChanged };
}

async function openReview() {
  fireEvent.click(screen.getByRole('button', { name: 'Preencher início em todas (2)' }));
  return screen.findByRole('dialog', { name: 'Preencher data de início' });
}

function postedBody(fetchMock: ReturnType<typeof stubServer>) {
  const call = fetchMock.mock.calls.find(([, init]) => init?.method === 'POST');
  return JSON.parse(String(call?.[1]?.body));
}

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
});

describe('BulkStartDate', () => {
  it('counts only the stories missing a start date', () => {
    renderBulk();
    expect(screen.getByRole('button', { name: 'Preencher início em todas (2)' })).toBeTruthy();
  });

  it('stays hidden when no story is missing a start date', () => {
    renderBulk({ problems: [PROBLEMS[2]] });
    expect(screen.queryByRole('button', { name: /Preencher início/ })).toBeNull();
  });

  it("stays hidden on a colleague's view so their issues are not bulk-edited by accident", () => {
    renderBulk({ viewer: { kind: 'person', name: 'Ana' } });
    expect(screen.queryByRole('button', { name: /Preencher início/ })).toBeNull();
  });

  it('asks the server for suggestions of the missing stories only', async () => {
    const fetchMock = stubServer();
    renderBulk();
    await openReview();
    expect(fetchMock).toHaveBeenCalledWith('/api/jira/problems/start-dates?keys=TT-1%2CTT-2');
  });

  it('lists each suggestion with its editable date and where it came from', async () => {
    stubServer();
    renderBulk();
    const dialog = await openReview();
    expect((within(dialog).getByLabelText('Data de início de TT-1') as HTMLInputElement).value).toBe('2026-10-09');
    expect((within(dialog).getByLabelText('Data de início de TT-2') as HTMLInputElement).value).toBe('2026-09-01');
    expect(within(dialog).getByText('primeira vez em andamento')).toBeTruthy();
    expect(within(dialog).getByText('data de criação')).toBeTruthy();
    expect(within(dialog).getByText('Login novo')).toBeTruthy();
    expect(within(dialog).getByRole('button', { name: 'Gravar 2 datas' })).toBeTruthy();
  });

  it('does not write anything before the confirmation click', async () => {
    const fetchMock = stubServer();
    renderBulk();
    await openReview();
    expect(fetchMock.mock.calls.some(([, init]) => init?.method === 'POST')).toBe(false);
  });

  it('writes the included rows with the edited dates', async () => {
    const fetchMock = stubServer(json(200, { ok: true, results: [{ key: 'TT-1', outcome: 'written' }] }));
    renderBulk();
    const dialog = await openReview();
    fireEvent.change(within(dialog).getByLabelText('Data de início de TT-1'), { target: { value: '2026-10-05' } });
    fireEvent.click(within(dialog).getByRole('checkbox', { name: 'Incluir TT-2' }));
    fireEvent.click(within(dialog).getByRole('button', { name: 'Gravar 1 data' }));
    await within(dialog).findByText('gravada ✓');
    expect(postedBody(fetchMock)).toEqual({ items: [{ key: 'TT-1', date: '2026-10-05' }] });
  });

  it("shows Jira's refusal next to the refused row and refreshes for the written one", async () => {
    stubServer(
      json(200, {
        ok: true,
        results: [
          { key: 'TT-1', outcome: 'written' },
          { key: 'TT-2', outcome: 'refused', error: 'Jira respondeu 400: campo não editável' },
        ],
      }),
    );
    const { onChanged } = renderBulk();
    const dialog = await openReview();
    fireEvent.click(within(dialog).getByRole('button', { name: 'Gravar 2 datas' }));
    expect(await within(dialog).findByText('Jira recusou: Jira respondeu 400: campo não editável')).toBeTruthy();
    expect(within(dialog).getByText('gravada ✓')).toBeTruthy();
    expect(onChanged).toHaveBeenCalledTimes(1);
  });

  it('does not refresh when every row was refused', async () => {
    stubServer(json(200, { results: [{ key: 'TT-1', outcome: 'refused', error: 'não' }, { key: 'TT-2', outcome: 'refused', error: 'não' }] }));
    const { onChanged } = renderBulk();
    const dialog = await openReview();
    fireEvent.click(within(dialog).getByRole('button', { name: 'Gravar 2 datas' }));
    await within(dialog).findAllByText('Jira recusou: não');
    expect(onChanged).not.toHaveBeenCalled();
  });

  it('shows the server error and keeps the review when the write fails as a whole', async () => {
    stubServer(json(502, { error: 'Jira respondeu 500: fora do ar' }));
    renderBulk();
    const dialog = await openReview();
    fireEvent.click(within(dialog).getByRole('button', { name: 'Gravar 2 datas' }));
    expect((await within(dialog).findByRole('alert')).textContent).toBe('Jira respondeu 500: fora do ar');
    expect(within(dialog).getByRole('button', { name: 'Gravar 2 datas' })).toBeTruthy();
  });

  it('shows why suggestions could not be loaded', async () => {
    vi.stubGlobal('fetch', vi.fn(async () => json(502, { error: 'Jira recusou o e-mail ou o API token' })));
    renderBulk();
    const dialog = await openReview();
    expect(within(dialog).getByRole('alert').textContent).toBe(
      'Não foi possível sugerir as datas: Jira recusou o e-mail ou o API token',
    );
  });

  it('starts over after closing', async () => {
    stubServer(json(200, { ok: true, results: [{ key: 'TT-1', outcome: 'written' }, { key: 'TT-2', outcome: 'written' }] }));
    renderBulk();
    let dialog = await openReview();
    fireEvent.click(within(dialog).getByRole('button', { name: 'Gravar 2 datas' }));
    await within(dialog).findAllByText('gravada ✓');
    fireEvent.click(within(dialog).getByRole('button', { name: 'Fechar' }));
    expect(screen.queryByRole('dialog')).toBeNull();
    dialog = await openReview();
    expect(within(dialog).queryByText('gravada ✓')).toBeNull();
    expect(within(dialog).getByRole('button', { name: 'Gravar 2 datas' })).toBeTruthy();
  });
});
