import { Suspense } from 'react';
import { TaskDetail } from '@/components/agents/TaskDetail';

export default async function AgentTaskPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return <Suspense fallback={<p role="status">Carregando tarefa…</p>}><TaskDetail id={id} /></Suspense>;
}
