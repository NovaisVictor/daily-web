import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import { AgentBoard } from '@/components/agents/AgentBoard';
import { AccessPanel } from '@/components/agents/AccessPanel';
import { parseSnapshot, parseTaskDetail } from '@/components/agents/contracts';
import captured from '@/tests/fixtures/agents/browser-contract.json';

const navigation = vi.hoisted(() => ({ params: new URLSearchParams(), replace: vi.fn(), push: vi.fn() }));
vi.mock('next/navigation', () => ({ useSearchParams: () => navigation.params, usePathname: () => '/', useRouter: () => navigation }));
const now = new Date().toISOString();
const task = { ...captured.snapshot.tasks.items[0], id: 'task-1', externalId: 'external-1', title: 'Revisar autenticação', description: 'Validar permissões', status: 'working', assignment: { ...captured.snapshot.tasks.items[0].assignment, agentId: 'a1', sessionId: 's1', provider: 'claude', displayName: 'Claude do projeto', freshness: 'disconnected' }, createdAt: now, lastActivityAt: now };
const snapshot = { tasks: { items: [task], nextCursor: null, complete: true }, sessions: { items: [], nextCursor: null, complete: true } };
const response = (value: unknown, status = 200) => new Response(status === 204 ? null : JSON.stringify(value), { status, headers: { 'Content-Type': 'application/json' } });

beforeEach(() => { navigation.params = new URLSearchParams(); navigation.replace.mockClear(); vi.stubGlobal('fetch', vi.fn()); });
afterEach(() => { cleanup(); vi.unstubAllGlobals(); });

describe('agent workspace', () => {
  it('accepts the captured running-service snapshot and detail contracts', () => {
    expect(parseSnapshot(captured.snapshot).tasks.items).toHaveLength(2);
    expect(parseTaskDetail(captured.detail).task.status).toBe('working');
  });
  it('keeps disconnected work in its lifecycle column and links the task detail', async () => {
    vi.mocked(fetch).mockResolvedValue(response(snapshot));
    render(<AgentBoard />);
    const column = await screen.findByRole('region', { name: 'Em andamento' });
    expect(within(column).getByRole('link', { name: /Revisar autenticação/ })).toHaveAttribute('href', '/agents/tasks/task-1');
    expect(within(column).getByText('Sem contato há mais de 10 min')).toBeInTheDocument();
    expect(screen.queryByText('E-mail')).not.toBeInTheDocument();
  });
  it('reads the filter from the URL and writes a new URL when changed', async () => {
    navigation.params = new URLSearchParams('q=auth&status=working&cursor=old-page');
    vi.mocked(fetch).mockResolvedValue(response(snapshot));
    render(<AgentBoard />);
    expect(screen.getByRole('searchbox')).toHaveValue('auth');
    fireEvent.change(screen.getByRole('searchbox'), { target: { value: 'security' } });
    expect(navigation.replace).toHaveBeenCalledWith('/?q=security&status=working', { scroll: false });
  });
  it('has actionable empty and unavailable states', async () => {
    vi.mocked(fetch).mockResolvedValue(response({ ...snapshot, tasks: { ...snapshot.tasks, items: [] } }));
    const view = render(<AgentBoard />);
    expect(await screen.findByRole('link', { name: 'Configurar acesso' })).toHaveAttribute('href', '/access');
    view.unmount();
    vi.mocked(fetch).mockResolvedValue(response({}, 403));
    render(<AgentBoard />);
    expect(await screen.findByRole('alert')).toHaveTextContent('Não foi possível carregar os agentes');
  });
  it('rejects unknown statuses and providers instead of showing misleading cards', () => {
    expect(() => parseSnapshot({ ...snapshot, tasks: { ...snapshot.tasks, items: [{ ...task, status: 'mystery' }] } })).toThrow();
    expect(() => parseSnapshot({ ...snapshot, tasks: { ...snapshot.tasks, items: [{ ...task, assignment: { ...task.assignment, provider: 'unknown' } }] } })).toThrow();
  });
});

describe('access onboarding', () => {
  it('shows a newly issued secret only until dismissal and keeps it out of the prompt and listing', async () => {
    const credential = { id: 'c1', label: 'Notebook', prefix: 'dwp_public', scopes: ['agents:read', 'agents:write'], state: 'active', createdAt: now, lastUsedAt: null };
    let created = false;
    vi.mocked(fetch).mockImplementation(async (url, init) => {
      if (String(url).endsWith('/config')) return response({ mcpUrl: 'https://daily.example/mcp' });
      if (String(url).endsWith('/prompt')) return response({ prompt: 'Use TOKEN_PLACEHOLDER via ambiente seguro.' });
      if (String(url).endsWith('/grants')) return response({ grants: [] });
      if (init?.method === 'POST') { created = true; return response({ credential, secret: 'dwp_super_private_once' }, 201); }
      return response({ items: created ? [credential] : [] });
    });
    render(<AccessPanel />);
    fireEvent.change(screen.getByRole('textbox', { name: 'Nome do acesso' }), { target: { value: 'Notebook' } });
    fireEvent.click(screen.getByRole('button', { name: 'Gerar token' }));
    expect(await screen.findByRole('textbox', { name: 'Token gerado, exibido uma única vez' })).toHaveValue('dwp_super_private_once');
    expect(screen.getByRole('textbox', { name: 'Instruções para o agente', hidden: true })).not.toHaveValue(expect.stringContaining('dwp_super_private_once'));
    fireEvent.click(screen.getByRole('button', { name: 'Já guardei o token' }));
    await waitFor(() => expect(screen.queryByRole('textbox', { name: 'Token gerado, exibido uma única vez' })).not.toBeInTheDocument());
    expect(screen.getByText(/dwp_public/)).toBeInTheDocument();
    expect(screen.queryByDisplayValue('dwp_super_private_once')).not.toBeInTheDocument();
  });
  it('revokes a named OAuth grant only after confirmation', async () => {
    const calls: string[] = [];
    vi.mocked(fetch).mockImplementation(async (url, init) => {
      if (init?.method === 'DELETE') { calls.push(String(url)); return response({ ok: true }); }
      if (String(url).endsWith('/config')) return response({ mcpUrl: 'https://daily.example/mcp' });
      if (String(url).endsWith('/prompt')) return response({ prompt: 'Use TOKEN_PLACEHOLDER.' });
      if (String(url).endsWith('/grants')) return response({ grants: [{ id: 'g1', clientId: 'client-1', clientName: 'Codex', scopes: ['agents:read'], expiresAt: null }] });
      return response({ items: [] });
    });
    render(<AccessPanel />);
    fireEvent.click(await screen.findByRole('button', { name: 'Revogar Codex' }));
    expect(calls).toHaveLength(0);
    fireEvent.click(screen.getByRole('button', { name: 'Revogar autorização' }));
    await waitFor(() => expect(calls).toEqual(['/api/agent-access/grants/g1']));
  });
});
