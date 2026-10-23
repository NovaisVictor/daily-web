import Link from 'next/link';
import { Bot, Clock3 } from 'lucide-react';
import { type AgentTask, formatTime } from './contracts';

const FRESHNESS_LABELS = { fresh: 'Reportando', stale: 'Sem atualização recente', disconnected: 'Sem contato há mais de 10 min' };
export function TaskCard({ task }: { task: AgentTask }) {
  return (
    <Link href={`/agents/tasks/${encodeURIComponent(task.id)}`} className="group flex flex-col gap-3 rounded-xl border border-line bg-surface-2 p-4 shadow-e1 transition hover:border-brand-edge hover:shadow-e2 focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-ring">
      <span className="text-sm font-semibold leading-relaxed text-ink group-hover:text-primary">{task.title}</span>
      {task.description && <p className="line-clamp-2 text-xs leading-relaxed text-ink-mid">{task.description}</p>}
      <div className="flex items-start gap-2 text-xs text-ink-mid"><Bot className="mt-0.5 size-3.5 shrink-0" /><span>{task.assignment ? <>{task.assignment.displayName}<span className="block text-ink-dim">{task.assignment.provider} · {task.assignment.sessionId.slice(0, 8)}</span></> : 'Sem agente atribuído'}</span></div>
      {task.assignment && <span className={`text-xs ${task.assignment.freshness === 'fresh' ? 'text-signal-success' : 'text-signal-warning'}`}>{FRESHNESS_LABELS[task.assignment.freshness]}</span>}
      <span className="flex items-center gap-1.5 text-[11px] text-ink-dim"><Clock3 className="size-3" /><time dateTime={task.lastActivityAt}>{formatTime(task.lastActivityAt)}</time></span>
    </Link>
  );
}
