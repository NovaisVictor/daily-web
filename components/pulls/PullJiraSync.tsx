'use client';

import { useRef, useState } from 'react';
import { ExternalLink } from 'lucide-react';
import type { PullJiraRef, PullRequestItem } from '@/lib/types';
import type { JiraTransition } from '@/lib/integrations/jira/transitions';
import { INTENT_LABEL, jiraSyncSuggestion, type SyncIntent } from '@/lib/pullJiraSync';
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover';
import { Button } from '@/components/ui/button';
import { sendJiraWrite } from '@/components/jira/actions/context';
import { cn } from '@/lib/utils';
import { focusRing } from '@/lib/theme';
import { usePullsActions } from './context';

const SYNC_URL = '/api/pulls/jira-sync';

type View =
  | { kind: 'loading' }
  | { kind: 'failed'; error: string }
  | { kind: 'confirming'; transition: JiraTransition; sending: 'idle' | 'sending'; refusal: string | null };

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

async function loadTarget(key: string, intent: SyncIntent): Promise<View> {
  const query = new URLSearchParams({ key, intent });
  const res = await fetch(`${SYNC_URL}?${query}`).catch(() => null);
  if (!res) return { kind: 'failed', error: 'sem resposta do servidor' };
  const data = (await res.json().catch(() => ({}))) as { transition?: unknown; error?: unknown };
  if (!res.ok) {
    return { kind: 'failed', error: typeof data.error === 'string' ? data.error : `falha (${res.status})` };
  }
  if (!isTransition(data.transition)) return { kind: 'failed', error: 'resposta inesperada do servidor' };
  return { kind: 'confirming', transition: data.transition, sending: 'idle', refusal: null };
}

function OpenInJira({ jira }: { jira: PullJiraRef }) {
  return (
    <a
      href={jira.url}
      target="_blank"
      rel="noreferrer"
      className={cn('inline-flex items-center gap-1 text-brand hover:underline', focusRing)}
    >
      abrir no Jira
      <ExternalLink aria-hidden className="size-3" />
    </a>
  );
}

function MoveCard({ jira, intent }: { jira: PullJiraRef; intent: SyncIntent }) {
  const { onChanged } = usePullsActions();
  const [open, setOpen] = useState(false);
  const [view, setView] = useState<View>({ kind: 'loading' });
  const request = useRef(0);
  const label = INTENT_LABEL[intent];

  const load = async () => {
    const id = ++request.current;
    setView({ kind: 'loading' });
    const next = await loadTarget(jira.key, intent);
    if (request.current === id) setView(next);
  };

  const onOpenChange = (next: boolean) => {
    setOpen(next);
    if (next) void load();
  };

  const confirm = async () => {
    if (view.kind !== 'confirming' || view.sending === 'sending') return;
    const pending = { ...view, sending: 'sending' as const, refusal: null };
    setView(pending);
    const result = await sendJiraWrite(SYNC_URL, 'POST', { key: jira.key, transitionId: view.transition.id });
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
          aria-label={`mover ${jira.key} para ${label}`}
          className={cn('shrink-0 rounded-sm px-1 type-caption text-brand hover:bg-muted', focusRing)}
        >
          {jira.key} → {label}
        </button>
      </PopoverTrigger>
      <PopoverContent align="start" className="w-72 p-2 type-caption">
        {view.kind === 'loading' && (
          <p role="status" className="px-2 py-1.5 text-ink-dim">
            procurando a transição…
          </p>
        )}

        {view.kind === 'failed' && (
          <div role="alert" className="flex flex-col gap-2 px-2 py-1.5">
            <p className="text-danger">{view.error}</p>
            <OpenInJira jira={jira} />
          </div>
        )}

        {view.kind === 'confirming' &&
          (view.transition.requires === 'screen' ? (
            <div className="flex flex-col gap-2 px-2 py-1.5">
              <p className="text-sm text-ink">
                {view.transition.name} → {view.transition.to.name}
              </p>
              <a
                href={jira.url}
                target="_blank"
                rel="noreferrer"
                className={cn('text-warning hover:underline', focusRing)}
              >
                pede campos — abrir no Jira
              </a>
            </div>
          ) : (
            <div className="flex flex-col gap-2 px-2 py-1.5">
              <p className="text-sm text-ink">
                Mover {jira.key} de {jira.status} para {view.transition.to.name}?
              </p>
              {view.refusal && (
                <p role="alert" className="text-danger">
                  {view.refusal} · <OpenInJira jira={jira} />
                </p>
              )}
              <div className="flex justify-end gap-2">
                <Button
                  size="sm"
                  variant="ghost"
                  disabled={view.sending === 'sending'}
                  onClick={() => setOpen(false)}
                >
                  Cancelar
                </Button>
                <Button size="sm" disabled={view.sending === 'sending'} onClick={() => void confirm()}>
                  {view.sending === 'sending' ? 'Movendo…' : 'Confirmar'}
                </Button>
              </div>
            </div>
          ))}
      </PopoverContent>
    </Popover>
  );
}

function Diverged({ jira, item }: { jira: PullJiraRef; item: PullRequestItem }) {
  return (
    <span className="shrink-0 type-caption text-warning">
      <a href={jira.url} target="_blank" rel="noreferrer" className={cn('hover:underline', focusRing)}>
        {jira.key}
      </a>
      {': card concluído com '}
      <a href={item.url} target="_blank" rel="noreferrer" className={cn('hover:underline', focusRing)}>
        PR aberto
      </a>
    </span>
  );
}

export function PullJiraSync({ item }: { item: PullRequestItem }) {
  return (
    <>
      {item.jira?.map((jira) => {
        const suggestion = jiraSyncSuggestion(item, jira);
        if (!suggestion) return null;
        if (suggestion.kind === 'diverged') return <Diverged key={jira.key} jira={jira} item={item} />;
        return <MoveCard key={jira.key} jira={jira} intent={suggestion.intent} />;
      })}
    </>
  );
}
