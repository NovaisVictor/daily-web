'use client';

import { useCallback, useEffect, useState } from 'react';

type LoadState<T> = { data: T | null; error: string | null; phase: 'loading' | 'ready' | 'error' };

function subscribe<T>(url: string, parse: (value: unknown) => T, update: (state: LoadState<T>) => void): () => void {
  let lifecycle: 'active' | 'disposed' = 'active';
  let request: AbortController | null = null;
  let deadline: ReturnType<typeof setTimeout> | undefined;
  let data: T | null = null;
  update({ data, error: null, phase: 'loading' });
  const load = async () => {
    if (lifecycle === 'disposed' || document.visibilityState === 'hidden' || request) return;
    const controller = new AbortController();
    request = controller;
    deadline = setTimeout(() => controller.abort(), 5000);
    try {
      const response = await fetch(url, { cache: 'no-store', signal: controller.signal });
      if (request !== controller) return;
      if ([401, 403, 404].includes(response.status)) data = null;
      if (!response.ok) throw new Error(response.status === 401 ? 'Sua sessão expirou. Entre novamente.' : response.status === 404 ? 'Este item não está disponível ou expirou.' : 'Não foi possível atualizar os dados.');
      const next = parse(await response.json());
      if (lifecycle === 'active' && request === controller) { data = next; update({ data, error: null, phase: 'ready' }); }
    } catch (error) {
      if (lifecycle === 'active' && request === controller) update({ data, phase: 'error', error: error instanceof Error ? error.message : 'Falha de conexão.' });
    } finally {
      if (request === controller) { clearTimeout(deadline); request = null; }
    }
  };
  const visibility = () => {
    request?.abort(); request = null; clearTimeout(deadline);
    if (document.visibilityState === 'visible') void load();
  };
  const interval = setInterval(() => void load(), 2000);
  document.addEventListener('visibilitychange', visibility);
  void load();
  return () => {
    lifecycle = 'disposed'; clearInterval(interval); clearTimeout(deadline);
    request?.abort(); request = null; document.removeEventListener('visibilitychange', visibility);
  };
}

export function useAgentPolling<T>(url: string, parse: (value: unknown) => T) {
  const [state, setState] = useState<LoadState<T>>({ data: null, error: null, phase: 'loading' });
  const [revision, setRevision] = useState(0);
  const refresh = useCallback(() => setRevision(value => value + 1), []);
  useEffect(() => subscribe(url, parse, setState), [url, parse, revision]);
  return { ...state, refresh };
}
