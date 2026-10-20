import { afterEach, describe, expect, it, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { IssueActions } from '@/components/jira/IssueActions';
import { JiraActionsProvider } from '@/components/jira/actions/context';
import type { JiraItem } from '@/lib/types';

const ISSUE: JiraItem = {
  key: 'TT-123',
  summary: 'Liberar acesso ao ambiente',
  status: 'Em Andamento',
  statusCategory: 'indeterminate',
  project: 'TT',
  url: 'https://acme.atlassian.net/browse/TT-123',
  parent: null,
  role: 'assignee',
  awaitingApproval: false,
  kind: 'História',
  subtask: false,
  hierarchyLevel: 0,
  updatedAt: '2026-10-20T10:00:00.000Z',
  dueDate: '',
  impediment: 'none',
};

function json(status: number, body: unknown) {
  return { ok: status >= 200 && status < 300, status, json: async () => body };
}

function stubFetch(...responses: unknown[]) {
  const fetchMock = vi.fn();
  for (const r of responses) fetchMock.mockResolvedValueOnce(r);
  vi.stubGlobal('fetch', fetchMock);
  return fetchMock;
}

async function openDialog(onChanged = vi.fn()) {
  render(
    <JiraActionsProvider value={{ viewer: { kind: 'self' }, onChanged }}>
      <IssueActions issue={ISSUE} />
    </JiraActionsProvider>,
  );
  fireEvent.pointerDown(screen.getByRole('button', { name: 'ações de TT-123' }), {
    button: 0,
    ctrlKey: false,
    pointerType: 'mouse',
  });
  fireEvent.click(await screen.findByRole('menuitem', { name: 'Comentar' }));
  await screen.findByRole('dialog', { name: 'Comentar em TT-123' });
  return onChanged;
}

function textbox() {
  return screen.getByRole('textbox', { name: 'comentário em TT-123' });
}

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
});

describe('CommentDialog', () => {
  it('shows the issue, the summary and who the comment will appear as', async () => {
    await openDialog();
    const dialog = screen.getByRole('dialog');
    expect(dialog).toHaveTextContent('Liberar acesso ao ambiente');
    expect(dialog).toHaveTextContent('vai aparecer como seu comentário em TT-123');
  });

  it('keeps "Comentar" disabled while the text is blank', async () => {
    await openDialog();
    fireEvent.change(textbox(), { target: { value: '   \n ' } });
    expect(screen.getByRole('button', { name: 'Comentar' })).toBeDisabled();
  });

  it('refuses text longer than 5000 characters without calling the server', async () => {
    const fetchMock = stubFetch();
    await openDialog();
    fireEvent.change(textbox(), { target: { value: 'a'.repeat(5001) } });
    expect(screen.getByRole('alert')).toHaveTextContent('passou de 5000 caracteres');
    expect(screen.getByRole('button', { name: 'Comentar' })).toBeDisabled();
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it('posts the trimmed text, reports success with a link and refreshes', async () => {
    const fetchMock = stubFetch(json(200, { ok: true, comment: { id: '10000' } }));
    const onChanged = await openDialog();

    fireEvent.change(textbox(), { target: { value: '  pronto para revisão  ' } });
    fireEvent.click(screen.getByRole('button', { name: 'Comentar' }));

    expect(await screen.findByRole('status')).toHaveTextContent('comentário publicado');
    expect(screen.getByRole('link', { name: 'abrir TT-123 no Jira' })).toHaveAttribute('href', ISSUE.url);
    expect(onChanged).toHaveBeenCalledOnce();
    const [url, init] = fetchMock.mock.calls[0];
    expect(url).toBe('/api/jira/issues/TT-123/comments');
    expect(init.method).toBe('POST');
    expect(JSON.parse(init.body)).toEqual({ body: 'pronto para revisão' });
  });

  it('submits with Ctrl+Enter', async () => {
    const fetchMock = stubFetch(json(200, { ok: true, comment: { id: '10000' } }));
    await openDialog();
    fireEvent.change(textbox(), { target: { value: 'oi' } });
    fireEvent.keyDown(textbox(), { key: 'Enter', ctrlKey: true });
    await screen.findByRole('status');
    expect(fetchMock).toHaveBeenCalledOnce();
  });

  it('disables the controls while the request runs', async () => {
    let answer: (value: unknown) => void = () => {};
    vi.stubGlobal('fetch', vi.fn().mockReturnValue(new Promise((resolve) => (answer = resolve))));
    await openDialog();
    fireEvent.change(textbox(), { target: { value: 'oi' } });
    fireEvent.click(screen.getByRole('button', { name: 'Comentar' }));

    expect(await screen.findByRole('button', { name: 'Comentando…' })).toBeDisabled();
    expect(screen.getByRole('button', { name: 'Cancelar' })).toBeDisabled();
    answer(json(200, { ok: true, comment: { id: '10000' } }));
    await screen.findByRole('status');
  });

  it("shows Jira's refusal under the text and keeps what was typed", async () => {
    stubFetch(json(502, { error: 'Jira respondeu 400: comment: Comment body can not be empty!' }));
    const onChanged = await openDialog();
    fireEvent.change(textbox(), { target: { value: 'meu texto' } });
    fireEvent.click(screen.getByRole('button', { name: 'Comentar' }));

    expect(await screen.findByRole('alert')).toHaveTextContent('Comment body can not be empty!');
    expect(textbox()).toHaveValue('meu texto');
    expect(onChanged).not.toHaveBeenCalled();
  });

  it('fails visibly when the server answers without the comment id', async () => {
    stubFetch(json(200, { ok: true }));
    const onChanged = await openDialog();
    fireEvent.change(textbox(), { target: { value: 'oi' } });
    fireEvent.click(screen.getByRole('button', { name: 'Comentar' }));

    expect(await screen.findByRole('alert')).toHaveTextContent('resposta inesperada do servidor');
    expect(onChanged).not.toHaveBeenCalled();
  });

  it('closes on "Cancelar" without calling the server', async () => {
    const fetchMock = stubFetch();
    await openDialog();
    fireEvent.click(screen.getByRole('button', { name: 'Cancelar' }));
    await waitFor(() => expect(screen.queryByRole('dialog')).not.toBeInTheDocument());
    expect(fetchMock).not.toHaveBeenCalled();
  });
});
