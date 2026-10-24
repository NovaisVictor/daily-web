'use client';

import { useEffect, useState } from 'react';
import { type SubtaskProgress } from './contracts';

const DOT_TONES = { queued: 'bg-ink-dim', working: 'bg-info', blocked: 'bg-warning' } as const;
export function SubtaskTicker({ progress }: { progress: SubtaskProgress }) {
  const [index, setIndex] = useState(0);
  const count = progress.active.length;
  useEffect(() => {
    if (count < 2) return;
    const timer = setInterval(() => setIndex(value => value + 1), 3200);
    return () => clearInterval(timer);
  }, [count]);
  const current = count ? progress.active[index % count] : null;
  const running = progress.active.some(item => item.status === 'working');
  const width = `${Math.round((progress.completed / progress.total) * 100)}%`;
  return (
    <div role="group" aria-label={`Subtarefas: ${progress.completed} de ${progress.total} concluídas`} className="flex flex-col gap-1.5">
      <div className="h-1 overflow-hidden rounded-full bg-neutral-tint">
        <div className={`relative h-full min-w-1 overflow-hidden rounded-full transition-[width] duration-700 ${current ? 'bg-info' : 'bg-success'}`} style={{ width }}>
          {running && <span aria-hidden className="absolute inset-y-0 -left-full w-full bg-linear-to-r from-transparent via-white/60 to-transparent motion-safe:animate-[subtask-sweep_1.8s_ease-in-out_infinite] motion-reduce:hidden" />}
        </div>
      </div>
      <div className="flex items-center gap-1.5 text-[11px] text-ink-dim">
        {current && <span aria-hidden className={`size-1.5 shrink-0 rounded-full motion-safe:animate-pulse ${DOT_TONES[current.status as keyof typeof DOT_TONES] ?? 'bg-ink-dim'}`} />}
        <span className="h-4 min-w-0 flex-1 overflow-hidden">
          <span key={current?.id ?? 'done'} className="block truncate motion-safe:animate-[subtask-roll_0.45s_ease-out]">{current ? current.title : 'Subtarefas concluídas'}</span>
        </span>
        <span className="shrink-0 tabular-nums">{progress.completed}/{progress.total}</span>
      </div>
    </div>
  );
}
