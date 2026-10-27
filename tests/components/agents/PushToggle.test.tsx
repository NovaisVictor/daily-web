import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { cleanup, fireEvent, render, screen } from '@testing-library/react';
import { PushToggle } from '@/components/agents/PushToggle';

const json = (value: unknown, status = 200) => new Response(JSON.stringify(value), { status, headers: { 'Content-Type': 'application/json' } });
const subscription = { endpoint: 'https://fcm.googleapis.com/fcm/send/device-1', toJSON: () => ({ endpoint: 'https://fcm.googleapis.com/fcm/send/device-1', keys: { p256dh: 'p', auth: 'a' } }), unsubscribe: vi.fn(async () => true) };
const manager = { getSubscription: vi.fn(), subscribe: vi.fn() };

beforeEach(() => {
  vi.stubGlobal('fetch', vi.fn(async (url: string) => url === '/api/push' ? json({ publicKey: 'BAAA_-w' }) : url === '/api/push/test' ? json({ devices: 1 }, 202) : json({ id: 's' }, 201)));
  vi.stubGlobal('PushManager', function PushManager() {});
  vi.stubGlobal('Notification', Object.assign(function Notification() {}, { permission: 'default', requestPermission: vi.fn(async () => 'granted') }));
  Object.defineProperty(navigator, 'serviceWorker', { configurable: true, value: { ready: Promise.resolve({ pushManager: manager }) } });
  manager.getSubscription.mockResolvedValue(null);
  manager.subscribe.mockResolvedValue(subscription);
  subscription.unsubscribe.mockClear();
});
afterEach(() => { cleanup(); vi.unstubAllGlobals(); delete (navigator as { serviceWorker?: unknown }).serviceWorker; });

describe('push toggle', () => {
  it('says nothing when the server has no push keys', async () => {
    vi.stubGlobal('fetch', vi.fn(async () => json({ publicKey: null })));
    const { container } = render(<PushToggle />);

    await vi.waitFor(() => expect(fetch).toHaveBeenCalled());
    await new Promise((resolve) => setTimeout(resolve, 20));
    expect(container.textContent).toBe('');
    expect(screen.queryByText(/configurados no servidor/)).toBeNull();
  });
  it('subscribes this device with the server key, then tests and disables it', async () => {
    render(<PushToggle />);
    fireEvent.click(await screen.findByRole('button', { name: /Ativar avisos/ }));
    expect(await screen.findByText('Avisos ativados neste dispositivo.')).toBeTruthy();
    expect(manager.subscribe).toHaveBeenCalledWith({ userVisibleOnly: true, applicationServerKey: new Uint8Array([4, 0, 0, 255, 236]) });
    const save = vi.mocked(fetch).mock.calls.find(([url, init]) => url === '/api/push/subscriptions' && init?.method === 'POST')!;
    expect(JSON.parse(String(save[1]?.body))).toEqual(subscription.toJSON());
    fireEvent.click(screen.getByRole('button', { name: /Testar aviso/ }));
    expect(await screen.findByText('Aviso de teste enviado.')).toBeTruthy();
    manager.getSubscription.mockResolvedValue(subscription);
    fireEvent.click(screen.getByRole('button', { name: 'Desativar avisos neste dispositivo' }));
    expect(await screen.findByText('Avisos desativados neste dispositivo.')).toBeTruthy();
    expect(subscription.unsubscribe).toHaveBeenCalled();
  });
  it('explains a blocked permission and an unsupported browser', async () => {
    vi.stubGlobal('Notification', Object.assign(function Notification() {}, { permission: 'denied', requestPermission: vi.fn() }));
    render(<PushToggle />);
    expect(await screen.findByText(/bloqueados nas permissões/)).toBeTruthy();
    cleanup();
    delete (navigator as { serviceWorker?: unknown }).serviceWorker;
    render(<PushToggle />);
    expect(await screen.findByText(/não recebe avisos/)).toBeTruthy();
  });
});
