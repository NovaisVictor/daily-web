import { cookies } from 'next/headers';
import type { ReactNode } from 'react';
import { AppShell } from '@/components/shell/AppShell';
import { getCurrentUser } from '@/lib/auth/currentUser';
import { greetingName } from '@/lib/greeting';
import { welcomeKind } from '@/lib/preferences';
import {
  BACKDROP_COOKIE,
  DENSITY_COOKIE,
  THEME_COOKIE,
  parseBackdrop,
  parseDensity,
  parseTheme,
} from '@/lib/theme';

/**
 * Wraps the authenticated screens only. /login sits outside this group on
 * purpose: it has nothing to navigate to and no account to act on.
 */
export default async function AppLayout({ children }: { children: ReactNode }) {
  const jar = await cookies();
  const user = await getCurrentUser();

  return (
    <AppShell
      theme={parseTheme(jar.get(THEME_COOKIE)?.value)}
      density={parseDensity(jar.get(DENSITY_COOKIE)?.value)}
      backdrop={parseBackdrop(jar.get(BACKDROP_COOKIE)?.value)}
      username={user?.username ?? null}
      avatarUrl={user?.avatarUrl ?? null}
      greetingName={user ? greetingName(user.fullName, user.username) : null}
      welcome={user ? welcomeKind(user.id) : 'first'}
    >
      {children}
    </AppShell>
  );
}
