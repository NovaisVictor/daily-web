import { afterEach, describe, expect, it, vi } from 'vitest';
import { cleanup, render } from '@testing-library/react';
import { AppShell } from '@/components/shell/AppShell';

vi.mock('next/navigation', () => ({
  usePathname: () => '/',
  useRouter: () => ({ push: vi.fn() }),
}));

vi.stubGlobal(
  'fetch',
  vi.fn(() => Promise.resolve({ ok: false })),
);

afterEach(() => {
  cleanup();
  localStorage.clear();
});

describe('AppShell content width', () => {
  // The cap is a CSS variant on the <html> attribute, which jsdom does not evaluate; what can be
  // pinned here is that it is conditional and not applied to everyone.
  it('caps the content only through the data-width variant, never unconditionally', () => {
    localStorage.setItem('daily-web:changelog-seen', 'x');
    render(
      <AppShell
        theme="system"
        density="comfortable"
        backdrop="mesh"
        username="ana"
        avatarUrl={null}
        greetingName="ana"
        welcome="first"
      >
        <p>conteúdo</p>
      </AppShell>,
    );

    const content = document.querySelector('main > div') as HTMLElement;
    expect(content.classList.contains('in-data-[width=limited]:max-w-[1216px]')).toBe(true);
    expect(content.classList.contains('max-w-[1216px]')).toBe(false);
  });
});
