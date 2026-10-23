import { Suspense } from 'react';
import { AgentBoard } from '@/components/agents/AgentBoard';

export default function HomePage() {
  return <Suspense fallback={<p role="status">Carregando tarefas…</p>}><AgentBoard /></Suspense>;
}
