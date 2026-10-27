'use client';

import { createContext, useContext, type ReactNode } from 'react';
import { useDashboardState } from '@/lib/hooks/usePolling';

type DashboardStateValue = ReturnType<typeof useDashboardState>;

const DashboardStateContext = createContext<DashboardStateValue | null>(null);

/**
 * One poller for the whole shell. The header's bell and refresh button and the
 * dashboard page read the same state, so refreshing from the header updates
 * the panels at once instead of waiting for the page's own next poll.
 */
export function DashboardStateProvider({ children }: { children: ReactNode }) {
  const value = useDashboardState();
  return <DashboardStateContext.Provider value={value}>{children}</DashboardStateContext.Provider>;
}

export function useSharedDashboardState(): DashboardStateValue {
  const value = useContext(DashboardStateContext);
  if (!value) {
    throw new Error('useSharedDashboardState must be used inside DashboardStateProvider');
  }
  return value;
}
