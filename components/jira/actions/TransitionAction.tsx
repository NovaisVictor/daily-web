'use client';

import { useState, type ReactNode } from 'react';
import { ExternalLink } from 'lucide-react';
import type { JiraItem } from '@/lib/types';
import type { JiraTransition } from '@/lib/integrations/jira/transitions';
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover';
import { Button } from '@/components/ui/button';
import { cn } from '@/lib/utils';
import { focusRing } from '@/lib/theme';
import { sendJiraWrite, useJiraActions } from './context';

type Sending = 'idle' | 'sending';

type View =
  | { kind: 'loading' }
  | { kind: 'failed'; error: string }
  | { kind: 'choosing'; transitions: JiraTransition[] }
  | {
      kind: 'confirming';
      transitions: JiraTransition[];
      chosen: JiraTransition;
      sending: Sending;
      refusal: string | null;
    };

function transitionsUrl(key: string): string {
  return `/api/jira/issues/${encodeURIComponent(key)}/transitions`;
}

const CATEGORIES: readonly unknown[] = ['new', 'indeterminate', 'done'];
const REQUIREMENTS: readonly unknown[] = ['nothing', 'screen'];

function isTransition(value: unknown): value is JiraTransition {
  if (typeof value !== 'object' || value === null) return false;
  const t = value as Record<string, unknown>;
  const to = t.to as Record<string, unknown> | null | undefined;
  return (
    typeof t.id === 'string' &&
    typeof t.name === 'string' &&
    typeof to === 'object' &&
    to !== null &&
    typeof to.name === 'string' &&
    CATEGORIES.includes(to.category) &&
    REQUIREMENTS.includes(t.requires)
  );
}

async function loadTransitions(key: string): Promise<View> {
  const res = await fetch(transitionsUrl(key)).catch(() => null);
  if (!res) return { kind: 'failed', error: 'sem resposta do servidor' };
  const data = (await res.json().catch(() => ({}))) as { transitions?: unknown; error?: unknown };
  if (!res.ok) {
    return { kind: 'failed', error: typeof data.error === 'string' ? data.error : `falha (${res.status})` };
  }
  if (!Array.isArray(data.transitions) || !data.transitions.every(isTransition)) {
    return { kind: 'failed', error: 'resposta inesperada do servidor' };
  }
  return { kind: 'choosing', transitions: data.transitions };
}

const optionClass = cn(
  'flex w-full flex-col items-start gap-0.5 rounded-md px-2 py-1.5 text-left text-sm hover:bg-muted',
  focusRing,
);

function OpenInJira({ issue }: { issue: JiraItem }) {
  return (
    <a
      href={issue.url}
      target="_blank"
      rel="noreferrer"
      className={cn('inline-flex items-center gap-1 text-brand hover:underline', focusRing)}
    >
      abrir no Jira
      <ExternalLink aria-hidden className="size-3" />
    </a>
  );
}

/** The status on the row, as a picker of the transitions Jira allows from it. */
export function TransitionAction({ issue, children }: { issue: JiraItem; children: ReactNode }) {
  const { onChanged } = useJiraActions();
  const [open, setOpen] = useState(false);
  const [view, setView] = useState<View>({ kind: 'loading' });

  const load = async () => {
    setView({ kind: 'loading' });
    setView(await loadTransitions(issue.key));
  };

  const onOpenChange = (next: boolean) => {
    setOpen(next);
    if (next) void load();
  };

  const confirm = async () => {
    if (view.kind !== 'confirming' || view.sending === 'sending') return;
    const pending = { ...view, sending: 'sending' as const, refusal: null };
    setView(pending);
    const result = await sendJiraWrite(transitionsUrl(issue.key), 'POST', { transitionId: view.chosen.id });
    if (!result.ok) {
      setView({ ...pending, sending: 'idle', refusal: result.error });
      return;
    }
    setOpen(false);
    onChanged();
  };

  return (
    <Popover open={open} onOpenChange={onOpenChange}>
      <PopoverTrigger asChild>
        <button
          type="button"
          aria-label={`mudar status de ${issue.key} (${issue.status})`}
          className={cn('-mx-1 rounded-sm px-1 hover:bg-muted', focusRing)}
        >
          {children}
        </button>
      </PopoverTrigger>
      <PopoverContent align="start" className="w-72 p-2 type-caption">
        {view.kind === 'loading' && (
          <p role="status" className="px-2 py-1.5 text-ink-dim">
            carregando transições…
          </p>
        )}

        {view.kind === 'failed' && (
          <div role="alert" className="flex flex-col gap-2 px-2 py-1.5">
            <p className="text-danger">{view.error}</p>
            <Button size="sm" variant="outline" onClick={() => void load()}>
              Tentar de novo
            </Button>
          </div>
        )}

        {view.kind === 'choosing' &&
          (view.transitions.length === 0 ? (
            <p className="px-2 py-1.5 text-ink-dim">nenhuma transição disponível</p>
          ) : (
            <ul aria-label={`transições de ${issue.key}`} className="flex flex-col">
              {view.transitions.map((t) => {
                const label = (
                  <>
                    <span className="text-ink">{t.name}</span>
                    {t.to.name !== t.name && <span className="text-ink-dim">→ {t.to.name}</span>}
                  </>
                );
                return (
                  <li key={t.id}>
                    {t.requires === 'screen' ? (
                      <a href={issue.url} target="_blank" rel="noreferrer" className={optionClass}>
                        {label}
                        <span className="text-warning">pede campos — abrir no Jira</span>
                      </a>
                    ) : (
                      <button
                        type="button"
                        className={optionClass}
                        onClick={() =>
                          setView({
                            kind: 'confirming',
                            transitions: view.transitions,
                            chosen: t,
                            sending: 'idle',
                            refusal: null,
                          })
                        }
                      >
                        {label}
                      </button>
                    )}
                  </li>
                );
              })}
            </ul>
          ))}

        {view.kind === 'confirming' && (
          <div className="flex flex-col gap-2 px-2 py-1.5">
            <p className="text-sm text-ink">
              Mover {issue.key} de {issue.status} para {view.chosen.to.name}?
            </p>
            {view.refusal && (
              <p role="alert" className="text-danger">
                {view.refusal} · <OpenInJira issue={issue} />
              </p>
            )}
            <div className="flex justify-end gap-2">
              <Button
                size="sm"
                variant="ghost"
                disabled={view.sending === 'sending'}
                onClick={() => setView({ kind: 'choosing', transitions: view.transitions })}
              >
                Cancelar
              </Button>
              <Button size="sm" disabled={view.sending === 'sending'} onClick={() => void confirm()}>
                {view.sending === 'sending' ? 'Movendo…' : 'Confirmar'}
              </Button>
            </div>
          </div>
        )}
      </PopoverContent>
    </Popover>
  );
}
