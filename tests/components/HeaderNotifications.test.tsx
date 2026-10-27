import { afterEach, describe, expect, it, vi } from 'vitest';
import { cleanup, fireEvent, render, screen } from '@testing-library/react';
import { HeaderNotifications } from '@/components/shell/HeaderNotifications';
import { DashboardStateProvider } from '@/lib/hooks/DashboardStateProvider';

vi.stubGlobal(
  'fetch',
  vi.fn(() => Promise.resolve({ ok: false })),
);

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
  vi.stubGlobal(
    'fetch',
    vi.fn(() => Promise.resolve({ ok: false })),
  );
  localStorage.clear();
});

describe('HeaderNotifications', () => {
  // The dashboard page's own bell is gone, so this is the only place the desktop alerts can be
  // switched on.
  it('offers the desktop alerts in the bell', () => {
    vi.stubGlobal(
      'Notification',
      Object.assign(vi.fn(), { permission: 'default', requestPermission: vi.fn() }),
    );
    render(
      <DashboardStateProvider>
        <HeaderNotifications />
      </DashboardStateProvider>,
    );

    fireEvent.click(screen.getByRole('button', { name: /notificações/ }));

    expect(screen.getByRole('button', { name: 'Avisar no computador' })).toBeInTheDocument();
  });

  it('has exactly one bell, next to the refresh button', () => {
    render(
      <DashboardStateProvider>
        <HeaderNotifications />
      </DashboardStateProvider>,
    );

    expect(screen.getAllByRole('button', { name: /notificações/ })).toHaveLength(1);
    expect(screen.getByRole('button', { name: 'Atualizar agora' })).toBeInTheDocument();
  });
});
