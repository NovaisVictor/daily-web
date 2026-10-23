'use client';

import Link from 'next/link';
import { useCallback, useEffect, useState } from 'react';
import { Check, Copy, KeyRound, Plug, ShieldCheck } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Dialog, DialogContent, DialogTitle } from '@/components/ui/dialog';
import { ErrorState } from '@/components/data/ErrorState';
import { accessRequest } from './request';
import { formatTime } from './contracts';

type Credential = { id: string; label: string; prefix: string; scopes: string[]; state: 'active' | 'revoked'; createdAt: string; lastUsedAt: string | null };
function credentials(value: unknown): Credential[] {
  if (!value || typeof value !== 'object' || !('items' in value) || !Array.isArray(value.items)) throw new Error('Lista de acessos inválida.');
  return value.items.map(item => {
    if (!item || typeof item !== 'object' || typeof item.id !== 'string' || typeof item.label !== 'string' || typeof item.prefix !== 'string' || !['active', 'revoked'].includes(item.state) || typeof item.createdAt !== 'string' || !Number.isFinite(Date.parse(item.createdAt)) || !Array.isArray(item.scopes) || item.scopes.some((scope: unknown) => !['agents:read', 'agents:write'].includes(String(scope))) || (item.lastUsedAt !== null && (typeof item.lastUsedAt !== 'string' || !Number.isFinite(Date.parse(item.lastUsedAt))))) throw new Error('Acesso inválido na resposta.');
    return item as Credential;
  });
}
export function CopyButton({ value, label }: { value: string; label: string }) {
  const [state, setState] = useState<'ready' | 'copied' | 'failed'>('ready');
  const copy = async () => {
    try { await navigator.clipboard.writeText(value); setState('copied'); }
    catch { setState('failed'); }
  };
  return <span className="inline-flex flex-col gap-1"><Button variant="outline" size="sm" onClick={() => void copy()}>{state === 'copied' ? <Check className="size-4" /> : <Copy className="size-4" />}{state === 'copied' ? 'Copiado' : label}</Button>{state === 'failed' && <span role="alert" className="text-xs text-destructive">Selecione o texto e copie manualmente.</span>}</span>;
}
export function AccessPanel() {
  const [items, setItems] = useState<Credential[] | null>(null);
  const [prompt, setPrompt] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [promptError, setPromptError] = useState<string | null>(null);
  const [label, setLabel] = useState('');
  const [permission, setPermission] = useState<'report' | 'read'>('report');
  const [phase, setPhase] = useState<'ready' | 'saving'>('ready');
  const [secret, setSecret] = useState<string | null>(null);
  const [revoke, setRevoke] = useState<Credential | null>(null);
  const load = useCallback(async () => {
    try { setItems(credentials(await accessRequest('/api/agent-access/tokens'))); setError(null); }
    catch (e) { setError(e instanceof Error ? e.message : 'Falha ao carregar acessos.'); }
  }, []);
  useEffect(() => { void load(); }, [load]);
  useEffect(() => {
    let mounted = true;
    void accessRequest('/api/agent-access/prompt').then(data => {
      if (!data || typeof data !== 'object' || !('prompt' in data) || typeof data.prompt !== 'string') throw new Error('Instruções inválidas na resposta.');
      if (mounted) setPrompt(data.prompt);
    }).catch(e => { if (mounted) setPromptError(e instanceof Error ? e.message : 'Falha ao carregar instruções.'); });
    return () => { mounted = false; };
  }, []);
  const create = async () => {
    setPhase('saving'); setError(null);
    try {
      const data = await accessRequest('/api/agent-access/tokens', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ label, scopes: permission === 'read' ? ['agents:read'] : ['agents:read', 'agents:write'] }) });
      if (!data || typeof data !== 'object' || !('secret' in data) || typeof data.secret !== 'string' || !data.secret || !('credential' in data)) throw new Error('Não foi possível verificar o acesso criado. Atualize a lista antes de gerar outro.');
      credentials({ items: [data.credential] });
      setSecret(data.secret); setLabel(''); await load();
    } catch (e) { setError(e instanceof Error ? e.message : 'Falha ao criar acesso.'); }
    finally { setPhase('ready'); }
  };
  const remove = async () => {
    if (!revoke) return;
    setPhase('saving'); setError(null);
    try { await accessRequest(`/api/agent-access/tokens/${encodeURIComponent(revoke.id)}`, { method: 'DELETE' }); setRevoke(null); await load(); }
    catch (e) { setError(e instanceof Error ? e.message : 'Falha ao revogar acesso.'); }
    finally { setPhase('ready'); }
  };
  return <div className="space-y-5">
    <header><p className="mb-1 text-xs font-medium uppercase tracking-widest text-ink-dim">Conecte seu workspace</p><h1 className="text-2xl font-semibold">Acesso dos agentes</h1><p className="mt-2 max-w-2xl text-sm text-ink-mid">Envie o trabalho do Claude, Codex ou Gemini ao seu kanban. Cada acesso pertence à sua conta e pode ser revogado a qualquer momento.</p></header>
    {error && <ErrorState title="Não foi possível concluir" description={error} onRetry={() => void load()} />}
    <div className="grid items-start gap-5 xl:grid-cols-2">
      <section className="space-y-5 rounded-2xl border border-line bg-surface-1 p-6"><div><h2 className="flex items-center gap-2 font-semibold"><KeyRound className="size-5 text-primary" />1. Gere um acesso para a API</h2><p className="mt-2 text-sm text-ink-mid">O token é exibido uma única vez. Guarde-o no gerenciador de segredos do seu ambiente.</p></div><form className="space-y-4" onSubmit={event => { event.preventDefault(); void create(); }}><label className="grid gap-2 text-sm">Nome do acesso<input className="h-10 rounded-lg border border-line-strong bg-surface-2 px-3" value={label} onChange={event => setLabel(event.target.value)} placeholder="Ex.: Claude no notebook" maxLength={80} required /></label><label className="grid gap-2 text-sm">Permissão<select className="h-10 rounded-lg border border-line-strong bg-surface-2 px-3" value={permission} onChange={event => setPermission(event.target.value as 'report' | 'read')}><option value="report">Consultar e reportar tarefas</option><option value="read">Somente consultar</option></select></label><Button type="submit" disabled={phase === 'saving' || !label.trim()}>{phase === 'saving' ? 'Aguarde…' : 'Gerar token'}</Button></form></section>
      <section className="space-y-4 rounded-2xl border border-line bg-surface-1 p-6"><h2 className="flex items-center gap-2 font-semibold"><Copy className="size-5 text-primary" />2. Copie as instruções para o agente</h2><p className="text-sm text-ink-mid">As instruções usam placeholders e não incluem seu token. Informe o segredo separadamente pelo ambiente seguro do agente.</p>{promptError && <p role="alert" className="text-sm text-destructive">{promptError}</p>}{prompt ? <><textarea aria-label="Instruções para o agente" readOnly value={prompt} className="h-56 w-full resize-y rounded-lg border border-line bg-surface-2 p-3 font-mono text-xs leading-relaxed" /><CopyButton value={prompt} label="Copiar instruções" /></> : !promptError && <p role="status" className="text-sm text-ink-mid">Preparando instruções…</p>}</section>
    </div>
    <section className="rounded-2xl border border-line bg-surface-1 p-6"><h2 className="mb-4 font-semibold">Tokens da API</h2>{items === null ? <p role="status" className="text-sm text-ink-mid">Carregando acessos…</p> : items.length === 0 ? <p className="text-sm text-ink-mid">Você ainda não gerou nenhum token.</p> : <ul className="divide-y divide-line">{items.map(item => <li key={item.id} className="flex flex-wrap items-center justify-between gap-3 py-4"><div><p className="text-sm font-medium">{item.label} <span className="ml-2 text-xs font-normal text-ink-dim">{item.state === 'active' ? 'Ativo' : 'Revogado'}</span></p><p className="mt-1 text-xs text-ink-mid">{item.prefix}… · {item.scopes.includes('agents:write') ? 'Consulta e envio' : 'Somente consulta'}</p><p className="mt-1 text-xs text-ink-dim">Criado em {formatTime(item.createdAt)} · {item.lastUsedAt ? `Usado em ${formatTime(item.lastUsedAt)}` : 'Ainda não utilizado'}</p></div>{item.state === 'active' && <Button variant="outline" size="sm" onClick={() => setRevoke(item)}>Revogar {item.label}</Button>}</li>)}</ul>}</section>
    <section className="space-y-3 rounded-2xl border border-line bg-surface-1 p-6"><h2 className="flex items-center gap-2 font-semibold"><Plug className="size-5 text-primary" />MCP com autorização OAuth</h2><p className="max-w-3xl text-sm text-ink-mid">O MCP usa sua autorização de login para operar tarefas, Jira e GitHub. Tokens e senhas das integrações são cadastrados apenas no navegador.</p><McpEndpoint /><Button asChild variant="outline"><Link href="/config">Gerenciar conexões</Link></Button><OAuthGrants /></section>
    <Dialog open={secret !== null} onOpenChange={open => { if (!open) setSecret(null); }}><DialogContent><DialogTitle>Guarde seu token agora</DialogTitle><p className="text-sm text-ink-mid">Este segredo não será mostrado novamente. Não o cole nas instruções nem compartilhe em conversas.</p>{secret && <><textarea readOnly aria-label="Token gerado, exibido uma única vez" value={secret} className="w-full break-all rounded-lg border border-line bg-surface-2 p-3 font-mono text-sm" /><CopyButton value={secret} label="Copiar token" /></>}<Button onClick={() => setSecret(null)}>Já guardei o token</Button></DialogContent></Dialog>
    <Dialog open={revoke !== null} onOpenChange={open => { if (!open && phase !== 'saving') setRevoke(null); }}><DialogContent><DialogTitle>Revogar {revoke?.label}?</DialogTitle><p className="text-sm text-ink-mid">O agente perde acesso na próxima chamada. As tarefas já enviadas continuam seguindo a retenção de 30 dias.</p><Button variant="destructive" disabled={phase === 'saving'} onClick={() => void remove()}>Revogar acesso</Button></DialogContent></Dialog>
  </div>;
}

interface Grant { id: string; clientId: string; clientName: string; scopes: string[]; expiresAt: string | null }
function parseGrants(value: unknown): Grant[] {
  if (!value || typeof value !== 'object' || !('grants' in value) || !Array.isArray(value.grants)) throw new Error('Lista de autorizações inválida.');
  return value.grants.map(grant => {
    if (!grant || typeof grant !== 'object' || typeof grant.id !== 'string' || typeof grant.clientId !== 'string' || typeof grant.clientName !== 'string' || !Array.isArray(grant.scopes) || grant.scopes.some((scope: unknown) => typeof scope !== 'string') || (grant.expiresAt !== null && (typeof grant.expiresAt !== 'string' || !Number.isFinite(Date.parse(grant.expiresAt))))) throw new Error('Autorização inválida na resposta.');
    return grant as Grant;
  });
}
function OAuthGrants() {
  const [grants, setGrants] = useState<Grant[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [selected, setSelected] = useState<Grant | null>(null);
  const [phase, setPhase] = useState<'ready' | 'saving'>('ready');
  const load = useCallback(async () => {
    try { setGrants(parseGrants(await accessRequest('/api/agent-access/grants'))); setError(null); }
    catch (e) { setError(e instanceof Error ? e.message : 'Falha ao carregar autorizações.'); }
  }, []);
  useEffect(() => { void load(); }, [load]);
  const revokeGrant = async () => {
    if (!selected) return;
    setPhase('saving');
    try { await accessRequest(`/api/agent-access/grants/${encodeURIComponent(selected.id)}`, { method: 'DELETE' }); setSelected(null); await load(); }
    catch (e) { setError(e instanceof Error ? e.message : 'Falha ao revogar autorização.'); }
    finally { setPhase('ready'); }
  };
  return <div className="space-y-3 border-t border-line pt-4"><h3 className="flex items-center gap-2 text-sm font-medium"><ShieldCheck className="size-4" />Clientes autorizados</h3>{error && <div role="alert" className="text-sm text-destructive">{error}<Button variant="link" size="sm" onClick={() => void load()}>Tentar novamente</Button></div>}{!grants && !error && <p role="status" className="text-xs text-ink-dim">Carregando autorizações…</p>}{grants?.length === 0 && <p className="text-sm text-ink-mid">Nenhum cliente MCP autorizado. A autorização é solicitada pelo seu cliente ao conectar.</p>}{grants && <ul className="divide-y divide-line">{grants.map(grant => <li className="flex flex-wrap items-center justify-between gap-3 py-3" key={grant.id}><div><p className="text-sm font-medium">{grant.clientName}</p><p className="mt-1 text-xs text-ink-mid">{grant.scopes.join(' · ')}</p>{grant.expiresAt && <p className="mt-1 text-xs text-ink-dim">Expira em {formatTime(grant.expiresAt)}</p>}</div><Button size="sm" variant="outline" onClick={() => setSelected(grant)}>Revogar {grant.clientName}</Button></li>)}</ul>}<Dialog open={selected !== null} onOpenChange={open => { if (!open && phase !== 'saving') setSelected(null); }}><DialogContent><DialogTitle>Revogar {selected?.clientName}?</DialogTitle><p className="text-sm text-ink-mid">O cliente MCP perde sua autorização na próxima operação.</p><Button variant="destructive" disabled={phase === 'saving'} onClick={() => void revokeGrant()}>Revogar autorização</Button>{error && <p role="alert" className="text-sm text-destructive">{error}</p>}</DialogContent></Dialog></div>;
}

function McpEndpoint() {
  const [endpoint, setEndpoint] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  useEffect(() => {
    let lifecycle: 'active' | 'disposed' = 'active';
    void accessRequest('/api/agent-access/config').then(value => {
      if (!value || typeof value !== 'object' || !('mcpUrl' in value) || typeof value.mcpUrl !== 'string') throw new Error('Endereço MCP inválido.');
      const url = new URL(value.mcpUrl);
      if (!['https:', 'http:'].includes(url.protocol) || url.pathname !== '/mcp' || url.username || url.password || url.search || url.hash) throw new Error('Endereço MCP inválido.');
      if (lifecycle === 'active') setEndpoint(url.toString());
    }).catch(reason => { if (lifecycle === 'active') setError(reason instanceof Error ? reason.message : 'Não foi possível carregar o endereço MCP.'); });
    return () => { lifecycle = 'disposed'; };
  }, []);
  if (error) return <p role="alert" className="text-sm text-destructive">{error}</p>;
  if (!endpoint) return <p role="status" className="text-sm text-ink-mid">Carregando endereço MCP…</p>;
  return <div className="flex flex-wrap items-end gap-3"><label className="grid min-w-64 flex-1 gap-2 text-sm">Endereço do servidor MCP<input readOnly value={endpoint} className="h-10 w-full rounded-lg border border-line bg-surface-2 px-3 font-mono text-xs" /></label><CopyButton value={endpoint} label="Copiar endereço MCP" /></div>;
}
