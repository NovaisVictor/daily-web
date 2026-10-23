import { Suspense } from 'react';
import { AgentBoard } from '@/components/agents/AgentBoard';

export default function AgentsPage() {
  return <Suspense fallback={<p role="status">Carregando agentes…</p>}><AgentBoard mode="workspace" /></Suspense>;
}
