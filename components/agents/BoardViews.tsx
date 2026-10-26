import { Bot, ChevronDown, TriangleAlert } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { EmptyState } from '@/components/data/EmptyState';
import { ACTIVITY_WINDOWS, activityWindow, formatTime, LIVE_LABELS, LIVE_TONES, NEEDS_YOU_LABELS, STATUS_LABELS, TASK_STATUSES, waitedFor, type AgentTask, type AgentSession, type SubtaskProgress, type TaskStatus } from './contracts';
import { TaskCard } from './TaskCard';

const ACTIVE: readonly TaskStatus[] = ['queued', 'working', 'waiting', 'blocked'];
const FINISHED: readonly TaskStatus[] = ['completed', 'failed', 'cancelled'];
const FINISHED_COUNTS: Record<string, [string, string]> = { completed: ['concluída', 'concluídas'], failed: ['falhou', 'falharam'], cancelled: ['cancelada', 'canceladas'] };

function Column({ value, tasks, progress }: { value: TaskStatus; tasks: AgentTask[]; progress: Record<string, SubtaskProgress> }) {
  const cards = tasks.filter(task => task.status === value);
  // On a phone an empty column is just its heading: a full empty box per status pushes the work off screen.
  return <section aria-label={STATUS_LABELS[value]} className={`min-w-0 rounded-xl border border-line bg-surface-1/80 p-2 ${cards.length === 0 ? 'max-sm:py-1' : ''}`}>
    <h2 className={`flex items-center justify-between gap-2 px-1 pt-1 text-sm font-semibold ${cards.length === 0 ? 'max-sm:pt-0 sm:mb-2' : 'mb-2'}`}><span>{STATUS_LABELS[value]}</span><span className="rounded-full bg-surface-2 px-2 py-0.5 text-xs font-normal text-ink-mid">{cards.length}</span></h2>
    <div className="flex flex-col gap-2">{cards.map(task => <TaskCard key={task.id} task={task} progress={progress[task.id]} />)}{cards.length === 0 && <p className="py-4 text-center text-xs text-ink-dim max-sm:hidden">Nenhuma tarefa</p>}</div>
  </section>;
}

export function KanbanColumns({ tasks, status, progress = {}, showFinished = false, onToggleFinished, totals = null }: { tasks: AgentTask[]; status: string | null; progress?: Record<string, SubtaskProgress>; showFinished?: boolean; onToggleFinished?: () => void; totals?: Record<TaskStatus, number> | null }) {
  const chosen = TASK_STATUSES.find(value => value === status);
  if (chosen) return <div className="grid grid-cols-1 items-start gap-3"><Column value={chosen} tasks={tasks} progress={progress} /></div>;
  // Server totals cover the whole period; the loaded page alone would undercount finished work.
  const counts = FINISHED.map(value => [value, totals?.[value] ?? tasks.filter(task => task.status === value).length] as const);
  const total = counts.reduce((sum, [, count]) => sum + count, 0);
  const failed = counts.find(([value]) => value === 'failed')?.[1] ?? 0;
  return <div className="flex flex-col gap-3">
    <div className="grid grid-cols-1 items-start gap-3 sm:grid-cols-2 lg:grid-cols-4">{ACTIVE.map(value => <Column key={value} value={value} tasks={tasks} progress={progress} />)}</div>
    <button type="button" onClick={onToggleFinished} disabled={total === 0} aria-expanded={showFinished} aria-controls="finished-columns" className={`flex w-full flex-wrap items-center justify-between gap-2 rounded-xl border border-dashed ${failed > 0 ? 'border-danger/60' : 'border-line'} bg-surface-1/60 px-4 py-2.5 text-left text-sm transition-colors hover:border-brand-edge hover:bg-surface-1 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring disabled:cursor-default disabled:hover:border-line disabled:hover:bg-surface-1/60`}>
      <span className="flex flex-wrap items-center gap-x-2 gap-y-1">
        <span className="font-semibold">Finalizadas</span>
        {total === 0 ? <span className="text-xs text-ink-dim">nenhuma neste período</span> : counts.filter(([, count]) => count > 0).map(([value, count]) => value === 'failed'
          ? <span key={value} className="flex items-center gap-1 rounded-full bg-danger-tint px-2 py-0.5 text-xs font-semibold text-danger"><TriangleAlert aria-hidden className="size-3.5" />{count} {FINISHED_COUNTS[value][count === 1 ? 0 : 1]}</span>
          : <span key={value} className="text-xs text-ink-mid">{count} {FINISHED_COUNTS[value][count === 1 ? 0 : 1]}</span>)}
      </span>
      {total > 0 && <span className="flex items-center gap-1 text-xs font-medium text-primary">{showFinished ? 'Ocultar' : 'Mostrar'}<ChevronDown aria-hidden className={`size-4 transition-transform motion-reduce:transition-none ${showFinished ? 'rotate-180' : ''}`} /></span>}
    </button>
    {showFinished && total > 0 && <div id="finished-columns" className="grid grid-cols-1 items-start gap-3 sm:grid-cols-2 lg:grid-cols-3">{FINISHED.map(value => <Column key={value} value={value} tasks={tasks} progress={progress} />)}</div>}
  </div>;
}

function sessionNeedsYou(session: AgentSession) {
  if (session.live?.state === 'prompt') return { kind: session.attention?.kind === 'permission' ? 'permission' as const : 'menu' as const, since: session.attention?.since ?? session.live.since ?? session.lastActivityAt };
  if (session.live && session.live.state !== 'idle') return null;
  return session.attention;
}
const freshnessLabels = { fresh: 'Reportando recentemente', stale: 'Sem atualização há mais de 2 minutos', disconnected: 'Sem contato há mais de 10 minutos' };
export function SessionGrid({ sessions, onSelect }: { sessions: AgentSession[]; onSelect: (id: string) => void }) {
  if (sessions.length === 0) return <EmptyState title="Nenhuma sessão reportada" description="As sessões aparecem quando seus agentes se conectarem." />;
  return <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-3">{sessions.map(session => { const attention = sessionNeedsYou(session); return <article key={session.id} className={`rounded-xl border bg-surface-1 p-5 ${attention ? 'border-danger ring-2 ring-danger/40' : 'border-line'}`}>
    <Bot className="mb-3 size-5 text-primary" />
    <h2 className="font-semibold">{session.agent.displayName}</h2>
    <p className="mt-1 break-all text-xs text-ink-dim">{session.agent.provider} · {session.id}</p>
    <p className="mt-3 text-xs text-ink-mid">Última atividade: {formatTime(session.lastActivityAt)}</p>
    <p className="mt-2 text-xs text-ink-mid">{freshnessLabels[session.freshness]}</p>
    {session.live && <p className="mt-2 flex items-center gap-1.5 text-xs text-ink-mid"><span aria-hidden className={`size-1.5 rounded-full ${LIVE_TONES[session.live.state]}`} />{LIVE_LABELS[session.live.state]}</p>}
    {attention && <p className="mt-2 flex items-center gap-1.5 text-xs font-semibold text-danger"><span aria-hidden className="size-1.5 rounded-full bg-danger motion-safe:animate-ping" />{NEEDS_YOU_LABELS[attention.kind]} · {waitedFor(attention.since)}</p>}
    <Button variant="link" className="mt-2 px-0" onClick={() => onSelect(session.id)}>Ver tarefas da sessão</Button>
  </article>; })}</div>;
}

const fieldClass = 'h-9 rounded-lg border border-line-strong bg-surface-2 px-3 text-sm outline-none focus-visible:ring-2 focus-visible:ring-ring';
export function BoardFilters({ params, onChange }: { params: Pick<URLSearchParams, 'get'>; onChange: (name: string, value: string) => void }) {
  return <div className="flex flex-wrap items-center gap-3 rounded-xl border border-line bg-surface-1 p-3">
    <label className="flex flex-1 items-center gap-2 text-sm"><span className="sr-only">Buscar tarefas</span><input type="search" value={params.get('q') ?? ''} onChange={event => onChange('q', event.target.value)} placeholder="Buscar tarefa…" maxLength={200} className={`${fieldClass} w-full min-w-40`} /></label>
    <label className="flex items-center gap-2 text-xs text-ink-mid">Status<select value={params.get('status') ?? ''} onChange={event => onChange('status', event.target.value)} className={fieldClass}><option value="">Todos</option>{TASK_STATUSES.map(status => <option key={status} value={status}>{STATUS_LABELS[status]}</option>)}</select></label>
    <label className="flex items-center gap-2 text-xs text-ink-mid">Período<select value={activityWindow(params.get('days'))} onChange={event => onChange('days', event.target.value)} className={fieldClass}>{ACTIVITY_WINDOWS.map(days => <option key={days} value={days}>Últimos {days} dias</option>)}</select></label>
    <label className="flex items-center gap-2 text-xs text-ink-mid">Ordem<select value={params.get('sort') ?? 'newest'} onChange={event => onChange('sort', event.target.value)} className={fieldClass}><option value="newest">Atividade recente</option><option value="oldest">Atividade mais antiga</option></select></label>
    {params.get('sessionId') && <Button size="sm" variant="ghost" onClick={() => onChange('sessionId', '')}>Limpar sessão</Button>}
  </div>;
}
