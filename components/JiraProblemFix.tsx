'use client';

import { useState } from 'react';
import type { JiraProblem, JiraProblemItem } from '@/lib/types';
import { Button } from './ui/button';
import { Input } from './ui/input';
import { selectClass } from '@/lib/theme';
import { cn } from '@/lib/utils';

const START_PROBLEMS: JiraProblem[] = ['story-in-progress-without-start', 'story-done-without-start'];

interface EpicOption {
  key: string;
  summary: string;
}

/** Cada correção passa pelos mesmos passos: buscar o que sugerir, mostrar
 *  para a pessoa conferir, gravar. Nada vai para o Jira sem o "Salvar". */
type Step<T> =
  | { kind: 'idle' }
  | { kind: 'loading' }
  | { kind: 'editing'; value: T }
  | { kind: 'saving'; value: T }
  | { kind: 'saved' };

async function readJson(response: Response): Promise<Record<string, unknown>> {
  const body = (await response.json().catch(() => ({}))) as Record<string, unknown>;
  if (!response.ok) throw new Error(typeof body.error === 'string' ? body.error : `erro ${response.status}`);
  return body;
}

export function JiraProblemFix({ issue, onFixed }: { issue: JiraProblemItem; onFixed: () => void }) {
  const precisaInicio = issue.problems.some((p) => START_PROBLEMS.includes(p));
  const precisaEpico = issue.problems.includes('story-without-epic');
  if (!precisaInicio && !precisaEpico) return null;

  return (
    <div className="flex flex-wrap items-center gap-2 pt-1">
      {precisaInicio && <StartDateFix issueKey={issue.key} onFixed={onFixed} />}
      {precisaEpico && <EpicFix issueKey={issue.key} project={issue.project} onFixed={onFixed} />}
    </div>
  );
}

function StartDateFix({ issueKey, onFixed }: { issueKey: string; onFixed: () => void }) {
  const [step, setStep] = useState<Step<string>>({ kind: 'idle' });
  const [nota, setNota] = useState<string | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const url = `/api/jira/issues/${encodeURIComponent(issueKey)}/start-date`;

  const sugerir = async () => {
    setErro(null);
    setStep({ kind: 'loading' });
    try {
      const body = await readJson(await fetch(url));
      const date = typeof body.date === 'string' ? body.date : '';
      setNota(date ? 'primeira passagem por andamento' : 'sem passagem por andamento no histórico');
      setStep({ kind: 'editing', value: date });
    } catch (err) {
      setErro(err instanceof Error ? err.message : String(err));
      setStep({ kind: 'idle' });
    }
  };

  const salvar = async (date: string) => {
    setErro(null);
    setStep({ kind: 'saving', value: date });
    try {
      await readJson(
        await fetch(url, {
          method: 'PUT',
          headers: { 'content-type': 'application/json' },
          body: JSON.stringify({ date }),
        }),
      );
      setStep({ kind: 'saved' });
      onFixed();
    } catch (err) {
      setErro(err instanceof Error ? err.message : String(err));
      setStep({ kind: 'editing', value: date });
    }
  };

  if (step.kind === 'saved') return <span className="type-caption text-success">início gravado no Jira</span>;

  if (step.kind === 'editing' || step.kind === 'saving') {
    return (
      <form
        className="flex flex-wrap items-center gap-2"
        onSubmit={(event) => {
          event.preventDefault();
          if (step.value) void salvar(step.value);
        }}
      >
        <Input
          type="date"
          aria-label={`data de início de ${issueKey}`}
          className="h-8 w-auto"
          value={step.value}
          disabled={step.kind === 'saving'}
          onChange={(event) => setStep({ kind: 'editing', value: event.target.value })}
        />
        <Button type="submit" size="sm" disabled={!step.value || step.kind === 'saving'}>
          {step.kind === 'saving' ? 'Salvando…' : 'Salvar'}
        </Button>
        <Button type="button" size="sm" variant="ghost" onClick={() => setStep({ kind: 'idle' })}>
          Cancelar
        </Button>
        {nota && <span className="type-caption text-ink-dim">{nota}</span>}
        {erro && <span className="type-caption text-danger">{erro}</span>}
      </form>
    );
  }

  return (
    <>
      <Button type="button" size="xs" variant="outline" disabled={step.kind === 'loading'} onClick={() => void sugerir()}>
        {step.kind === 'loading' ? 'Lendo o histórico…' : 'Preencher início'}
      </Button>
      {erro && <span className="type-caption text-danger">{erro}</span>}
    </>
  );
}

function EpicFix({ issueKey, project, onFixed }: { issueKey: string; project: string; onFixed: () => void }) {
  const [step, setStep] = useState<Step<string>>({ kind: 'idle' });
  const [epicos, setEpicos] = useState<EpicOption[]>([]);
  const [erro, setErro] = useState<string | null>(null);

  const carregar = async () => {
    setErro(null);
    setStep({ kind: 'loading' });
    try {
      const body = await readJson(await fetch(`/api/jira/epics?project=${encodeURIComponent(project)}`));
      const lista = Array.isArray(body.epics) ? (body.epics as EpicOption[]) : [];
      setEpicos(lista);
      if (lista.length === 0) {
        setErro(`nenhum épico aberto em ${project}`);
        setStep({ kind: 'idle' });
        return;
      }
      setStep({ kind: 'editing', value: '' });
    } catch (err) {
      setErro(err instanceof Error ? err.message : String(err));
      setStep({ kind: 'idle' });
    }
  };

  const salvar = async (epic: string) => {
    setErro(null);
    setStep({ kind: 'saving', value: epic });
    try {
      await readJson(
        await fetch(`/api/jira/issues/${encodeURIComponent(issueKey)}/parent`, {
          method: 'PUT',
          headers: { 'content-type': 'application/json' },
          body: JSON.stringify({ epic }),
        }),
      );
      setStep({ kind: 'saved' });
      onFixed();
    } catch (err) {
      setErro(err instanceof Error ? err.message : String(err));
      setStep({ kind: 'editing', value: epic });
    }
  };

  if (step.kind === 'saved') return <span className="type-caption text-success">épico gravado no Jira</span>;

  if (step.kind === 'editing' || step.kind === 'saving') {
    return (
      <form
        className="flex flex-wrap items-center gap-2"
        onSubmit={(event) => {
          event.preventDefault();
          if (step.value) void salvar(step.value);
        }}
      >
        <select
          aria-label={`épico de ${issueKey}`}
          className={cn(selectClass, 'max-w-72 border-line-strong')}
          value={step.value}
          disabled={step.kind === 'saving'}
          onChange={(event) => setStep({ kind: 'editing', value: event.target.value })}
        >
          <option value="">Escolha o épico</option>
          {epicos.map((epic) => (
            <option key={epic.key} value={epic.key}>
              {epic.key} — {epic.summary}
            </option>
          ))}
        </select>
        <Button type="submit" size="sm" disabled={!step.value || step.kind === 'saving'}>
          {step.kind === 'saving' ? 'Salvando…' : 'Salvar'}
        </Button>
        <Button type="button" size="sm" variant="ghost" onClick={() => setStep({ kind: 'idle' })}>
          Cancelar
        </Button>
        {erro && <span className="type-caption text-danger">{erro}</span>}
      </form>
    );
  }

  return (
    <>
      <Button type="button" size="xs" variant="outline" disabled={step.kind === 'loading'} onClick={() => void carregar()}>
        {step.kind === 'loading' ? 'Buscando épicos…' : 'Escolher épico'}
      </Button>
      {erro && <span className="type-caption text-danger">{erro}</span>}
    </>
  );
}
