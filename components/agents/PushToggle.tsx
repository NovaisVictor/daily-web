'use client';

import { useEffect, useState } from 'react';
import { Bell, BellOff, BellRing } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { mutationHeaders } from './request';

type State = 'checking' | 'unsupported' | 'unconfigured' | 'denied' | 'off' | 'on';
const NOTES: Partial<Record<State, string>> = {
  unsupported: 'Este navegador não recebe avisos. No iPhone, instale o app pela Tela de Início.',
  unconfigured: 'Os avisos ainda não estão configurados no servidor.',
  denied: 'Avisos bloqueados nas permissões do navegador.',
};

function applicationKey(value: string): Uint8Array<ArrayBuffer> {
  const base64 = (value + '='.repeat((4 - (value.length % 4)) % 4)).replace(/-/g, '+').replace(/_/g, '/');
  const raw = atob(base64);
  const bytes = new Uint8Array(new ArrayBuffer(raw.length));
  for (let index = 0; index < raw.length; index += 1) bytes[index] = raw.charCodeAt(index);
  return bytes;
}

async function call(url: string, method: string, body?: unknown): Promise<Response> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 10000);
  try {
    return await fetch(url, { method, cache: 'no-store', signal: controller.signal, ...(body === undefined ? {} : { headers: mutationHeaders(), body: JSON.stringify(body) }) });
  } finally { clearTimeout(timer); }
}

async function registration(): Promise<ServiceWorkerRegistration> {
  return Promise.race([navigator.serviceWorker.ready, new Promise<never>((_, reject) => setTimeout(() => reject(new Error('Service worker indisponível.')), 5000))]);
}

export function PushToggle() {
  const [state, setState] = useState<State>('checking');
  const [key, setKey] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState<string | null>(null);
  useEffect(() => {
    let active = true;
    (async () => {
      if (!('serviceWorker' in navigator) || !('PushManager' in window) || !('Notification' in window)) return 'unsupported';
      const response = await call('/api/push', 'GET');
      const data: unknown = response.ok ? await response.json() : null;
      const publicKey = data && typeof data === 'object' && 'publicKey' in data && typeof data.publicKey === 'string' ? data.publicKey : null;
      if (!publicKey) return 'unconfigured';
      if (active) setKey(publicKey);
      if (Notification.permission === 'denied') return 'denied';
      const existing = await (await registration()).pushManager.getSubscription();
      if (!existing) return 'off';
      // Keeps the server in step with this browser, e.g. after the database was restored.
      await call('/api/push/subscriptions', 'POST', existing.toJSON());
      return 'on';
    })().then(next => { if (active) setState(next); }, () => { if (active) setState('off'); });
    return () => { active = false; };
  }, []);

  const run = async (work: () => Promise<State | null>, done?: string) => {
    setBusy(true); setNotice(null);
    try {
      const next = await work();
      if (next) setState(next);
      if (done) setNotice(done);
    } catch (error) {
      setNotice(error instanceof Error ? error.message : 'Não foi possível concluir.');
    } finally { setBusy(false); }
  };
  const enable = () => run(async () => {
    const permission = await Notification.requestPermission();
    if (permission !== 'granted') return permission === 'denied' ? 'denied' : 'off';
    const subscription = await (await registration()).pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: applicationKey(key ?? '') });
    const response = await call('/api/push/subscriptions', 'POST', subscription.toJSON());
    if (!response.ok) { await subscription.unsubscribe(); throw new Error('O servidor recusou este dispositivo.'); }
    return 'on';
  }, 'Avisos ativados neste dispositivo.');
  const disable = () => run(async () => {
    const subscription = await (await registration()).pushManager.getSubscription();
    if (subscription) {
      await call('/api/push/subscriptions', 'DELETE', { endpoint: subscription.endpoint });
      await subscription.unsubscribe();
    }
    return 'off';
  }, 'Avisos desativados neste dispositivo.');
  const test = () => run(async () => {
    const response = await call('/api/push/test', 'POST', {});
    if (!response.ok) throw new Error('Não foi possível enviar o aviso de teste.');
    return null;
  }, 'Aviso de teste enviado.');

  if (state === 'checking') return null;
  return <div className="flex flex-wrap items-center gap-2">
    {state === 'off' && <Button variant="outline" size="sm" disabled={busy} onClick={() => void enable()}><Bell className="size-4" />Ativar avisos</Button>}
    {state === 'on' && <>
      <Button variant="outline" size="sm" disabled={busy} onClick={() => void test()} title="Envia um aviso de teste para os seus dispositivos"><BellRing className="size-4" />Testar aviso</Button>
      <Button variant="ghost" size="sm" disabled={busy} onClick={() => void disable()} aria-label="Desativar avisos neste dispositivo"><BellOff className="size-4" /></Button>
    </>}
    {NOTES[state] && <span className="text-xs text-ink-dim">{NOTES[state]}</span>}
    {notice && <span role="status" className="text-xs text-ink-mid">{notice}</span>}
  </div>;
}
