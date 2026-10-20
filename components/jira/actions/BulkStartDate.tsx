'use client';

import { useState } from 'react';
import { Button } from '@/components/ui/button';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { cn } from '@/lib/utils';
import { focusRing } from '@/lib/theme';
import { START_DATE_BATCH } from '@/lib/jiraLimits';
import { isCalendarDate } from '@/lib/integrations/jira/parse';
import type { JiraProblem, JiraProblemItem } from '@/lib/types';
import type { StartDateResult, StartDateSource, StartDateSuggestion } from '@/lib/integrations/jira/startDates';
import { sendJiraWrite, useJiraActions } from './context';

const MISSING_START: readonly JiraProblem[] = ['story-in-progress-without-start', 'story-done-without-start'];

const SOURCE_HINT: Record<StartDateSource, string> = {
  changelog: 'primeira vez em andamento',
  created: 'data de criação',
};

type Inclusion = 'included' | 'excluded';

type Row =
  | { key: string; summary: string; kind: 'editable'; date: string; source: StartDateSource; inclusion: Inclusion }
  | { key: string; summary: string; kind: 'unavailable'; error: string };

type Phase =
  | { kind: 'closed' }
  | { kind: 'loading' }
  | { kind: 'failed'; error: string }
  | { kind: 'review'; rows: Row[]; error: string | null }
  | { kind: 'writing'; rows: Row[] }
  | { kind: 'written'; rows: Row[]; results: Map<string, StartDateResult>; error: string | null };

function today(): string {
  const now = new Date();
  const pad = (n: number) => String(n).padStart(2, '0');
  return `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}`;
}

function isWritableDate(value: string, limit: string): boolean {
  return isCalendarDate(value) && value <= limit;
}

function isSuggestion(value: unknown): value is StartDateSuggestion {
  if (typeof value !== 'object' || value === null) return false;
  const s = value as Record<string, unknown>;
  if (typeof s.key !== 'string') return false;
  if (s.status === 'failed') return typeof s.error === 'string';
  return s.status === 'suggested' && typeof s.date === 'string' && (s.source === 'changelog' || s.source === 'created');
}

function isResult(value: unknown): value is StartDateResult {
  if (typeof value !== 'object' || value === null) return false;
  const r = value as Record<string, unknown>;
  return typeof r.key === 'string' && (r.outcome === 'written' || r.outcome === 'refused');
}

/** The server takes at most START_DATE_BATCH keys per request. */
function batches<T>(list: T[]): T[][] {
  const out: T[][] = [];
  for (let i = 0; i < list.length; i += START_DATE_BATCH) out.push(list.slice(i, i + START_DATE_BATCH));
  return out;
}

async function loadBatch(keys: string[]): Promise<StartDateSuggestion[] | string> {
  const res = await fetch(`/api/jira/problems/start-dates?keys=${encodeURIComponent(keys.join(','))}`).catch(
    () => null,
  );
  if (!res) return 'sem resposta do servidor';
  const data = (await res.json().catch(() => ({}))) as { suggestions?: unknown; error?: unknown };
  if (!res.ok) return typeof data.error === 'string' ? data.error : `falha (${res.status})`;
  if (!Array.isArray(data.suggestions) || !data.suggestions.every(isSuggestion)) {
    return 'resposta inesperada do servidor';
  }
  return data.suggestions;
}

async function loadSuggestions(keys: string[]): Promise<StartDateSuggestion[] | string> {
  const all: StartDateSuggestion[] = [];
  for (const batch of batches(keys)) {
    const loaded = await loadBatch(batch);
    if (typeof loaded === 'string') return loaded;
    all.push(...loaded);
  }
  return all;
}

async function writeBatch(items: { key: string; date: string }[]): Promise<StartDateResult[] | string> {
  const res = await sendJiraWrite('/api/jira/problems/start-dates', 'POST', { items });
  if (!res.ok) return res.error;
  const raw = res.data.results;
  if (!Array.isArray(raw) || !raw.every(isResult)) return 'resposta inesperada do servidor';
  return raw;
}

/** Writes are kept to the viewer's own stories: a bulk edit on a colleague's
 *  issues is too easy to do by accident from their view. */
export function BulkStartDate({ problems }: { problems: JiraProblemItem[] }) {
  const { viewer, onChanged } = useJiraActions();
  const [phase, setPhase] = useState<Phase>({ kind: 'closed' });

  const missing = problems.filter((issue) => issue.problems.some((p) => MISSING_START.includes(p)));
  if (viewer.kind !== 'self' || missing.length === 0) return null;

  const limit = today();
  const writable = (rows: Row[]) =>
    rows.flatMap((row) =>
      row.kind === 'editable' && row.inclusion === 'included' && isWritableDate(row.date, limit)
        ? [{ key: row.key, date: row.date }]
        : [],
    );

  const open = async () => {
    setPhase({ kind: 'loading' });
    const loaded = await loadSuggestions(missing.map((issue) => issue.key));
    if (typeof loaded === 'string') {
      setPhase({ kind: 'failed', error: loaded });
      return;
    }
    const summaries = new Map(missing.map((issue) => [issue.key, issue.summary]));
    const rows = loaded.map((s): Row => {
      const summary = summaries.get(s.key) ?? '';
      return s.status === 'suggested'
        ? { key: s.key, summary, kind: 'editable', date: s.date, source: s.source, inclusion: 'included' }
        : { key: s.key, summary, kind: 'unavailable', error: s.error };
    });
    setPhase((current) => (current.kind === 'loading' ? { kind: 'review', rows, error: null } : current));
  };

  const close = () => setPhase({ kind: 'closed' });

  const edit = (key: string, change: Partial<{ date: string; inclusion: Inclusion }>) =>
    setPhase((current) =>
      current.kind === 'review'
        ? {
            ...current,
            rows: current.rows.map((row) => (row.key === key && row.kind === 'editable' ? { ...row, ...change } : row)),
          }
        : current,
    );

  const write = async (rows: Row[]) => {
    const items = writable(rows);
    if (items.length === 0) return;
    setPhase({ kind: 'writing', rows });
    const settle = (next: Phase) => setPhase((current) => (current.kind === 'writing' ? next : current));
    const results: StartDateResult[] = [];
    let error: string | null = null;
    for (const batch of batches(items)) {
      const written = await writeBatch(batch);
      if (typeof written === 'string') {
        error = written;
        break;
      }
      results.push(...written);
    }
    if (results.length === 0) {
      settle({ kind: 'review', rows, error });
      return;
    }
    settle({ kind: 'written', rows, results: new Map(results.map((r) => [r.key, r])), error });
    if (results.some((r) => r.outcome === 'written')) onChanged();
  };

  const rows = phase.kind === 'review' || phase.kind === 'writing' || phase.kind === 'written' ? phase.rows : [];
  const locked = phase.kind !== 'review';
  const count = writable(rows).length;

  return (
    <div className="mb-3 flex justify-end">
      <Button variant="outline" size="sm" onClick={open} disabled={phase.kind === 'loading'}>
        {phase.kind === 'loading' ? 'Buscando datas…' : `Preencher início em todas (${missing.length})`}
      </Button>

      <Dialog open={phase.kind !== 'closed' && phase.kind !== 'loading'} onOpenChange={(o) => !o && close()}>
        <DialogContent showCloseButton className="motion-reduce:animate-none sm:max-w-2xl">
          <DialogHeader>
            <DialogTitle>Preencher data de início</DialogTitle>
            <DialogDescription className="text-ink-dim">
              Confira a data sugerida de cada história. Nada é gravado no Jira até você confirmar.
            </DialogDescription>
          </DialogHeader>

          {phase.kind === 'failed' && (
            <p role="alert" className="text-sm text-danger">
              Não foi possível sugerir as datas: {phase.error}
            </p>
          )}

          {rows.length > 0 && (
            <ul className="-mx-1 flex max-h-[60vh] flex-col gap-3 overflow-y-auto px-1">
              {rows.map((row) => {
                const result = phase.kind === 'written' ? phase.results.get(row.key) : undefined;
                return (
                  <li key={row.key} className="flex flex-col gap-1 text-sm">
                    <div className="flex items-center gap-3">
                      {row.kind === 'editable' && (
                        <input
                          type="checkbox"
                          aria-label={`Incluir ${row.key}`}
                          className={cn('size-3.5 accent-[var(--brand)]', focusRing)}
                          checked={row.inclusion === 'included'}
                          disabled={locked}
                          onChange={(e) => edit(row.key, { inclusion: e.target.checked ? 'included' : 'excluded' })}
                        />
                      )}
                      <span className="shrink-0 font-mono text-brand">{row.key}</span>
                      <span className="min-w-0 flex-1 truncate">{row.summary}</span>
                      {row.kind === 'editable' && (
                        <input
                          type="date"
                          aria-label={`Data de início de ${row.key}`}
                          className={cn('h-8 rounded-md border bg-glass px-2 text-sm', focusRing)}
                          value={row.date}
                          max={limit}
                          disabled={locked}
                          onChange={(e) => edit(row.key, { date: e.target.value })}
                        />
                      )}
                    </div>
                    {row.kind === 'editable' ? (
                      <span className="type-caption text-ink-dim">{SOURCE_HINT[row.source]}</span>
                    ) : (
                      <span className="type-caption text-danger">Sem sugestão: {row.error}</span>
                    )}
                    {result?.outcome === 'written' && <span className="type-caption text-success">gravada ✓</span>}
                    {result?.outcome === 'refused' && (
                      <span className="type-caption text-danger">Jira recusou: {result.error ?? 'sem detalhe'}</span>
                    )}
                  </li>
                );
              })}
            </ul>
          )}

          {(phase.kind === 'review' || phase.kind === 'written') && phase.error && (
            <p role="alert" className="text-sm text-danger">
              {phase.error}
            </p>
          )}

          <DialogFooter>
            {phase.kind === 'written' || phase.kind === 'failed' ? (
              <Button onClick={close}>Fechar</Button>
            ) : (
              <Button onClick={() => write(rows)} disabled={locked || count === 0}>
                {phase.kind === 'writing' ? 'Gravando…' : `Gravar ${count} ${count === 1 ? 'data' : 'datas'}`}
              </Button>
            )}
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
