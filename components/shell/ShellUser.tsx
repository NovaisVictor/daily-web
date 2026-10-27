'use client';

import { createContext, useContext, type ReactNode } from 'react';
import type { WelcomeKind } from '@/lib/greeting';

export interface ShellUser {
  /** What the greeting calls the person; null when nobody is signed in. */
  greetingName: string | null;
  welcome: WelcomeKind;
}

const ShellUserContext = createContext<ShellUser | null>(null);

/** The layout knows the user on the server; pages below it read it from here without a fetch. */
export function ShellUserProvider({ value, children }: { value: ShellUser; children: ReactNode }) {
  return <ShellUserContext.Provider value={value}>{children}</ShellUserContext.Provider>;
}

export function useShellUser(): ShellUser {
  const value = useContext(ShellUserContext);
  if (!value) throw new Error('useShellUser must be used inside ShellUserProvider');
  return value;
}
