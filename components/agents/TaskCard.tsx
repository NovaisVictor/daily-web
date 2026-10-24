import Link from 'next/link';
import { Bot } from 'lucide-react';
import { type AgentTask, type SubtaskProgress, formatTime, holdLabel, NEEDS_YOU_LABELS, needsYou, STATUS_TONES, waitedFor } from './contracts';
import { SubtaskTicker } from './SubtaskTicker';

const FRESHNESS_LABELS = { fresh: 'Reportando', stale: 'Sem atualização recente', disconnected: 'Sem contato há mais de 10 min' };
const PROVIDER_ACCENTS = { claude: 'border-l-chart-3 [--provider:var(--chart-3)]', codex: 'border-l-chart-5 [--provider:var(--chart-5)]', gemini: 'border-l-chart-2 [--provider:var(--chart-2)]' };
const FRESHNESS_DOTS = { fresh: 'bg-success', stale: 'bg-warning', disconnected: 'bg-warning' };
export function TaskCard({ task, progress }: { task: AgentTask; progress?: SubtaskProgress }) {
  const waiting = needsYou(task);
  return (
    <Link href={`/agents/tasks/${encodeURIComponent(task.id)}`} title={task.description || undefined} className={`group flex flex-col gap-2 rounded-lg border border-l-[3px] border-line ${task.assignment ? PROVIDER_ACCENTS[task.assignment.provider] : ''} ${waiting ? 'ring-2 ring-danger/70 motion-safe:animate-[needs-you_2s_ease-in-out_infinite]' : ''} bg-surface-2 px-3 py-2.5 shadow-e1 transition hover:border-brand-edge hover:shadow-e2 focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-ring`} data-provider={task.assignment?.provider} data-needs-you={waiting ? waiting.kind : undefined}>
      {waiting && <span className="flex items-center gap-1.5 text-[11px] font-semibold text-danger"><span aria-hidden className="size-1.5 shrink-0 rounded-full bg-danger motion-safe:animate-ping" />{NEEDS_YOU_LABELS[waiting.kind]}<span className="font-normal text-ink-dim">· {waitedFor(waiting.since)}</span></span>}
      <span className="line-clamp-2 text-[13px] font-semibold leading-snug text-ink group-hover:text-primary">{task.title}</span>
      {task.hold && <span className="flex min-w-0 items-center gap-1.5 text-[11px]"><span className={`shrink-0 rounded-full px-1.5 py-0.5 font-medium ${STATUS_TONES[task.status]}`}>{holdLabel(task.status, task.hold)}</span>{task.hold.note && <span className="truncate text-ink-dim">{task.hold.note}</span>}</span>}
      {progress && progress.total > 0 && <SubtaskTicker progress={progress} />}
      <div className="flex items-center gap-1.5 text-[11px] text-ink-dim">
        <Bot className="size-3 shrink-0 text-(--provider,currentColor)" />
        <span className="min-w-0 flex-1 truncate">{task.assignment ? `${task.assignment.displayName} · ${task.assignment.provider}` : 'Sem agente atribuído'}</span>
        {task.assignment && <span title={FRESHNESS_LABELS[task.assignment.freshness]} className={`size-1.5 shrink-0 rounded-full ${FRESHNESS_DOTS[task.assignment.freshness]}`}><span className="sr-only">{FRESHNESS_LABELS[task.assignment.freshness]}</span></span>}
        <time dateTime={task.lastActivityAt} className="shrink-0 tabular-nums">{formatTime(task.lastActivityAt)}</time>
      </div>
    </Link>
  );
}
