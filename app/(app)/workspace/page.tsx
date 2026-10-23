'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import type { ReactNode } from 'react';
import Link from 'next/link';
import { useDashboardState } from '@/lib/hooks/usePolling';
import { useDesktopAlerts } from '@/lib/hooks/useDesktopAlerts';
import { NowBand } from '@/components/NowBand';
import { NotificationsBell } from '@/components/NotificationsBell';
import { EmailPanel } from '@/components/EmailPanel';
import { AgendaPanel } from '@/components/AgendaPanel';
import { PullsPanel } from '@/components/PullsPanel';
import { JiraPanel } from '@/components/JiraPanel';
import { TasksPanel } from '@/components/TasksPanel';
import { FocusBlockProvider } from '@/components/FocusBlockProvider';
import { DashboardGrid } from '@/components/DashboardGrid';
import { NotesPanel } from '@/components/NotesPanel';
import { SlackPanel } from '@/components/SlackPanel';
import { EmptyState } from '@/components/data/EmptyState';
import { ErrorState } from '@/components/data/ErrorState';
import { Button } from '@/components/ui/button';
import { Plug } from 'lucide-react';
import { DEFAULT_AGENDA_DAYS } from '@/lib/agendaWindow';
import {
  defaultLayout,
  nearestLayout,
  type PanelPlacement,
  type SizedLayout,
} from '@/lib/dashboardLayout';
import {
  markEmailsSeen,
  markNotificationRead,
  markNotificationsRead,
  removeEmails,
  removeTask,
  setSubtaskCompleted,
  setTaskCompleted,
  setTaskDoing,
  setTaskStyle,
} from '@/lib/statePatches';

export default function DashboardPage() {
  const { state, loading, refreshNow, reload, mutate } = useDashboardState();
  const desktop = useDesktopAlerts(state);
  const [layoutError, setLayoutError] = useState<string | null>(null);
  const booting = loading && !state;
  // As duas listas de PRs, para o Jira mostrar sob cada issue o PR que a cita.
  const jiraPulls = useMemo(
    () => [...(state?.pulls.data?.items ?? []), ...(state?.reviewRequests.data?.items ?? [])],
    [state?.pulls.data, state?.reviewRequests.data],
  );

  // Cada pessoa liga os módulos que usa. Um painel de módulo desligado não
  // aparece vazio: ele não aparece.
  const modules = state?.modules ?? [];
  const has = (id: string) => modules.includes(id);
  const nothingOn = state !== null && modules.length === 0;
  const layouts = (state?.layouts as SizedLayout[] | undefined) ?? [];
  const legado = (state?.layout as PanelPlacement[] | undefined) ?? defaultLayout();

  // A escolha da disposição é do cliente: só ele sabe o tamanho da janela.
  // Enquanto não houver gravação por tamanho, vale a disposição única antiga.
  const [janela, setJanela] = useState<{ width: number; height: number } | null>(null);
  useEffect(() => {
    const medir = () => setJanela({ width: window.innerWidth, height: window.innerHeight });
    medir();
    window.addEventListener('resize', medir);
    return () => window.removeEventListener('resize', medir);
  }, []);

  const layout = useMemo(() => {
    if (!janela) return legado;
    return nearestLayout(layouts, janela.width, janela.height)?.layout ?? legado;
  }, [layouts, legado, janela]);

  // A disposição é gravada para o tamanho de janela de agora, e só quando a
  // pessoa pede: arrastar não grava nada.
  const saveLayout = useCallback(
    async (next: PanelPlacement[]) => {
      const viewport = { width: window.innerWidth, height: window.innerHeight };
      const res = await fetch('/api/preferences', {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ layout: next, viewport }),
      });
      if (!res.ok) {
        const data = await res.json().catch(() => ({}));
        setLayoutError(data.error ?? 'Falha ao guardar a disposição dos painéis');
        reload();
        return;
      }
      setLayoutError(null);
      const { layouts: gravados } = (await res.json()) as { layouts: SizedLayout[] };
      mutate((s) => ({ ...s, layouts: gravados }));
    },
    [mutate, reload],
  );

  const panels: { id: string; node: ReactNode }[] = [
    has('email') && {
      id: 'email',
      node: (
        <EmailPanel
          email={state?.email ?? { data: [], error: null }}
          mailboxes={state?.mailboxes ?? []}
          onChanged={reload}
          onSeenChanged={(targets, seen) => mutate((s) => markEmailsSeen(s, targets, seen))}
          onRemoved={(targets) => mutate((s) => removeEmails(s, targets))}
          loading={booting}
        />
      ),
    },
    has('tasks') && {
      id: 'tasks',
      node: (
        <TasksPanel
          tasks={state?.tasks ?? { data: [], error: null }}
          onChanged={reload}
          onCompletedChanged={(id, completed) => mutate((s) => setTaskCompleted(s, id, completed))}
          onRemoved={(id) => mutate((s) => removeTask(s, id))}
          onSubtaskChanged={(taskId, itemId, completed) =>
            mutate((s) => setSubtaskCompleted(s, taskId, itemId, completed))
          }
          onDoingChanged={(id, doing) => mutate((s) => setTaskDoing(s, id, doing))}
          onStyleChanged={(id, style) => mutate((s) => setTaskStyle(s, id, style))}
          view={state?.tasksView ?? 'board'}
          onViewChanged={(tasksView) => mutate((s) => ({ ...s, tasksView }))}
          loading={booting}
        />
      ),
    },
    has('notes') && {
      id: 'notes',
      // O painel busca e grava as próprias notas: passar por `state` faria o
      // refresh de 60s sobrescrever o que está sendo digitado.
      node: <NotesPanel />,
    },
    has('agenda') && {
      id: 'agenda',
      node: (
        <AgendaPanel
          agenda={state?.agenda ?? { data: [], error: null }}
          days={state?.agendaDays ?? DEFAULT_AGENDA_DAYS}
          onChanged={reload}
          loading={booting}
        />
      ),
    },
    has('jira') && {
      id: 'jira',
      node: (
        <JiraPanel
          jira={state?.jira ?? { data: [], error: null }}
          watched={state?.jiraWatched ?? { data: [], error: null }}
          delivered={state?.jiraDelivered ?? { data: [], error: null }}
          approved={state?.jiraApproved ?? { data: [], error: null }}
          problems={state?.jiraProblems ?? { data: [], error: null }}
          ancestors={state?.jiraAncestors ?? []}
          people={state?.jiraFollowedPeople ?? []}
          refreshedAt={state?.updatedAt ?? null}
          onChanged={reload}
          loading={booting}
          pulls={jiraPulls}
          myPulls={state?.myPulls.data?.items}
        />
      ),
    },
    has('pulls') && {
      id: 'pulls',
      node: (
        <PullsPanel
          pulls={state?.pulls ?? { data: { items: [], errors: [], defaultBranches: [], truncated: [] }, error: null }}
          reviewRequests={state?.reviewRequests ?? { data: null, error: null }}
          myPulls={state?.myPulls ?? { data: null, error: null }}
          onChanged={reload}
          loading={booting}
        />
      ),
    },
    has('slack') && {
      id: 'slack',
      node: (
        <SlackPanel
          slack={state?.slack ?? { data: { mentions: [], directs: [], team: '' }, error: null }}
          loading={booting}
        />
      ),
    },
  ].filter((p) => p !== false) as { id: string; node: ReactNode }[];

  return (
    <div className="flex flex-col gap-4">
      <NowBand
        pomodoro={state?.pomodoro ?? null}
        loading={loading}
        onRefresh={() => void refreshNow()}
        onChanged={reload}
        updatedAt={state?.updatedAt ?? null}
        nextRefreshAt={state?.nextRefreshAt ?? null}
        bell={
          has('jira') || has('email') || has('pulls') || has('slack') ? (
            <NotificationsBell
              notifications={state?.notifications ?? { data: [], error: null }}
              onChanged={reload}
              onMarkedRead={(id) => mutate((s) => markNotificationRead(s, id))}
              onMarkedAllRead={(ids) => mutate((s) => markNotificationsRead(s, ids))}
              desktop={{
                supported: desktop.supported,
                enabled: desktop.enabled,
                permission: desktop.permission,
                onEnable: () => void desktop.enable(),
                onDisable: desktop.disable,
              }}
            />
          ) : null
        }
      />

      {layoutError && <ErrorState title="Não deu para guardar a disposição" description={layoutError} />}

      {nothingOn ? (
        <EmptyState
          icon={<Plug />}
          title="Nenhum módulo ligado ainda"
          description="Conecte seu e-mail, agenda, Jira ou GitHub para o painel começar a mostrar alguma coisa. Cada um é opcional e leva menos de um minuto."
          action={
            <Button asChild variant="glow">
              <Link href="/config">Conectar minhas contas</Link>
            </Button>
          }
        />
      ) : (
        <FocusBlockProvider calendars={state?.agendaCalendars ?? []} onCreated={reload}>
          <DashboardGrid layout={layout} panels={panels} onSave={saveLayout} />
        </FocusBlockProvider>
      )}
    </div>
  );
}
