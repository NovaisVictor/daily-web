import { useEffect, useRef, useState } from 'react';
import { Bot, ChevronDown, ListFilter, Search, TriangleAlert } from 'lucide-react';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { IconAction } from '@/components/data/IconAction';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuLabel,
  DropdownMenuItem,
  DropdownMenuRadioGroup,
  DropdownMenuRadioItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover';
import { EmptyState } from '@/components/data/EmptyState';
import { ACTIVITY_WINDOWS, activityWindow, DEFAULT_ACTIVITY_WINDOW, formatTime, LIVE_LABELS, LIVE_TONES, NEEDS_YOU_LABELS, STATUS_LABELS, TASK_STATUSES, waitedFor, type AgentTask, type AgentSession, type SubtaskProgress, type TaskStatus } from './contracts';
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
type FilterParams = Pick<URLSearchParams, 'get'>;
type FilterChange = (name: string, value: string) => void;

/** The empty string means "no filter" in the URL, but a radio item cannot carry it. */
const ALL = 'all';

/**
 * The URL is the truth for the search, but it answers a keystroke late: an input driven straight
 * from it gave back the old value in between and dropped letters typed quickly. The field keeps
 * its own text and the URL follows after a short pause.
 */
const SEARCH_DEBOUNCE_MS = 250;

function SearchField({ query, onChange }: { query: string; onChange: (value: string) => void }) {
  const [draft, setDraft] = useState(query);
  // The last value this field wrote to the URL, to tell its own echo from an outside change.
  const pushed = useRef(query);
  const latestOnChange = useRef(onChange);
  latestOnChange.current = onChange;

  useEffect(() => {
    if (query !== pushed.current) {
      pushed.current = query;
      setDraft(query);
    }
  }, [query]);

  useEffect(() => {
    if (draft === pushed.current) return;
    const timer = setTimeout(() => {
      pushed.current = draft;
      latestOnChange.current(draft);
    }, SEARCH_DEBOUNCE_MS);
    return () => clearTimeout(timer);
  }, [draft]);

  return (
    <input
      type="search"
      autoFocus
      value={draft}
      onChange={(event) => setDraft(event.target.value)}
      placeholder="Buscar tarefa…"
      maxLength={200}
      aria-label="Buscar tarefas"
      className={`${fieldClass} w-full`}
    />
  );
}

/** Search sits behind an icon: one input took a whole bar across the page. */
export function BoardSearch({ params, onChange }: { params: FilterParams; onChange: FilterChange }) {
  const query = params.get('q') ?? '';
  return (
    <div className="relative">
      <Popover>
        <PopoverTrigger asChild>
          <IconAction variant="outline" label="Buscar tarefas" icon={<Search className="size-4" />} />
        </PopoverTrigger>
        <PopoverContent align="center" className="w-80 p-2">
          <SearchField query={query} onChange={(value) => onChange('q', value)} />
        </PopoverContent>
      </Popover>
      {/* A search that is on has to show without opening the popover. */}
      {query && (
        <span aria-hidden className="pointer-events-none absolute -top-0.5 -right-0.5 size-2.5 rounded-full bg-brand" />
      )}
    </div>
  );
}

/** Status, period and order in one dropdown; the number says how many differ from the default. */
export function BoardFilterMenu({ params, onChange }: { params: FilterParams; onChange: FilterChange }) {
  const status = params.get('status') ?? '';
  const days = activityWindow(params.get('days'));
  const sort = params.get('sort') === 'oldest' ? 'oldest' : 'newest';
  const sessionId = params.get('sessionId');
  const active =
    (status ? 1 : 0) + (days !== DEFAULT_ACTIVITY_WINDOW ? 1 : 0) + (sort !== 'newest' ? 1 : 0) + (sessionId ? 1 : 0);

  // Several filters are usually changed in a row, so choosing one does not close the menu.
  const keepOpen = (event: Event) => event.preventDefault();

  return (
    <div className="relative">
      <DropdownMenu>
        <DropdownMenuTrigger asChild>
          <IconAction variant="outline" label="Filtros" icon={<ListFilter className="size-4" />} />
        </DropdownMenuTrigger>
        <DropdownMenuContent align="center" className="w-60">
          <DropdownMenuLabel>Status</DropdownMenuLabel>
          <DropdownMenuRadioGroup value={status || ALL} onValueChange={(value) => onChange('status', value === ALL ? '' : value)}>
            <DropdownMenuRadioItem value={ALL} onSelect={keepOpen}>Todos</DropdownMenuRadioItem>
            {TASK_STATUSES.map((value) => (
              <DropdownMenuRadioItem key={value} value={value} onSelect={keepOpen}>{STATUS_LABELS[value]}</DropdownMenuRadioItem>
            ))}
          </DropdownMenuRadioGroup>
          <DropdownMenuSeparator />
          <DropdownMenuLabel>Período</DropdownMenuLabel>
          <DropdownMenuRadioGroup value={String(days)} onValueChange={(value) => onChange('days', value)}>
            {ACTIVITY_WINDOWS.map((window) => (
              <DropdownMenuRadioItem key={window} value={String(window)} onSelect={keepOpen}>Últimos {window} dias</DropdownMenuRadioItem>
            ))}
          </DropdownMenuRadioGroup>
          <DropdownMenuSeparator />
          <DropdownMenuLabel>Ordem</DropdownMenuLabel>
          <DropdownMenuRadioGroup value={sort} onValueChange={(value) => onChange('sort', value)}>
            <DropdownMenuRadioItem value="newest" onSelect={keepOpen}>Atividade recente</DropdownMenuRadioItem>
            <DropdownMenuRadioItem value="oldest" onSelect={keepOpen}>Atividade mais antiga</DropdownMenuRadioItem>
          </DropdownMenuRadioGroup>
          {sessionId && (
            <>
              <DropdownMenuSeparator />
              <DropdownMenuItem onSelect={() => onChange('sessionId', '')}>Limpar sessão</DropdownMenuItem>
            </>
          )}
        </DropdownMenuContent>
      </DropdownMenu>
      {active > 0 && (
        <Badge className="pointer-events-none absolute -top-1 -right-1 min-w-4 justify-center rounded-full px-1 type-caption leading-none tabular-nums">
          {active}
        </Badge>
      )}
    </div>
  );
}
