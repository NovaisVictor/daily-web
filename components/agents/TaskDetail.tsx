'use client';

import Link from 'next/link';
import { ArrowLeft, Bot, Clock3 } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { ErrorState } from '@/components/data/ErrorState';
import { EmptyState } from '@/components/data/EmptyState';
import { formatTime, parseTaskDetail, STATUS_LABELS } from './contracts';
import { TaskActions } from './TaskActions';
import { useAgentPolling } from './useAgentPolling';
import { usePathname, useRouter, useSearchParams } from 'next/navigation';

export function TaskDetail({ id }: { id: string }) {
  const params = useSearchParams();
  const router = useRouter();
  const pathname = usePathname();
  const cursor = params.get('cursor');
  const { data, error, refresh } = useAgentPolling(`/api/agents/tasks/${encodeURIComponent(id)}${cursor ? `?cursor=${encodeURIComponent(cursor)}` : ''}`, parseTaskDetail);
  const task = data?.task;
  const page = (nextCursor: string | null) => {
    const next = new URLSearchParams(params.toString());
    if (nextCursor) next.set('cursor', nextCursor); else next.delete('cursor');
    router.replace(`${pathname}${next.size ? `?${next}` : ''}`, { scroll: false });
  };
  return <div className="mx-auto flex w-full max-w-5xl flex-col gap-5">
    <Button asChild variant="ghost" className="self-start"><Link href="/"><ArrowLeft className="size-4" />Voltar ao kanban</Link></Button>
    {error && <ErrorState title={data ? 'Último estado recebido' : 'Tarefa indisponível'} description={error} onRetry={refresh} />}
    {!data && !error && <p role="status" className="p-10 text-center text-ink-mid">Carregando tarefa…</p>}
    {task && <>
      <header className="rounded-2xl border border-line bg-surface-1 p-6"><span className="mb-3 inline-block rounded-full bg-secondary px-3 py-1 text-xs font-medium">{STATUS_LABELS[task.status]}</span><h1 className="break-words text-2xl font-semibold">{task.title}</h1>{task.description && <p className="mt-4 whitespace-pre-wrap break-words text-sm leading-relaxed text-ink-mid">{task.description}</p>}<p className="mt-4 text-xs text-ink-dim">Referência: {task.externalId} · Versão {task.version}</p><TaskActions task={task} onChanged={refresh} /></header>
      <div className="grid items-start gap-5 md:grid-cols-[minmax(0,1fr)_18rem]">
        <section className="rounded-2xl border border-line bg-surface-1 p-5"><h2 className="mb-5 font-semibold">Atividade recente</h2>{data.activity.items.length === 0 ? <EmptyState title="Sem atualizações de atividade" description="Novos relatos do agente aparecerão aqui." /> : <ol className="space-y-5 border-l border-line pl-5">{data.activity.items.map(activity => <li key={activity.id}><p className="whitespace-pre-wrap break-words text-sm">{activity.summary}</p><p className="mt-1 text-xs text-ink-dim"><time dateTime={activity.receivedAt}>{formatTime(activity.receivedAt)}</time> · {activity.kind}</p></li>)}</ol>}<div className="mt-5 flex flex-wrap gap-2">{cursor && <Button variant="outline" size="sm" onClick={() => page(null)}>Mais recentes</Button>}{data.activity.nextCursor && <Button variant="outline" size="sm" onClick={() => page(data.activity.nextCursor)}>Ver mais atividade</Button>}</div></section>
        <aside className="space-y-5 rounded-2xl border border-line bg-surface-1 p-5"><div><h2 className="flex items-center gap-2 text-sm font-semibold"><Bot className="size-4" />Agente responsável</h2>{task.assignment ? <><p className="mt-3 text-sm">{task.assignment.displayName}</p><p className="mt-1 text-xs text-ink-mid">{task.assignment.provider}</p><Link className="mt-3 block break-all text-xs text-primary underline underline-offset-4" href={`/agents?tab=tasks&sessionId=${encodeURIComponent(task.assignment.sessionId)}`}>Sessão {task.assignment.sessionId}</Link><p className="mt-3 text-xs text-ink-mid">{task.assignment.freshness === 'fresh' ? 'Reportando recentemente' : task.assignment.freshness === 'stale' ? 'Sem atualização há mais de 2 minutos' : 'Sem contato há mais de 10 minutos'}</p></> : <p className="mt-3 text-sm text-ink-mid">Nenhum agente atribuído.</p>}</div><div><h2 className="flex items-center gap-2 text-sm font-semibold"><Clock3 className="size-4" />Histórico</h2><dl className="mt-3 space-y-3 text-xs"><div><dt className="text-ink-dim">Criada em</dt><dd className="mt-1">{formatTime(task.createdAt)}</dd></div><div><dt className="text-ink-dim">Última atividade</dt><dd className="mt-1">{formatTime(task.lastActivityAt)}</dd></div></dl><p className="mt-4 text-xs leading-relaxed text-ink-mid">A tarefa e seu histórico expiram após 30 dias sem atividade aceita. Consultas não renovam esse prazo.</p></div>{task.source && <div><h2 className="text-sm font-semibold">Origem vinculada</h2><p className="mt-2 break-all text-xs text-ink-mid">{task.source.provider}: {task.source.resource}</p><p className="mt-1 text-xs text-ink-dim">O vínculo não altera o item de origem automaticamente.</p></div>}</aside>
      </div>
    </>}
  </div>;
}
