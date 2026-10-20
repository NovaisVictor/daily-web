'use client';

import { useRef, useState } from 'react';
import type { JiraItem } from '@/lib/types';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { cn } from '@/lib/utils';
import { focusRing } from '@/lib/theme';
import { sendJiraWrite, useJiraActions } from './context';

type Decision = 'approve' | 'decline';

interface PendingApproval {
  id: string;
  name: string;
}

type Load =
  | { kind: 'loading' }
  | { kind: 'failed'; error: string }
  | { kind: 'ready'; approvals: PendingApproval[] };

type Step = { kind: 'choose' } | { kind: 'confirm'; approval: PendingApproval; decision: Decision };

type Phase = 'idle' | 'sending';

function parseApprovals(data: unknown): PendingApproval[] | null {
  if (typeof data !== 'object' || data === null) return null;
  const list = (data as { approvals?: unknown }).approvals;
  if (!Array.isArray(list)) return null;
  const valid = list.every(
    (a) => typeof a === 'object' && a !== null && typeof a.id === 'string' && typeof a.name === 'string',
  );
  return valid ? (list as PendingApproval[]) : null;
}

async function loadApprovals(key: string): Promise<Load> {
  const res = await fetch(`/api/jira/issues/${encodeURIComponent(key)}/approvals`).catch(() => null);
  if (!res) return { kind: 'failed', error: 'sem resposta do servidor' };
  const data: unknown = await res.json().catch(() => null);
  if (!res.ok) {
    const error = (data as { error?: unknown } | null)?.error;
    return { kind: 'failed', error: typeof error === 'string' ? error : `falha (${res.status})` };
  }
  const approvals = parseApprovals(data);
  if (!approvals) return { kind: 'failed', error: 'resposta inesperada do servidor' };
  return { kind: 'ready', approvals };
}

/** The APROV badge. Looking at someone else's queue it stays a mark: only the
 *  logged-in user can answer their own approvals. */
export function ApprovalBadge({ issue, className, title }: { issue: JiraItem; className: string; title: string }) {
  const { viewer } = useJiraActions();
  const [open, setOpen] = useState(false);
  const [load, setLoad] = useState<Load>({ kind: 'loading' });
  const request = useRef(0);

  if (viewer.kind === 'person') {
    return (
      <span className={className} title={title}>
        APROV
      </span>
    );
  }

  const openDialog = () => {
    const id = ++request.current;
    setLoad({ kind: 'loading' });
    setOpen(true);
    void loadApprovals(issue.key).then((next) => {
      if (request.current === id) setLoad(next);
    });
  };

  return (
    <>
      <button
        type="button"
        className={cn(className, 'cursor-pointer hover:brightness-110', focusRing)}
        title={title}
        aria-label={`aprovar ou recusar ${issue.key}`}
        onClick={openDialog}
      >
        APROV
      </button>
      <Dialog open={open} onOpenChange={setOpen}>
        {open && <ApprovalDialogBody issue={issue} load={load} onDone={() => setOpen(false)} />}
      </Dialog>
    </>
  );
}

function ApprovalDialogBody({ issue, load, onDone }: { issue: JiraItem; load: Load; onDone: () => void }) {
  const { onChanged } = useJiraActions();
  const [step, setStep] = useState<Step>({ kind: 'choose' });
  const [phase, setPhase] = useState<Phase>('idle');
  const [error, setError] = useState<string | null>(null);

  const submit = async (approval: PendingApproval, decision: Decision) => {
    setPhase('sending');
    setError(null);
    const result = await sendJiraWrite(`/api/jira/issues/${encodeURIComponent(issue.key)}/approvals`, 'POST', {
      approvalId: approval.id,
      decision,
    });
    setPhase('idle');
    if (!result.ok) {
      setError(result.error);
      return;
    }
    onChanged();
    onDone();
  };

  return (
    <DialogContent className="sm:max-w-md">
      <DialogHeader>
        <DialogTitle>
          {step.kind === 'confirm'
            ? `Confirmar ${step.decision === 'approve' ? 'aprovação' : 'recusa'} de ${issue.key}?`
            : `Aprovação de ${issue.key}`}
        </DialogTitle>
        <DialogDescription>
          <span className="font-mono">{issue.key}</span> — {issue.summary}
        </DialogDescription>
      </DialogHeader>

      {load.kind === 'loading' && <p className="text-sm text-ink-dim">carregando aprovações…</p>}

      {load.kind === 'failed' && (
        <p role="alert" className="text-sm text-danger">
          {load.error}
        </p>
      )}

      {load.kind === 'ready' && load.approvals.length === 0 && (
        <p className="text-sm text-ink-dim">
          nenhuma aprovação sua pendente nesta issue —{' '}
          <a href={issue.url} target="_blank" rel="noreferrer" className={cn('text-brand hover:underline', focusRing)}>
            abrir no Jira
          </a>
        </p>
      )}

      {load.kind === 'ready' && step.kind === 'choose' && load.approvals.length > 0 && (
        <ul className="flex flex-col gap-3">
          {load.approvals.map((approval) => (
            <li key={approval.id} className="flex flex-wrap items-center justify-between gap-2">
              <span className="text-sm text-ink">{approval.name}</span>
              <span className="flex gap-2">
                <Button
                  type="button"
                  size="sm"
                  variant="outline"
                  onClick={() => setStep({ kind: 'confirm', approval, decision: 'decline' })}
                >
                  Recusar
                </Button>
                <Button
                  type="button"
                  size="sm"
                  onClick={() => setStep({ kind: 'confirm', approval, decision: 'approve' })}
                >
                  Aprovar
                </Button>
              </span>
            </li>
          ))}
        </ul>
      )}

      {step.kind === 'confirm' && (
        <>
          <p className="text-sm text-ink">{step.approval.name}</p>
          {error && (
            <p role="alert" className="text-sm text-danger">
              {error}
            </p>
          )}
          <DialogFooter>
            <Button
              type="button"
              variant="outline"
              disabled={phase === 'sending'}
              onClick={() => {
                setError(null);
                setStep({ kind: 'choose' });
              }}
            >
              Voltar
            </Button>
            <Button
              type="button"
              variant={step.decision === 'decline' ? 'destructive' : 'default'}
              disabled={phase === 'sending'}
              onClick={() => void submit(step.approval, step.decision)}
            >
              {phase === 'sending' ? 'enviando…' : step.decision === 'approve' ? 'Confirmar aprovação' : 'Confirmar recusa'}
            </Button>
          </DialogFooter>
        </>
      )}
    </DialogContent>
  );
}
