import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const toast = vi.hoisted(() => ({ error: vi.fn() }));
vi.mock('sonner', () => ({ toast }));

import { persistAppearance } from '@/lib/appearanceClient';

beforeEach(() => {
  toast.error.mockClear();
});

afterEach(() => {
  vi.unstubAllGlobals();
});

describe('persistAppearance', () => {
  it('sends the patch to the account', async () => {
    const fetchMock = vi.fn(() => Promise.resolve(new Response('{}', { status: 200 })));
    vi.stubGlobal('fetch', fetchMock);

    persistAppearance({ width: 'limited' });
    await vi.waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(1));

    const [url, init] = fetchMock.mock.calls[0] as unknown as [string, RequestInit];
    expect(url).toBe('/api/preferences');
    expect(init.method).toBe('PATCH');
    expect(JSON.parse(String(init.body))).toEqual({ appearance: { width: 'limited' } });
    expect(toast.error).not.toHaveBeenCalled();
  });

  it('says so when the server refuses, with the reason', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn(() =>
        Promise.resolve(
          new Response(JSON.stringify({ error: 'aparência inválida' }), { status: 400 }),
        ),
      ),
    );

    persistAppearance({ theme: 'dark' });

    await vi.waitFor(() => expect(toast.error).toHaveBeenCalledTimes(1));
    expect(toast.error.mock.calls[0][0]).toContain('aparência inválida');
    expect(toast.error.mock.calls[0][0]).toContain('Vale só neste navegador');
  });

  it('says so when the network fails', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn(() => Promise.reject(new Error('Failed to fetch'))),
    );

    persistAppearance({ density: 'compact' });

    await vi.waitFor(() => expect(toast.error).toHaveBeenCalledTimes(1));
    expect(toast.error.mock.calls[0][0]).toContain('Failed to fetch');
  });
});
