'use client';

import Link from 'next/link';
import { usePathname, useRouter, useSearchParams } from 'next/navigation';
import { Columns3, RefreshCw } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { EmptyState } from '@/components/data/EmptyState';
import { ErrorState } from '@/components/data/ErrorState';
import { parseSnapshot } from './contracts';
import { useAgentPolling } from './useAgentPolling';
import { BoardFilters, KanbanColumns, SessionGrid } from './BoardViews';

export function AgentBoard({ mode = 'kanban' }: { mode?: 'kanban' | 'workspace' }) {
  const detailed = mode === 'workspace';
  const params = useSearchParams();
  const router = useRouter();
  const pathname = usePathname();
  const query = new URLSearchParams(params.toString());
  if (!detailed) { query.delete('tab'); query.delete('parentTaskId'); }
  query.set('scope', detailed ? 'all' : 'roots');
  query.set('sort', params.get('sort') === 'oldest' ? 'oldest' : 'newest');
  query.set('limit', '100');
  const { data, error, phase, refresh } = useAgentPolling(`/api/agents?${query.toString()}`, parseSnapshot);
  const changeFilter = (name: string, value: string) => {
    const next = new URLSearchParams(params.toString());
    if (value) next.set(name, value); else next.delete(name);
    if (name !== 'cursor') next.delete('cursor');
    router.replace(`${pathname}${next.size ? `?${next}` : ''}`, { scroll: false });
  };
  const tasks = (data?.tasks.items ?? []).filter(task => (detailed || task.parentTaskId === null) && Date.parse(task.lastActivityAt) > Date.now() - 30 * 86400000);
  const tab = detailed && params.get('tab') === 'sessions' ? 'sessions' : 'tasks';
  const nextCursor = tab === 'sessions' ? data?.sessions.nextCursor : data?.tasks.nextCursor;
  return (
    <div className="flex flex-col gap-5">
      <header className="flex flex-wrap items-start justify-between gap-4">
        <div><p className="mb-1 text-xs font-medium uppercase tracking-widest text-ink-dim">{detailed ? 'Workspace de agentes' : 'Seu trabalho, em movimento'}</p><h1 className="text-2xl font-semibold tracking-tight">{detailed ? 'Agentes e atividades' : 'Kanban de tarefas'}</h1><p className="mt-2 text-sm text-ink-mid">{detailed ? 'Tarefas e subtarefas têm status e atividade próprios. O status do trabalho e a conexão do agente são independentes.' : 'Cada cartão representa uma tarefa principal. Abra a tarefa para acompanhar suas subtarefas.'}</p></div>
        <div className="flex flex-wrap gap-2"><Button variant="outline" size="sm" onClick={refresh} aria-label="Atualizar agentes"><RefreshCw className="size-4" />Atualizar</Button><Button asChild size="sm"><Link href="/access">Conectar agente</Link></Button></div>
      </header>
      <BoardFilters params={params} onChange={changeFilter} />
      {detailed && <nav aria-label="Visão de agentes" className="flex gap-2"><Button variant={tab === 'tasks' ? 'secondary' : 'ghost'} onClick={() => changeFilter('tab', 'tasks')}>Tarefas</Button><Button variant={tab === 'sessions' ? 'secondary' : 'ghost'} onClick={() => changeFilter('tab', 'sessions')}>Sessões</Button></nav>}
      {error && <ErrorState title={data ? 'Exibindo a última atualização recebida' : 'Não foi possível carregar os agentes'} description={error} onRetry={refresh} />}
      {phase === 'loading' && !data && <div role="status" className="rounded-xl border border-line bg-surface-1 p-12 text-center text-sm text-ink-mid">Carregando seu workspace…</div>}
      {data && tab === 'tasks' && <>
        <div className="flex items-center justify-between text-xs text-ink-dim"><span>{tasks.length} tarefa{tasks.length === 1 ? '' : 's'} nesta página</span><span>Histórico: 30 dias após a última atividade</span></div>
        {tasks.length === 0 && <EmptyState icon={<Columns3 />} title={params.get('q') || params.get('status') || params.get('sessionId') ? 'Nenhuma tarefa neste filtro' : 'Seu próximo trabalho começa aqui'} description="Conecte Claude, Codex ou Gemini para acompanhar as tarefas conforme os agentes trabalham." action={<Button asChild><Link href="/access">Configurar acesso</Link></Button>} />}
        <KanbanColumns tasks={tasks} status={params.get('status')} />
      </>}
      {data && tab === 'sessions' && <SessionGrid sessions={data.sessions.items} onSelect={id => {
        const next = new URLSearchParams(params.toString());
        next.set('sessionId', id); next.set('tab', 'tasks'); next.delete('cursor');
        router.replace(`${pathname}?${next}`, { scroll: false });
      }} />}
      {data && <div className="flex items-center justify-between gap-3 text-xs text-ink-mid"><span>{nextCursor ? 'Mais resultados disponíveis; esta página não representa todo o workspace.' : 'Fim dos resultados.'}</span><div className="flex gap-2">{params.has('cursor') && <Button variant="outline" size="sm" onClick={() => changeFilter('cursor', '')}>Primeira página</Button>}{nextCursor && <Button variant="outline" size="sm" onClick={() => changeFilter('cursor', nextCursor)}>Próxima página</Button>}</div></div>}
    </div>
  );
}
