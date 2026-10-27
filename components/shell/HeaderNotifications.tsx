'use client';

import { RefreshCw } from 'lucide-react';
import { IconAction } from '@/components/data/IconAction';
import { useSharedDashboardState } from '@/lib/hooks/DashboardStateProvider';
import { markNotificationRead, markNotificationsRead } from '@/lib/statePatches';
import { NotificationsBell } from '@/components/NotificationsBell';
import { cn } from '@/lib/utils';

/**
 * The header's refresh button and bell. Both read the dashboard state shared by
 * the shell, so opening the bell never triggers a fresh round-trip to Jira,
 * GitHub or the inbox — it reads what the last refresh cycle already cached —
 * and the refresh button updates the dashboard panels too. No desktop-alert
 * toggle here; that setting lives on the dashboard page's own bell.
 */
export function HeaderNotifications() {
  const { state, loading, refreshNow, reload, mutate } = useSharedDashboardState();

  return (
    <>
      <IconAction
        label={loading ? 'Atualizando…' : 'Atualizar agora'}
        variant="outline"
        size="icon"
        className="size-10 border-transparent"
        onClick={() => void refreshNow()}
        disabled={loading}
        icon={<RefreshCw className={cn('size-5', loading && 'animate-spin')} />}
      />
      <NotificationsBell
        notifications={state?.notifications ?? { data: [], error: null }}
        onChanged={reload}
        onMarkedRead={(id) => mutate((s) => markNotificationRead(s, id))}
        onMarkedAllRead={(ids) => mutate((s) => markNotificationsRead(s, ids))}
        triggerClassName="size-10 border-transparent"
      />
    </>
  );
}
