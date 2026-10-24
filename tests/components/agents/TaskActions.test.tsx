import { afterEach, describe, expect, it, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { TaskActions } from '@/components/agents/TaskActions';
import type { AgentTask } from '@/lib/agents/model';

vi.mock('next/navigation', () => ({ useRouter: () => ({ push: vi.fn() }) }));
afterEach(() => { cleanup(); vi.unstubAllGlobals(); });

describe('task editing concurrency', () => {
  it('preserves the version present when editing started even if polling updates the task', async () => {
    const now = new Date().toISOString();
    const task: AgentTask = { id: 'task', parentTaskId: null, externalId: 'external', title: 'Original title', description: '', status: 'queued', assignment: null, source: null, version: 1, createdAt: now, lastActivityAt: now };
    const fetch = vi.fn().mockResolvedValue(new Response('{}', { status: 409 }));
    vi.stubGlobal('fetch', fetch);
    const view = render(<TaskActions task={task} onChanged={vi.fn()} />);
    fireEvent.click(screen.getByRole('button', { name: 'Editar' }));
    fireEvent.change(screen.getByRole('textbox', { name: 'Título' }), { target: { value: 'Local edit' } });
    view.rerender(<TaskActions task={{ ...task, version: 2, title: 'Remote edit' }} onChanged={vi.fn()} />);
    fireEvent.click(screen.getByRole('button', { name: 'Salvar alterações' }));
    await waitFor(() => expect(fetch).toHaveBeenCalledTimes(1));
    expect(JSON.parse(fetch.mock.calls[0][1].body)).toMatchObject({ expectedVersion: 1, title: 'Local edit' });
    expect(await screen.findByRole('alert')).toHaveTextContent('O item mudou');
  });
  it('offers completion for a cancelled task whose agent finished the work after losing its session', async () => {
    const now = new Date().toISOString();
    const task: AgentTask = { id: 'task', parentTaskId: null, externalId: 'external', title: 'Done offline', description: '', status: 'cancelled', assignment: null, source: null, version: 4, createdAt: now, lastActivityAt: now };
    const fetch = vi.fn().mockResolvedValue(new Response('{}', { status: 200, headers: { 'Content-Type': 'application/json' } }));
    vi.stubGlobal('fetch', fetch);
    const onChanged = vi.fn();
    render(<TaskActions task={task} onChanged={onChanged} />);
    expect(screen.getByRole('button', { name: 'Reabrir tarefa' })).toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: 'Concluir' }));
    await waitFor(() => expect(onChanged).toHaveBeenCalled());
    expect(String(fetch.mock.calls[0][0])).toBe('/api/agents/tasks/task/transitions');
    expect(JSON.parse(fetch.mock.calls[0][1].body)).toEqual({ status: 'completed', expectedVersion: 4 });
  });
});
