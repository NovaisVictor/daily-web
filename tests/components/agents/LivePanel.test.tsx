import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { LivePanel } from '@/components/agents/LivePanel';

const navigation = vi.hoisted(() => ({ params: new URLSearchParams(), replace: vi.fn() }));
vi.mock('next/navigation', () => ({ useSearchParams: () => navigation.params, usePathname: () => '/agents/tasks/t', useRouter: () => navigation }));
const json = (value: unknown, status = 200) => new Response(JSON.stringify(value), { status, headers: { 'Content-Type': 'application/json' } });
const terminal = { available: true, live: { state: 'background', since: new Date().toISOString() }, pane: '❯ npm test\n✓ 51 passed', response: { content: 'Build rodando.', at: '2026-10-24T06:12:08.305Z' }, capturedAt: new Date().toISOString() };

beforeEach(() => { navigation.params = new URLSearchParams(); navigation.replace.mockClear(); vi.stubGlobal('fetch', vi.fn()); });
afterEach(() => { cleanup(); vi.unstubAllGlobals(); });

describe('live session panel', () => {
  it('shows the live state and terminal, and switches to the last response through the URL', async () => {
    vi.mocked(fetch).mockResolvedValue(json(terminal));
    render(<LivePanel sessionId="s1" />);
    expect(await screen.findByText(/51 passed/)).toBeTruthy();
    expect(screen.getByText('Rodando em segundo plano')).toBeTruthy();
    fireEvent.click(screen.getByRole('button', { name: 'Última resposta' }));
    expect(navigation.replace).toHaveBeenCalledWith('/agents/tasks/t?live=response', { scroll: false });
  });
  it('explains when the session runs elsewhere and offers no reply box', async () => {
    vi.mocked(fetch).mockResolvedValue(json({ available: false, reason: 'not_local' }));
    render(<LivePanel sessionId="s1" />);
    expect(await screen.findByText(/não roda no agent-deck deste servidor/)).toBeTruthy();
    expect(screen.queryByRole('textbox')).toBeNull();
  });
  it('sends a reply with a stable idempotency key and clears it after delivery', async () => {
    vi.mocked(fetch).mockImplementation(async (url, init) => String(url).endsWith('/messages') ? json({ ok: true, id: 'send-1', state: 'queued' }, 202) : json(terminal));
    render(<LivePanel sessionId="s1" />);
    const box = await screen.findByRole('textbox', { name: 'Responder ao agente' });
    fireEvent.change(box, { target: { value: 'pode seguir' } });
    fireEvent.keyDown(box, { key: 'Enter', ctrlKey: true });
    await screen.findByText(/Mensagem na fila/);
    const call = vi.mocked(fetch).mock.calls.find(([url]) => String(url).endsWith('/messages'))!;
    expect(call[0]).toBe('/api/agents/sessions/s1/messages');
    expect(JSON.parse(String(call[1]?.body))).toEqual({ text: 'pode seguir' });
    expect((call[1]?.headers as Record<string, string>)['Idempotency-Key']).toMatch(/^[0-9a-f-]{36}$/);
    expect((box as HTMLTextAreaElement).value).toBe('');
  });
  it('keeps the draft and explains an uncertain delivery', async () => {
    vi.mocked(fetch).mockImplementation(async url => String(url).endsWith('/messages') ? json({ error: { code: 'uncertain_outcome' } }, 409) : json(terminal));
    render(<LivePanel sessionId="s1" />);
    const box = await screen.findByRole('textbox', { name: 'Responder ao agente' });
    fireEvent.change(box, { target: { value: 'pode seguir' } });
    fireEvent.click(screen.getByRole('button', { name: 'Enviar' }));
    await waitFor(() => expect(screen.getByText(/Confira o terminal antes de reenviar/)).toBeTruthy());
    expect((box as HTMLTextAreaElement).value).toBe('pode seguir');
  });
});
