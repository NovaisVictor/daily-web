import { afterEach, describe, expect, it, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, within } from '@testing-library/react';
import { Header } from '@/components/shell/Header';
import { DashboardStateProvider } from '@/lib/hooks/DashboardStateProvider';

vi.mock('next/navigation', () => ({
  usePathname: () => '/kanban',
  useRouter: () => ({ push: vi.fn() }),
}));

vi.stubGlobal(
  'fetch',
  vi.fn(() => Promise.resolve({ ok: false })),
);

afterEach(cleanup);

function header() {
  return (
    <DashboardStateProvider>
      <Header username="ana" onShowChangelog={() => {}} />
    </DashboardStateProvider>
  );
}

describe('Header navigation', () => {
  it('links Início, Kanban and Ferramentas, and no longer Agentes', () => {
    render(header());

    const nav = screen.getByRole('navigation', { name: 'Principal' });
    const labels = within(nav)
      .getAllByRole('link')
      .map((link) => link.getAttribute('aria-label'));
    expect(labels).toEqual(['Início', 'Kanban', 'Ferramentas']);
    expect(within(nav).queryByRole('link', { name: 'Agentes' })).toBeNull();
  });

  it('marks the current page', () => {
    render(header());

    const nav = screen.getByRole('navigation', { name: 'Principal' });
    expect(within(nav).getByRole('link', { name: 'Kanban' })).toHaveAttribute(
      'aria-current',
      'page',
    );
  });

  it('has "Conectar agente" in the avatar menu, pointing at the access page', async () => {
    render(header());

    fireEvent.keyDown(screen.getByRole('button', { name: 'ana' }), { key: 'Enter' });

    const item = await screen.findByRole('menuitem', { name: 'Conectar agente' });
    expect(item).toHaveAttribute('href', '/access');
  });
});
