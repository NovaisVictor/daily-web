'use client';

import { createContext, useContext, type ReactNode } from 'react';

export interface PullsActionsValue {
  /** Asks for the dashboard state again after a write was accepted. */
  onChanged: () => void;
}

const PullsActionsContext = createContext<PullsActionsValue>({ onChanged: () => {} });

export function PullsActionsProvider({ value, children }: { value: PullsActionsValue; children: ReactNode }) {
  return <PullsActionsContext.Provider value={value}>{children}</PullsActionsContext.Provider>;
}

export function usePullsActions(): PullsActionsValue {
  return useContext(PullsActionsContext);
}
