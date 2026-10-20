'use client';

import { useId, useState } from 'react';
import { Flag } from 'lucide-react';
import type { JiraImpediment, JiraItem } from '@/lib/types';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { DropdownMenuItem } from '@/components/ui/dropdown-menu';
import { Button } from '@/components/ui/button';
import { Textarea } from '@/components/ui/textarea';
import { cn } from '@/lib/utils';
import { focusRing } from '@/lib/theme';
import { FLAG_REASON_MAX } from '@/lib/jiraLimits';
import type { DialogProps, MenuItemProps } from '../IssueActions';
import { sendJiraWrite, useJiraActions } from './context';

type Phase = 'idle' | 'sending';

/** The flag shown on a row that is marked as impeded; clicking it offers to
 *  remove the impediment. */
export function FlagIndicator({ issue }: { issue: JiraItem }) {
  const [open, setOpen] = useState(false);
  // Kept mounted while open: after a write that left a warning, the refreshed
  // row is no longer flagged, and the warning must stay on screen.
  if (issue.impediment !== 'flagged' && !open) return null;

  return (
    <>
      {issue.impediment === 'flagged' && (
        <button
          type="button"
          className={cn(
            'inline-flex size-5 shrink-0 items-center justify-center rounded text-danger hover:brightness-110',
            focusRing,
          )}
          aria-label="impedida"
          title="impedida — clique para remover o impedimento"
          onClick={() => setOpen(true)}
        >
          <Flag className="size-3.5" aria-hidden="true" />
        </button>
      )}
      <Dialog open={open} onOpenChange={setOpen}>
        {open && <FlagDialogBody issue={issue} current="flagged" onDone={() => setOpen(false)} />}
      </Dialog>
    </>
  );
}

export function FlagMenuItem({ issue, onOpen }: MenuItemProps) {
  return (
    <DropdownMenuItem onSelect={() => onOpen('flag')}>
      <Flag aria-hidden="true" />
      {issue.impediment === 'flagged' ? 'Remover impedimento' : 'Marcar impedimento'}
    </DropdownMenuItem>
  );
}

export function FlagDialog({ issue, open, onClose }: DialogProps) {
  const isOpen = open === 'flag';
  return (
    <Dialog open={isOpen} onOpenChange={(next) => !next && onClose()}>
      {isOpen && <FlagDialogBody issue={issue} current={issue.impediment} onDone={onClose} />}
    </Dialog>
  );
}

function FlagDialogBody({
  issue,
  current,
  onDone,
}: {
  issue: JiraItem;
  current: JiraImpediment;
  onDone: () => void;
}) {
  const { onChanged } = useJiraActions();
  const [text, setText] = useState('');
  const [phase, setPhase] = useState<Phase>('idle');
  const [error, setError] = useState<string | null>(null);
  const [warning, setWarning] = useState<string | null>(null);
  const [flagging] = useState(current === 'none');
  const fieldId = useId();
  const hintId = useId();

  const trimmed = text.trim();
  const valid = flagging ? trimmed.length > 0 && trimmed.length <= FLAG_REASON_MAX : trimmed.length <= FLAG_REASON_MAX;

  const submit = async () => {
    setPhase('sending');
    setError(null);
    const body = flagging
      ? { action: 'flag', reason: trimmed }
      : { action: 'unflag', ...(trimmed ? { note: trimmed } : {}) };
    const result = await sendJiraWrite(`/api/jira/issues/${encodeURIComponent(issue.key)}/flag`, 'POST', body);
    setPhase('idle');
    if (!result.ok) {
      setError(result.error);
      return;
    }
    onChanged();
    if (typeof result.data.warning === 'string') {
      setWarning(result.data.warning);
      return;
    }
    onDone();
  };

  if (warning) {
    return (
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>{flagging ? 'Impedimento marcado' : 'Impedimento removido'}</DialogTitle>
          <DialogDescription>
            <span className="font-mono">{issue.key}</span> — {issue.summary}
          </DialogDescription>
        </DialogHeader>
        <p role="alert" className="text-sm text-warning">
          {warning}
        </p>
        <DialogFooter>
          <Button type="button" onClick={onDone}>
            Fechar
          </Button>
        </DialogFooter>
      </DialogContent>
    );
  }

  return (
    <DialogContent className="sm:max-w-md">
      <DialogHeader>
        <DialogTitle>
          {flagging ? `Marcar ${issue.key} como impedida?` : `Remover o impedimento de ${issue.key}?`}
        </DialogTitle>
        <DialogDescription>
          <span className="font-mono">{issue.key}</span> — {issue.summary}
        </DialogDescription>
      </DialogHeader>

      <div className="flex flex-col gap-1.5">
        <label htmlFor={fieldId} className="text-sm font-medium text-ink">
          {flagging ? 'Motivo' : 'Observação (opcional)'}
        </label>
        <Textarea
          id={fieldId}
          aria-describedby={hintId}
          value={text}
          maxLength={FLAG_REASON_MAX}
          disabled={phase === 'sending'}
          onChange={(event) => setText(event.target.value)}
        />
        <p id={hintId} className="text-xs text-ink-dim">
          {flagging ? 'o motivo vira um comentário na issue' : 'se preenchida, a observação vira um comentário na issue'}
        </p>
      </div>

      {error && (
        <p role="alert" className="text-sm text-danger">
          {error}
        </p>
      )}

      <DialogFooter>
        <Button type="button" variant="outline" disabled={phase === 'sending'} onClick={onDone}>
          Cancelar
        </Button>
        <Button
          type="button"
          variant={flagging ? 'destructive' : 'default'}
          disabled={phase === 'sending' || !valid}
          onClick={() => void submit()}
        >
          {phase === 'sending' ? 'enviando…' : flagging ? 'Marcar impedimento' : 'Remover impedimento'}
        </Button>
      </DialogFooter>
    </DialogContent>
  );
}
