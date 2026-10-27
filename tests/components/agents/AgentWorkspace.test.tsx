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

// The filters live in a dropdown behind the "Filtros" icon.
const openFilters = () => fireEvent.keyDown(screen.getByRole('button', { name: 'Filtros' }), { key: 'Enter' });

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
    fireEvent.click(screen.getByRole('button', { name: 'Buscar tarefas' }));
    const search = await screen.findByRole('searchbox');
    expect(search).toHaveValue('auth');
    fireEvent.change(search, { target: { value: 'security' } });
    await waitFor(() =>
      expect(navigation.replace).toHaveBeenCalledWith('/?q=security&status=working', { scroll: false }),
    );
  });
  it('loads the last 3 days by default and keeps the chosen window in the URL', async () => {
    vi.mocked(fetch).mockResolvedValue(response(snapshot));
    render(<AgentBoard />);
    await waitFor(() => expect(vi.mocked(fetch).mock.calls.some(([url]) => String(url).includes('days=3'))).toBe(true));
    openFilters();
    expect(await screen.findByRole('menuitemradio', { name: 'Últimos 3 dias' })).toBeChecked();
    fireEvent.click(screen.getByRole('menuitemradio', { name: 'Últimos 15 dias' }));
    expect(navigation.replace).toHaveBeenCalledWith('/?days=15', { scroll: false });
  });
  it('falls back to the default window for an unknown days value', async () => {
    navigation.params = new URLSearchParams('days=90');
    vi.mocked(fetch).mockResolvedValue(response(snapshot));
    render(<AgentBoard />);
    openFilters();
    expect(await screen.findByRole('menuitemradio', { name: 'Últimos 3 dias' })).toBeChecked();
    await waitFor(() => expect(vi.mocked(fetch).mock.calls.every(([url]) => !String(url).includes('days=90'))).toBe(true));
  });
  it('keeps finished work in a collapsed summary that opens through the URL and still flags failures', async () => {
    const finished = (id: string, status: string) => ({ ...task, id, externalId: id, title: `Tarefa ${id}`, status });
    vi.mocked(fetch).mockImplementation(async () => response({ ...snapshot, tasks: { items: [task, finished('c1', 'completed'), finished('c2', 'completed'), finished('f1', 'failed'), finished('x1', 'cancelled')], nextCursor: null, complete: true } }));
    const view = render(<AgentBoard />);
    const strip = await screen.findByRole('button', { name: /Finalizadas/ });
    expect(strip).toHaveAttribute('aria-expanded', 'false');
    expect(strip).toHaveTextContent('2 concluídas');
    expect(strip).toHaveTextContent('1 falhou');
    expect(strip).toHaveTextContent('1 cancelada');
    expect(within(strip).getByText(/1 falhou/)).toHaveClass('text-danger');
    expect(strip).toHaveClass('border-danger/60');
    expect(screen.queryByRole('region', { name: 'Concluídas' })).toBeNull();
    expect(screen.getByRole('region', { name: 'Em andamento' })).toBeInTheDocument();
    fireEvent.click(strip);
    expect(navigation.replace).toHaveBeenCalledWith('/?finished=show', { scroll: false });
    view.unmount();
    navigation.params = new URLSearchParams('finished=show');
    render(<AgentBoard />);
    expect(await screen.findByRole('button', { name: /Finalizadas/ })).toHaveAttribute('aria-expanded', 'true');
    expect(screen.getByRole('region', { name: 'Concluídas' })).toHaveTextContent('Tarefa c1');
    expect(screen.getByRole('region', { name: 'Falharam' })).toHaveTextContent('Tarefa f1');
  });
  it('summarises finished work with the server totals for the whole period, not just the loaded page', async () => {
    const statusCounts = { queued: 0, working: 1, waiting: 0, blocked: 0, completed: 140, failed: 2, cancelled: 0 };
    vi.mocked(fetch).mockImplementation(async () => response({ ...snapshot, statusCounts }));
    render(<AgentBoard />);
    const strip = await screen.findByRole('button', { name: /Finalizadas/ });
    expect(strip).toHaveTextContent('140 concluídas');
    expect(strip).toHaveTextContent('2 falharam');
    expect(strip).not.toHaveTextContent('cancelada');
  });
  it('rejects malformed status totals instead of showing misleading counts', () => {
    expect(() => parseSnapshot({ ...snapshot, statusCounts: { completed: -1 } })).toThrow();
    expect(() => parseSnapshot({ ...snapshot, statusCounts: { archived: 1 } })).toThrow();
  });
  it('shows a finished column directly when it is chosen in the status filter, and a quiet strip when nothing finished', async () => {
    navigation.params = new URLSearchParams('status=completed');
    vi.mocked(fetch).mockImplementation(async () => response({ ...snapshot, tasks: { items: [{ ...task, status: 'completed' }], nextCursor: null, complete: true } }));
    const view = render(<AgentBoard />);
    expect(await screen.findByRole('region', { name: 'Concluídas' })).toHaveTextContent('Revisar autenticação');
    expect(screen.queryByRole('button', { name: /Finalizadas/ })).toBeNull();
    view.unmount();
    navigation.params = new URLSearchParams();
    vi.mocked(fetch).mockImplementation(async () => response(snapshot));
    render(<AgentBoard />);
    const strip = await screen.findByRole('button', { name: /Finalizadas/ });
    expect(strip).toBeDisabled();
    expect(strip).toHaveTextContent('nenhuma neste período');
  });
  it('keeps Atualizar, search and filters side by side on the right, with no filter bar', async () => {
    vi.mocked(fetch).mockResolvedValue(response(snapshot));
    render(<AgentBoard />);

    const refresh = screen.getByRole('button', { name: 'Atualizar agentes' });
    const search = screen.getByRole('button', { name: 'Buscar tarefas' });
    const filters = screen.getByRole('button', { name: 'Filtros' });
    const group = refresh.parentElement as HTMLElement;
    expect(group).toContainElement(search);
    expect(group).toContainElement(filters);
    expect(screen.queryByPlaceholderText('Buscar tarefa…')).toBeNull();
    expect(screen.queryByRole('combobox')).toBeNull();
  });

  it('no longer prints the task count or the activity window under the header', async () => {
    vi.mocked(fetch).mockResolvedValue(response(snapshot));
    render(<AgentBoard />);
    await screen.findByRole('region', { name: 'Em andamento' });

    expect(screen.queryByText(/nesta página/)).toBeNull();
    expect(screen.queryByText(/histórico guardado por 30 dias/)).toBeNull();
  });

  it('prints no end-of-list text, and no pagination row when there is nothing to page', async () => {
    vi.mocked(fetch).mockResolvedValue(response(snapshot));
    render(<AgentBoard />);
    await screen.findByRole('region', { name: 'Em andamento' });

    expect(screen.queryByText(/Fim dos resultados/)).toBeNull();
    expect(screen.queryByRole('button', { name: 'Próxima página' })).toBeNull();
    expect(screen.queryByRole('button', { name: 'Primeira página' })).toBeNull();
  });

  it('keeps the pagination row when another page exists', async () => {
    vi.mocked(fetch).mockResolvedValue(
      response({ ...snapshot, tasks: { ...snapshot.tasks, nextCursor: 'page-2' } }),
    );
    render(<AgentBoard />);

    expect(await screen.findByText(/Mais resultados disponíveis/)).toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: 'Próxima página' }));
    expect(navigation.replace).toHaveBeenLastCalledWith('/?cursor=page-2', { scroll: false });
  });

  it('keeps a way back to the first page on the last page, without any end text', async () => {
    navigation.params = new URLSearchParams('cursor=page-2');
    vi.mocked(fetch).mockResolvedValue(response(snapshot));
    render(<AgentBoard />);

    expect(await screen.findByRole('button', { name: 'Primeira página' })).toBeInTheDocument();
    expect(screen.queryByText(/Fim dos resultados/)).toBeNull();
    expect(screen.queryByRole('button', { name: 'Próxima página' })).toBeNull();
  });

  it('offers status, period and order in the filter dropdown and writes them to the URL', async () => {
    vi.mocked(fetch).mockResolvedValue(response(snapshot));
    render(<AgentBoard />);
    openFilters();

    fireEvent.click(await screen.findByRole('menuitemradio', { name: 'Em andamento' }));
    expect(navigation.replace).toHaveBeenLastCalledWith('/?status=working', { scroll: false });
    fireEvent.click(screen.getByRole('menuitemradio', { name: 'Atividade mais antiga' }));
    expect(navigation.replace).toHaveBeenLastCalledWith('/?sort=oldest', { scroll: false });
    expect(screen.getByRole('menuitemradio', { name: 'Todos' })).toBeInTheDocument();
  });

  it('clears the status with "Todos"', async () => {
    navigation.params = new URLSearchParams('status=working&days=15');
    vi.mocked(fetch).mockResolvedValue(response(snapshot));
    render(<AgentBoard />);
    openFilters();

    expect(await screen.findByRole('menuitemradio', { name: 'Em andamento' })).toBeChecked();
    fireEvent.click(screen.getByRole('menuitemradio', { name: 'Todos' }));
    expect(navigation.replace).toHaveBeenLastCalledWith('/?days=15', { scroll: false });
  });

  it('counts the filters that differ from the default on the filter icon', async () => {
    navigation.params = new URLSearchParams('status=working&days=15&sort=oldest');
    vi.mocked(fetch).mockResolvedValue(response(snapshot));
    render(<AgentBoard />);

    expect(screen.getByRole('button', { name: 'Filtros' }).parentElement).toHaveTextContent('3');
  });

  it('shows no count on a board with the default filters', async () => {
    vi.mocked(fetch).mockResolvedValue(response(snapshot));
    render(<AgentBoard />);

    expect(screen.getByRole('button', { name: 'Filtros' }).parentElement).not.toHaveTextContent(/\d/);
  });

  it('offers to clear the session filter from the dropdown', async () => {
    navigation.params = new URLSearchParams('sessionId=s1');
    vi.mocked(fetch).mockResolvedValue(response(snapshot));
    render(<AgentBoard />);
    openFilters();

    fireEvent.click(await screen.findByRole('menuitem', { name: 'Limpar sessão' }));
    expect(navigation.replace).toHaveBeenLastCalledWith('/', { scroll: false });
  });

  // The URL answers a keystroke late; the field must not hand back the old text meanwhile.
  it('keeps what is typed while the URL catches up, and writes it once, after a pause', async () => {
    vi.mocked(fetch).mockResolvedValue(response(snapshot));
    render(<AgentBoard />);
    fireEvent.click(screen.getByRole('button', { name: 'Buscar tarefas' }));
    const search = await screen.findByRole('searchbox');

    for (const text of ['l', 'lo', 'log', 'logi', 'login']) fireEvent.change(search, { target: { value: text } });

    expect(search).toHaveValue('login');
    expect(navigation.replace).not.toHaveBeenCalled();
    await waitFor(() => expect(navigation.replace).toHaveBeenCalledTimes(1));
    expect(navigation.replace).toHaveBeenCalledWith('/?q=login', { scroll: false });
  });

  it('follows the URL when the search is cleared from outside', async () => {
    navigation.params = new URLSearchParams('q=auth');
    vi.mocked(fetch).mockResolvedValue(response(snapshot));
    const { rerender } = render(<AgentBoard />);
    fireEvent.click(screen.getByRole('button', { name: 'Buscar tarefas' }));
    expect(await screen.findByRole('searchbox')).toHaveValue('auth');

    navigation.params = new URLSearchParams('');
    rerender(<AgentBoard />);

    expect(screen.getByRole('searchbox')).toHaveValue('');
  });

  it('flags an active search on the search icon without opening it', async () => {
    navigation.params = new URLSearchParams('q=auth');
    vi.mocked(fetch).mockResolvedValue(response(snapshot));
    const { container } = render(<AgentBoard />);

    const wrapper = screen.getByRole('button', { name: 'Buscar tarefas' }).parentElement as HTMLElement;
    expect(wrapper.querySelector('.bg-brand')).not.toBeNull();
    expect(container.querySelector('input[type="search"]')).toBeNull();
  });

  it('has no "Conectar agente" button in its header: that lives in the avatar menu', async () => {
    vi.mocked(fetch).mockResolvedValue(response(snapshot));
    render(<AgentBoard />);
    await screen.findByRole('region', { name: 'Em andamento' });

    expect(screen.queryByRole('link', { name: 'Conectar agente' })).toBeNull();
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
