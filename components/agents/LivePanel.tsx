'use client';

import { useEffect, useRef, useState } from 'react';
import { usePathname, useRouter, useSearchParams } from 'next/navigation';
import { Send, TerminalSquare } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Textarea } from '@/components/ui/textarea';
import { formatTime, LIVE_LABELS, LIVE_TONES, parseTerminal, waitedFor } from './contracts';
import { mutationHeaders } from './request';
import { useAgentPolling } from './useAgentPolling';

const UNAVAILABLE = {
  not_enabled: 'O terminal ao vivo não está habilitado para a sua conta neste servidor.',
  not_local: 'Esta sessão não roda no agent-deck deste servidor (por exemplo, uma sessão no Mac). Aqui aparecem só os relatos do agente.',
  unavailable: 'Não foi possível ler o terminal agora. Tentando de novo…',
} as const;
const SEND_ERRORS: Record<string, string> = {
  terminal_not_local: 'Esta sessão não roda neste servidor.',
  terminal_not_enabled: 'O envio não está habilitado para a sua conta.',
  session_stopped: 'A sessão do agente está encerrada.',
  uncertain_outcome: 'Não deu para confirmar a entrega. Confira o terminal antes de reenviar.',
  idempotency_conflict: 'Não deu para confirmar a entrega. Confira o terminal antes de reenviar.',
  send_refused: 'O agent-deck recusou a mensagem. Tente de novo.',
  deck_unavailable: 'O agent-deck não respondeu. Tente de novo.',
  operation_pending: 'O envio anterior ainda está em andamento.',
  unauthenticated: 'Sua sessão expirou. Entre novamente.',
};

async function deliver(sessionId: string, text: string, key: string): Promise<void> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 20000);
  try {
    const response = await fetch(`/api/agents/sessions/${encodeURIComponent(sessionId)}/messages`, { method: 'POST', headers: { ...mutationHeaders(), 'Idempotency-Key': key }, body: JSON.stringify({ text }), cache: 'no-store', signal: controller.signal });
    if (response.ok) return;
    const detail: unknown = await response.json().catch(() => null);
    const error = detail && typeof detail === 'object' && 'error' in detail ? detail.error : null;
    const code = error && typeof error === 'object' && 'code' in error ? String(error.code) : '';
    throw new Error(SEND_ERRORS[code] ?? 'Não foi possível enviar a mensagem.');
  } finally { clearTimeout(timer); }
}

export function LivePanel({ sessionId }: { sessionId: string }) {
  const params = useSearchParams();
  const router = useRouter();
  const pathname = usePathname();
  const view = params.get('live') === 'response' ? 'response' : 'pane';
  const { data, error } = useAgentPolling(`/api/agents/sessions/${encodeURIComponent(sessionId)}/live`, parseTerminal);
  const screen = useRef<HTMLPreElement>(null);
  const pinned = useRef(true);
  const [text, setText] = useState('');
  const key = useRef('');
  const [phase, setPhase] = useState<'ready' | 'sending'>('ready');
  const [notice, setNotice] = useState<{ tone: 'ok' | 'error'; text: string } | null>(null);
  const pane = data?.available ? data.pane : '';
  useEffect(() => {
    const node = screen.current;
    if (node && pinned.current) node.scrollTop = node.scrollHeight;
  }, [pane, view]);
  const switchView = (next: 'pane' | 'response') => {
    const query = new URLSearchParams(params.toString());
    if (next === 'pane') query.delete('live'); else query.set('live', next);
    router.replace(`${pathname}${query.size ? `?${query}` : ''}`, { scroll: false });
  };
  const send = async () => {
    const message = text.trim();
    if (!message || phase === 'sending') return;
    setPhase('sending'); setNotice(null);
    try {
      key.current ||= crypto.randomUUID();
      await deliver(sessionId, message, key.current);
      setText(''); key.current = ''; pinned.current = true;
      setNotice({ tone: 'ok', text: 'Mensagem na fila: o agente recebe assim que o terminal estiver pronto.' });
    } catch (e) {
      setNotice({ tone: 'error', text: e instanceof Error && e.name !== 'AbortError' ? e.message : SEND_ERRORS.uncertain_outcome });
    } finally { setPhase('ready'); }
  };
  return <section aria-labelledby="live-title" className="rounded-2xl border border-line bg-surface-1 p-5">
    <div className="mb-3 flex flex-wrap items-center justify-between gap-3">
      <h2 id="live-title" className="flex items-center gap-2 font-semibold"><TerminalSquare className="size-4" />Sessão ao vivo</h2>
      {data?.available && <span className="flex items-center gap-2 text-xs text-ink-mid"><span aria-hidden className={`size-2 rounded-full ${LIVE_TONES[data.live.state]} ${data.live.state === 'working' ? 'motion-safe:animate-pulse' : ''}`} />{LIVE_LABELS[data.live.state]}{data.live.since && <span className="text-ink-dim">· última atividade {waitedFor(data.live.since)}</span>}</span>}
    </div>
    {!data && !error && <p role="status" className="text-sm text-ink-mid">Conectando ao terminal…</p>}
    {error && <p role="alert" className="text-sm text-danger">{error}</p>}
    {data && !data.available && <p className="text-sm text-ink-mid">{UNAVAILABLE[data.reason]}</p>}
    {data?.available && <>
      <nav aria-label="Conteúdo da sessão" className="mb-2 flex gap-2">
        <Button size="sm" variant={view === 'pane' ? 'secondary' : 'ghost'} onClick={() => switchView('pane')}>Terminal</Button>
        <Button size="sm" variant={view === 'response' ? 'secondary' : 'ghost'} onClick={() => switchView('response')}>Última resposta</Button>
      </nav>
      <pre ref={screen} onScroll={event => { const node = event.currentTarget; pinned.current = node.scrollHeight - node.scrollTop - node.clientHeight < 24; }} aria-live="off" className="max-h-[32rem] min-h-40 overflow-auto rounded-xl border border-line bg-surface-2 p-3 font-mono text-xs leading-relaxed whitespace-pre-wrap break-words text-ink">
        {view === 'pane' ? (data.pane || 'Terminal vazio.') : (data.response?.content || 'Nenhuma resposta registrada ainda.')}
      </pre>
      <p className="mt-1 text-[11px] text-ink-dim">{view === 'response' && data.response?.at ? `Resposta de ${formatTime(data.response.at)} · ` : ''}Atualizado {formatTime(data.capturedAt)}. Nada disso fica salvo no servidor.</p>
      <form className="mt-4 flex flex-col gap-2" onSubmit={event => { event.preventDefault(); void send(); }}>
        <label htmlFor="live-message" className="text-sm font-medium">Responder ao agente</label>
        <Textarea id="live-message" value={text} onChange={event => { key.current = ''; setText(event.target.value); }} onKeyDown={event => { if (event.key === 'Enter' && (event.metaKey || event.ctrlKey)) { event.preventDefault(); void send(); } }} maxLength={4000} rows={3} placeholder="Escreva como se estivesse no terminal. Ctrl+Enter envia." disabled={data.live.state === 'stopped'} />
        <div className="flex flex-wrap items-center justify-between gap-2">
          <span className={`text-xs ${notice?.tone === 'error' ? 'text-danger' : 'text-ink-mid'}`} role={notice ? 'status' : undefined}>{notice?.text ?? (data.live.state === 'working' ? 'O agente está trabalhando; a mensagem espera o fim do turno.' : data.live.state === 'prompt' ? 'Há um menu aberto no terminal; a mensagem é entregue quando ele fechar.' : '')}</span>
          <Button type="submit" size="sm" disabled={phase === 'sending' || !text.trim() || data.live.state === 'stopped'}><Send className="size-4" />{phase === 'sending' ? 'Enviando…' : 'Enviar'}</Button>
        </div>
      </form>
    </>}
  </section>;
}
