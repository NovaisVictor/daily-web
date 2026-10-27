import { afterEach, describe, expect, it, vi } from 'vitest';
import { act, cleanup, render, screen } from '@testing-library/react';
import { toast } from 'sonner';
import { AppShell } from '@/components/shell/AppShell';
import { RELEASES } from '@/lib/changelog';

vi.mock('next/navigation', () => ({
  usePathname: () => '/',
  useRouter: () => ({ push: vi.fn() }),
}));

// The header's notification bell polls /api/state; jsdom has no origin to resolve it against.
vi.stubGlobal('fetch', vi.fn(() => Promise.resolve({ ok: false })));

afterEach(() => {
  cleanup();
  localStorage.clear();
});

describe('AppShell toasts', () => {
  // The focus-block confirmation called toast() for months with no Toaster
  // mounted anywhere, so it never reached the screen.
  it('shows a toast raised from any screen inside the shell', async () => {
    localStorage.setItem('daily-web:changelog-seen', RELEASES[0].id);
    render(
      <AppShell theme="system" density="comfortable" backdrop="mesh" username="ana" avatarUrl={null} greetingName="ana" welcome="first">
        <p>conteúdo</p>
      </AppShell>,
    );

    act(() => {
      toast('Bloco de foco criado');
    });

    expect(await screen.findByText('Bloco de foco criado')).toBeInTheDocument();
  });
});
