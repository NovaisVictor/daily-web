import { cookies } from 'next/headers';
import type { ReactNode } from 'react';
import { AppShell } from '@/components/shell/AppShell';
import { getCurrentUser } from '@/lib/auth/currentUser';
import { resolveAppearance } from '@/lib/appearance';
import { greetingName } from '@/lib/greeting';
import { welcomeKind } from '@/lib/preferences';

/**
 * Wraps the authenticated screens only. /login sits outside this group on
 * purpose: it has nothing to navigate to and no account to act on.
 */
export default async function AppLayout({ children }: { children: ReactNode }) {
  const jar = await cookies();
  const user = await getCurrentUser();
  const { theme, density, backdrop } = resolveAppearance(
    (name) => jar.get(name)?.value,
    user?.id ?? null,
  );

  return (
    <AppShell
      theme={theme}
      density={density}
      backdrop={backdrop}
      username={user?.username ?? null}
      avatarUrl={user?.avatarUrl ?? null}
      greetingName={user ? greetingName(user.fullName, user.username) : null}
      welcome={user ? welcomeKind(user.id) : 'first'}
    >
      {children}
    </AppShell>
  );
}
