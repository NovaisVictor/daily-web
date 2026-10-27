import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, within } from '@testing-library/react';
import { ChangelogDialog, useChangelog } from '@/components/shell/ChangelogDialog';
import { AppShell } from '@/components/shell/AppShell';
import { RELEASES, type Release } from '@/lib/changelog';

vi.mock('next/navigation', () => ({
  usePathname: () => '/',
  useRouter: () => ({ push: vi.fn() }),
}));

// The header's notification bell polls /api/state; jsdom has no origin to resolve it against.
vi.stubGlobal('fetch', vi.fn(() => Promise.resolve({ ok: false })));

const KEY = 'daily-web:changelog-seen';

const releases: Release[] = [
  {
    id: 'new',
    date: '2026-11-02',
    title: 'Lançamento novo',
    items: [{ title: 'Coisa nova', detail: 'Faz algo novo.' }],
  },
  {
    id: 'old',
    date: '2026-10-20',
    title: 'Lançamento antigo',
    items: [{ title: 'Coisa antiga', detail: 'Faz algo antigo.' }],
  },
];

function Harness({ list = releases }: { list?: Release[] }) {
  const changelog = useChangelog(list);
  return <ChangelogDialog shown={changelog.shown} dismiss={changelog.dismiss} />;
}

describe('ChangelogDialog', () => {
  beforeEach(() => localStorage.clear());
  afterEach(() => {
    cleanup();
    vi.restoreAllMocks();
  });

  it('opens on the first visit with every release listed', async () => {
    render(<Harness />);

    const dialog = await screen.findByRole('dialog', { name: 'Novidades' });
    expect(dialog).toHaveAccessibleDescription(/O que mudou/);
    expect(within(dialog).getByText('Lançamento novo')).toBeInTheDocument();
    expect(within(dialog).getByText('Lançamento antigo')).toBeInTheDocument();
    expect(within(dialog).getAllByRole('list')[0]).toBeInTheDocument();
    expect(within(dialog).getByText('02/11/2026')).toBeInTheDocument();
  });

  it('stores the newest id on "Continuar" and stays closed on the next load', async () => {
    const { unmount } = render(<Harness />);
    fireEvent.click(await screen.findByRole('button', { name: 'Continuar' }));

    expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
    expect(localStorage.getItem(KEY)).toBe('new');

    unmount();
    render(<Harness />);
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
  });

  it('counts closing with Escape as seen, so it does not nag on every load', async () => {
    render(<Harness />);
    fireEvent.keyDown(await screen.findByRole('dialog'), { key: 'Escape' });

    expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
    expect(localStorage.getItem(KEY)).toBe('new');
  });

  it('counts closing with the X button as seen', async () => {
    render(<Harness />);
    fireEvent.click(await screen.findByRole('button', { name: 'Close' }));

    expect(localStorage.getItem(KEY)).toBe('new');
  });

  it('stays closed when the newest release was already seen', () => {
    localStorage.setItem(KEY, 'new');
    render(<Harness />);

    expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
  });

  it('lists only the releases newer than the one seen', async () => {
    localStorage.setItem(KEY, 'old');
    render(<Harness />);

    const dialog = await screen.findByRole('dialog', { name: 'Novidades' });
    expect(within(dialog).getByText('Lançamento novo')).toBeInTheDocument();
    expect(within(dialog).queryByText('Lançamento antigo')).not.toBeInTheDocument();
  });

  it('still opens and closes when storage refuses access', async () => {
    vi.spyOn(Storage.prototype, 'getItem').mockImplementation(() => {
      throw new Error('blocked');
    });
    vi.spyOn(Storage.prototype, 'setItem').mockImplementation(() => {
      throw new Error('blocked');
    });
    render(<Harness />);

    fireEvent.click(await screen.findByRole('button', { name: 'Continuar' }));
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
  });

  it('reopens the latest release from the account menu after it was seen', async () => {
    localStorage.setItem(KEY, RELEASES[0].id);
    render(
      <AppShell theme="system" density="comfortable" backdrop="mesh" username="ana" avatarUrl={null} greetingName="ana" welcome="first">
        <p>conteúdo</p>
      </AppShell>,
    );
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument();

    fireEvent.keyDown(screen.getAllByRole('button', { name: /ana/ })[0], { key: 'Enter' });
    fireEvent.click(await screen.findByRole('menuitem', { name: 'Novidades' }));

    const dialog = await screen.findByRole('dialog', { name: 'Novidades' });
    expect(within(dialog).getByText(RELEASES[0].title)).toBeInTheDocument();
  });
});
