import { Bot } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { EmptyState } from '@/components/data/EmptyState';
import { ACTIVITY_WINDOWS, activityWindow, formatTime, LIVE_LABELS, LIVE_TONES, NEEDS_YOU_LABELS, STATUS_LABELS, TASK_STATUSES, waitedFor, type AgentTask, type AgentSession, type SubtaskProgress } from './contracts';
import { TaskCard } from './TaskCard';

export function KanbanColumns({ tasks, status, progress = {} }: { tasks: AgentTask[]; status: string | null; progress?: Record<string, SubtaskProgress> }) {
  const columns = TASK_STATUSES.filter(value => !status || status === value);
  return <div className="grid grid-cols-1 items-start gap-3 sm:grid-cols-2 xl:grid-cols-3 2xl:grid-cols-7">
    {columns.map(value => {
      const cards = tasks.filter(task => task.status === value);
      return <section key={value} aria-label={STATUS_LABELS[value]} className="min-w-0 rounded-xl border border-line bg-surface-1/80 p-2">
        <h2 className="mb-2 flex px-1 pt-1 items-center justify-between gap-2 text-sm font-semibold"><span>{STATUS_LABELS[value]}</span><span className="rounded-full bg-surface-2 px-2 py-0.5 text-xs font-normal text-ink-mid">{cards.length}</span></h2>
        <div className="flex flex-col gap-2">{cards.map(task => <TaskCard key={task.id} task={task} progress={progress[task.id]} />)}{cards.length === 0 && <p className="py-4 text-center text-xs text-ink-dim">Nenhuma tarefa</p>}</div>
      </section>;
    })}
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
