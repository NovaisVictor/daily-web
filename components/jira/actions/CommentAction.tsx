'use client';

import { useId, useState, type KeyboardEvent } from 'react';
import { MessageSquare } from 'lucide-react';
import { Button } from '@/components/ui/button';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { DropdownMenuItem } from '@/components/ui/dropdown-menu';
import { Textarea } from '@/components/ui/textarea';
import type { DialogProps, MenuItemProps } from '../IssueActions';
import { COMMENT_MAX } from '@/lib/jiraLimits';
import { sendJiraWrite, useJiraActions } from './context';

type Sending = 'idle' | 'sending';
type Stage = 'writing' | 'published';

function commentsUrl(key: string): string {
  return `/api/jira/issues/${encodeURIComponent(key)}/comments`;
}

function publishedId(data: Record<string, unknown>): string | null {
  const comment = data.comment;
  if (typeof comment !== 'object' || comment === null) return null;
  const id = (comment as Record<string, unknown>).id;
  return typeof id === 'string' && id !== '' ? id : null;
}

interface CommentFormProps {
  issueKey: string;
  onPublished: () => void;
  onCancel: () => void;
}

/** A plain-text comment on one issue, written with the logged-in user's token. */
export function CommentForm({ issueKey, onPublished, onCancel }: CommentFormProps) {
  const [text, setText] = useState('');
  const [sending, setSending] = useState<Sending>('idle');
  const [refusal, setRefusal] = useState<string | null>(null);
  const hintId = useId();
  const errorId = useId();

  const trimmed = text.trim();
  const tooLong = trimmed.length > COMMENT_MAX;
  const ready = trimmed.length > 0 && !tooLong && sending === 'idle';

  const submit = async () => {
    if (!ready) return;
    setSending('sending');
    setRefusal(null);
    const result = await sendJiraWrite(commentsUrl(issueKey), 'POST', { body: trimmed });
    setSending('idle');
    if (!result.ok) {
      setRefusal(result.error);
      return;
    }
    if (!publishedId(result.data)) {
      setRefusal('resposta inesperada do servidor');
      return;
    }
    onPublished();
  };

  const onKeyDown = (e: KeyboardEvent<HTMLTextAreaElement>) => {
    if (e.key === 'Enter' && (e.ctrlKey || e.metaKey)) {
      e.preventDefault();
      void submit();
    }
  };

  const problem = refusal ?? (tooLong ? `passou de ${COMMENT_MAX} caracteres (${trimmed.length})` : null);

  return (
    <form
      className="flex flex-col gap-2"
      onSubmit={(e) => {
        e.preventDefault();
        void submit();
      }}
    >
      <Textarea
        aria-label={`comentário em ${issueKey}`}
        aria-describedby={problem ? `${hintId} ${errorId}` : hintId}
        aria-invalid={problem ? true : undefined}
        value={text}
        onChange={(e) => setText(e.target.value)}
        onKeyDown={onKeyDown}
        disabled={sending === 'sending'}
        autoFocus
        rows={4}
      />
      {problem && (
        <p id={errorId} role="alert" className="type-caption text-danger [overflow-wrap:anywhere]">
          {problem}
        </p>
      )}
      <p id={hintId} className="type-caption text-ink-dim">
        vai aparecer como seu comentário em {issueKey}
      </p>
      <div className="flex justify-end gap-2">
        <Button type="button" size="sm" variant="ghost" disabled={sending === 'sending'} onClick={onCancel}>
          Cancelar
        </Button>
        <Button type="submit" size="sm" disabled={!ready}>
          {sending === 'sending' ? 'Comentando…' : 'Comentar'}
        </Button>
      </div>
    </form>
  );
}

export function CommentMenuItem({ onOpen }: MenuItemProps) {
  return (
    <DropdownMenuItem onSelect={() => onOpen('comment')}>
      <MessageSquare />
      Comentar
    </DropdownMenuItem>
  );
}

export function CommentDialog({ issue, open, onClose }: DialogProps) {
  const { onChanged } = useJiraActions();
  const [stage, setStage] = useState<Stage>('writing');

  const close = () => {
    setStage('writing');
    onClose();
  };

  return (
    <Dialog open={open === 'comment'} onOpenChange={(next) => !next && close()}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Comentar em {issue.key}</DialogTitle>
          <DialogDescription className="[overflow-wrap:anywhere]">{issue.summary}</DialogDescription>
        </DialogHeader>
        {stage === 'writing' ? (
          <CommentForm
            issueKey={issue.key}
            onCancel={close}
            onPublished={() => {
              setStage('published');
              onChanged();
            }}
          />
        ) : (
          <>
            <p role="status" className="type-body text-ink">
              comentário publicado ·{' '}
              <a href={issue.url} target="_blank" rel="noreferrer" className="underline">
                abrir {issue.key} no Jira
              </a>
            </p>
            <DialogFooter>
              <Button size="sm" onClick={close}>
                Fechar
              </Button>
            </DialogFooter>
          </>
        )}
      </DialogContent>
    </Dialog>
  );
}
