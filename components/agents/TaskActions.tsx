'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { Button } from '@/components/ui/button';
import { Dialog, DialogContent, DialogTitle } from '@/components/ui/dialog';
import { HOLD_NOTE_MAX, holdReasons, transitions, type HeldStatus } from '@/lib/agents/model';
import { HOLD_LABELS, type AgentTask, type TaskStatus } from './contracts';
import { accessRequest, mutationHeaders } from './request';

const actionLabels: Record<TaskStatus, string> = { queued: 'Retornar à fila', working: 'Iniciar', waiting: 'Aguardar processo', blocked: 'Bloquear', completed: 'Concluir', failed: 'Marcar falha', cancelled: 'Cancelar' };
export function TaskActions({ task, onChanged }: { task: AgentTask; onChanged: () => void }) {
  const router = useRouter();
  const [mode, setMode] = useState<'idle' | 'edit' | 'delete' | HeldStatus>('idle');
  const [reason, setReason] = useState('');
  const [note, setNote] = useState('');
  const [phase, setPhase] = useState<'ready' | 'saving'>('ready');
  const [error, setError] = useState<string | null>(null);
  const [title, setTitle] = useState(task.title);
  const [description, setDescription] = useState(task.description);
  const [editVersion, setEditVersion] = useState(task.version);
  const change = async (method: string, body?: unknown, suffix = '') => {
    setError(null); setPhase('saving');
    try {
      await accessRequest(`/api/agents/tasks/${encodeURIComponent(task.id)}${suffix}`, { method, headers: mutationHeaders(), ...(body === undefined ? {} : { body: JSON.stringify(body) }) });
      setMode('idle');
      if (method === 'DELETE') router.push('/kanban'); else onChanged();
    } catch (e) { setError(e instanceof Error ? e.message : 'Falha ao alterar tarefa.'); }
    finally { setPhase('ready'); }
  };
  return <div className="mt-5 space-y-3 border-t border-line pt-4">
    <div className="flex flex-wrap gap-2">{transitions[task.status].map(status => <Button key={status} size="sm" variant="outline" disabled={phase === 'saving'} onClick={() => { if (status in holdReasons) { setReason(''); setNote(''); setMode(status as HeldStatus); } else void change('POST', { status, expectedVersion: task.version }, '/transitions'); }}>{status === 'queued' && ['completed', 'failed', 'cancelled'].includes(task.status) ? 'Reabrir tarefa' : status === task.status ? 'Trocar motivo' : actionLabels[status]}</Button>)}<Button size="sm" variant="ghost" onClick={() => { setTitle(task.title); setDescription(task.description); setEditVersion(task.version); setMode('edit'); }}>Editar</Button><Button size="sm" variant="ghost" onClick={() => setMode('delete')}>Excluir</Button></div>
    {error && <p role="alert" className="text-sm text-destructive">{error}</p>}
    <Dialog open={mode !== 'idle'} onOpenChange={open => { if (!open && phase !== 'saving') setMode('idle'); }}><DialogContent><DialogTitle>{mode === 'delete' ? 'Excluir esta tarefa?' : mode === 'edit' ? 'Editar tarefa' : mode === 'waiting' ? 'Aguardando o quê?' : 'Por que está bloqueada?'}</DialogTitle>{mode === 'waiting' || mode === 'blocked' ? <form className="space-y-4" onSubmit={event => { event.preventDefault(); void change('POST', { status: mode, hold: { reason, note: note.trim() || null }, expectedVersion: task.version }, '/transitions'); }}><label className="grid gap-2 text-sm">Motivo<select className="rounded-lg border border-line bg-surface-2 p-2" value={reason} onChange={event => setReason(event.target.value)} required><option value="" disabled>Escolha um motivo</option>{holdReasons[mode].map(value => <option key={value} value={value}>{HOLD_LABELS[mode][value]}</option>)}</select></label><label className="grid gap-2 text-sm">Detalhe{reason === 'other' ? '' : ' (opcional)'}<input className="rounded-lg border border-line bg-surface-2 p-2" value={note} onChange={event => setNote(event.target.value)} maxLength={HOLD_NOTE_MAX} required={reason === 'other'} placeholder={mode === 'waiting' ? 'Ex.: PR #81' : 'Ex.: escolher entre A e B'} /></label><Button type="submit" disabled={phase === 'saving' || !reason || (reason === 'other' && !note.trim())}>{actionLabels[mode]}</Button></form> : mode === 'delete' ? <><p className="text-sm text-ink-mid">A tarefa “{task.title}” e seu histórico serão removidos. O item vinculado no Jira ou GitHub permanece.</p><Button variant="destructive" disabled={phase === 'saving'} onClick={() => void change('DELETE')}>Excluir tarefa</Button></> : <form className="space-y-4" onSubmit={event => { event.preventDefault(); void change('PATCH', { title, description, expectedVersion: editVersion }); }}><label className="grid gap-2 text-sm">Título<input className="rounded-lg border border-line bg-surface-2 p-2" value={title} onChange={event => setTitle(event.target.value)} required maxLength={200} /></label><label className="grid gap-2 text-sm">Descrição<textarea className="min-h-28 rounded-lg border border-line bg-surface-2 p-2" value={description} onChange={event => setDescription(event.target.value)} maxLength={4000} /></label><Button type="submit" disabled={phase === 'saving' || !title.trim()}>Salvar alterações</Button></form>}{error && <p role="alert" className="text-sm text-destructive">{error}</p>}</DialogContent></Dialog>
  </div>;
}
