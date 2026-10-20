'use client';

import { createContext, useContext, type ReactNode } from 'react';

/** Quem está sendo olhado no painel. Escrever na issue usa sempre o token de
 *  quem está logado; aprovar só faz sentido na própria fila. */
export type JiraViewer = { kind: 'self' } | { kind: 'person'; name: string };

export interface JiraActionsValue {
  viewer: JiraViewer;
  /** Pede o estado de novo depois de uma escrita aceita pelo Jira. */
  onChanged: () => void;
}

const JiraActionsContext = createContext<JiraActionsValue>({
  viewer: { kind: 'self' },
  onChanged: () => {},
});

export function JiraActionsProvider({ value, children }: { value: JiraActionsValue; children: ReactNode }) {
  return <JiraActionsContext.Provider value={value}>{children}</JiraActionsContext.Provider>;
}

export function useJiraActions(): JiraActionsValue {
  return useContext(JiraActionsContext);
}

/** POST/PUT para uma rota de escrita do Jira. Devolve o erro que o servidor
 *  mandou — que, numa recusa do Jira, é a frase do próprio Jira. */
export async function sendJiraWrite(
  url: string,
  method: 'POST' | 'PUT' | 'DELETE',
  body?: unknown,
): Promise<{ ok: true; data: Record<string, unknown> } | { ok: false; error: string }> {
  const res = await fetch(url, {
    method,
    headers: body === undefined ? undefined : { 'Content-Type': 'application/json' },
    body: body === undefined ? undefined : JSON.stringify(body),
  }).catch(() => null);
  if (!res) return { ok: false, error: 'sem resposta do servidor' };
  const data = (await res.json().catch(() => ({}))) as Record<string, unknown>;
  if (!res.ok) return { ok: false, error: typeof data.error === 'string' ? data.error : `falha (${res.status})` };
  return { ok: true, data };
}
