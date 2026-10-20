'use client';

import { useEffect, useState, type ReactNode } from 'react';
import { ExternalLink } from 'lucide-react';
import type { JiraItem } from '@/lib/types';
import type { JiraPriority } from '@/lib/integrations/jira/edits';
import { isEpic } from '@/lib/parsers/jiraProblems';
import { DropdownMenuItem, DropdownMenuSeparator } from '@/components/ui/dropdown-menu';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Textarea } from '@/components/ui/textarea';
import { Label } from '@/components/ui/label';
import { cn } from '@/lib/utils';
import { focusRing } from '@/lib/theme';
import type { DialogProps, MenuItemProps } from '../IssueActions';
import { sendJiraWrite, useJiraActions } from './context';

type Sending = 'idle' | 'sending';

const SUMMARY_MAX = 255;

function fieldsUrl(key: string): string {
  return `/api/jira/issues/${encodeURIComponent(key)}/fields`;
}

function storiesUrl(key: string): string {
  return `/api/jira/issues/${encodeURIComponent(key)}/stories`;
}

function formatDate(iso: string): string {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(iso);
  return match ? `${match[3]}/${match[2]}/${match[1]}` : 'sem prazo';
}

function isMine(issue: JiraItem, viewer: ReturnType<typeof useJiraActions>['viewer']): boolean {
  return viewer.kind === 'self' && (issue.role === 'assignee' || issue.role === 'both');
}

export function EditMenuItems({ issue, onOpen }: MenuItemProps) {
  const { viewer } = useJiraActions();
  return (
    <>
      <DropdownMenuSeparator />
      <DropdownMenuItem onSelect={() => onOpen('due')}>Alterar prazo</DropdownMenuItem>
      <DropdownMenuItem onSelect={() => onOpen('priority')}>Alterar prioridade</DropdownMenuItem>
      {!isMine(issue, viewer) && (
        <DropdownMenuItem onSelect={() => onOpen('assign')}>Atribuir a mim</DropdownMenuItem>
      )}
      {isEpic(issue) && (
        <DropdownMenuItem onSelect={() => onOpen('create-story')}>Criar história neste épico</DropdownMenuItem>
      )}
    </>
  );
}

export function EditDialogs(props: DialogProps) {
  return (
    <>
      <DueDialog {...props} />
      <PriorityDialog {...props} />
      <AssignDialog {...props} />
      <CreateStoryDialog {...props} />
    </>
  );
}

/** One write in flight at a time; a refusal stays next to the buttons. */
function useWrite(onDone: (data: Record<string, unknown>) => void) {
  const [sending, setSending] = useState<Sending>('idle');
  const [refusal, setRefusal] = useState<string | null>(null);
  const send = async (url: string, method: 'POST' | 'PUT', body: unknown) => {
    if (sending === 'sending') return;
    setSending('sending');
    setRefusal(null);
    const result = await sendJiraWrite(url, method, body);
    setSending('idle');
    if (!result.ok) {
      setRefusal(result.error);
      return;
    }
    onDone(result.data);
  };
  return { sending, refusal, send };
}

function Refusal({ issue, message }: { issue: JiraItem; message: string | null }) {
  if (!message) return null;
  return (
    <p role="alert" className="type-caption text-danger">
      {message} · <OpenInJira url={issue.url}>abrir no Jira</OpenInJira>
    </p>
  );
}

function OpenInJira({ url, children }: { url: string; children: ReactNode }) {
  return (
    <a
      href={url}
      target="_blank"
      rel="noreferrer"
      className={cn('inline-flex items-center gap-1 text-brand hover:underline', focusRing)}
    >
      {children}
      <ExternalLink aria-hidden className="size-3" />
    </a>
  );
}

function EditDialog({
  title,
  description,
  onClose,
  children,
  footer,
}: {
  title: string;
  description: ReactNode;
  onClose: () => void;
  children?: ReactNode;
  footer: ReactNode;
}) {
  return (
    <Dialog open onOpenChange={(next) => !next && onClose()}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{title}</DialogTitle>
          <DialogDescription>{description}</DialogDescription>
        </DialogHeader>
        {children}
        <DialogFooter>{footer}</DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function Actions({
  sending,
  disabled,
  onClose,
  onConfirm,
  idle,
  busy,
}: {
  sending: Sending;
  disabled?: boolean;
  onClose: () => void;
  onConfirm: () => void;
  idle: string;
  busy: string;
}) {
  return (
    <>
      <Button variant="ghost" disabled={sending === 'sending'} onClick={onClose}>
        Cancelar
      </Button>
      <Button disabled={disabled || sending === 'sending'} onClick={onConfirm}>
        {sending === 'sending' ? busy : idle}
      </Button>
    </>
  );
}

function DueDialog({ issue, open, onClose }: DialogProps) {
  if (open !== 'due') return null;
  return <DueForm issue={issue} onClose={onClose} />;
}

function DueForm({ issue, onClose }: { issue: JiraItem; onClose: () => void }) {
  const { onChanged } = useJiraActions();
  const [value, setValue] = useState(issue.dueDate);
  const { sending, refusal, send } = useWrite(() => {
    onClose();
    onChanged();
  });
  const changed = value !== issue.dueDate;

  return (
    <EditDialog
      title={`Prazo de ${issue.key}`}
      description={issue.summary}
      onClose={onClose}
      footer={
        <Actions
          sending={sending}
          disabled={!changed}
          onClose={onClose}
          onConfirm={() => void send(fieldsUrl(issue.key), 'PUT', { change: 'due', dueDate: value || null })}
          idle="Salvar"
          busy="Salvando…"
        />
      }
    >
      <div className="flex flex-col gap-2">
        <Label htmlFor={`due-${issue.key}`}>Novo prazo</Label>
        <div className="flex items-center gap-2">
          <Input
            id={`due-${issue.key}`}
            type="date"
            value={value}
            disabled={sending === 'sending'}
            onChange={(event) => setValue(event.target.value)}
          />
          <Button
            variant="outline"
            disabled={value === '' || sending === 'sending'}
            onClick={() => setValue('')}
          >
            Remover prazo
          </Button>
        </div>
        {changed && (
          <p className="type-caption text-ink">
            de {formatDate(issue.dueDate)} para {formatDate(value)}
          </p>
        )}
        <Refusal issue={issue} message={refusal} />
      </div>
    </EditDialog>
  );
}

type PriorityView =
  | { kind: 'loading' }
  | { kind: 'failed'; error: string }
  | { kind: 'ready'; priorities: JiraPriority[]; current: JiraPriority | null };

async function loadPriorities(key: string): Promise<PriorityView> {
  const res = await fetch(`${fieldsUrl(key)}?options=priority`).catch(() => null);
  if (!res) return { kind: 'failed', error: 'sem resposta do servidor' };
  const data = (await res.json().catch(() => ({}))) as {
    priorities?: JiraPriority[];
    current?: JiraPriority | null;
    error?: unknown;
  };
  if (!res.ok || !Array.isArray(data.priorities)) {
    return { kind: 'failed', error: typeof data.error === 'string' ? data.error : `falha (${res.status})` };
  }
  return { kind: 'ready', priorities: data.priorities, current: data.current ?? null };
}

function PriorityDialog({ issue, open, onClose }: DialogProps) {
  if (open !== 'priority') return null;
  return <PriorityForm issue={issue} onClose={onClose} />;
}

function PriorityForm({ issue, onClose }: { issue: JiraItem; onClose: () => void }) {
  const { onChanged } = useJiraActions();
  const [view, setView] = useState<PriorityView>({ kind: 'loading' });
  const [chosen, setChosen] = useState<string | null>(null);
  const { sending, refusal, send } = useWrite(() => {
    onClose();
    onChanged();
  });

  const [attempt, setAttempt] = useState(0);

  useEffect(() => {
    let live = true;
    void loadPriorities(issue.key).then((next) => live && setView(next));
    return () => {
      live = false;
    };
  }, [issue.key, attempt]);

  const retry = () => {
    setView({ kind: 'loading' });
    setAttempt((n) => n + 1);
  };

  const current = view.kind === 'ready' ? view.current : null;
  const target = view.kind === 'ready' ? view.priorities.find((p) => p.id === chosen) ?? null : null;
  const changed = target !== null && target.id !== current?.id;

  return (
    <EditDialog
      title={`Prioridade de ${issue.key}`}
      description={issue.summary}
      onClose={onClose}
      footer={
        <Actions
          sending={sending}
          disabled={!changed}
          onClose={onClose}
          onConfirm={() =>
            target && void send(fieldsUrl(issue.key), 'PUT', { change: 'priority', priorityId: target.id })
          }
          idle="Salvar"
          busy="Salvando…"
        />
      }
    >
      {view.kind === 'loading' && (
        <p role="status" className="type-caption text-ink-dim">
          carregando prioridades…
        </p>
      )}
      {view.kind === 'failed' && (
        <div role="alert" className="flex flex-col items-start gap-2 type-caption">
          <p className="text-danger">{view.error}</p>
          <Button size="sm" variant="outline" onClick={retry}>
            Tentar de novo
          </Button>
        </div>
      )}
      {view.kind === 'ready' && (
        <div className="flex flex-col gap-2">
          <fieldset className="flex flex-col gap-1" disabled={sending === 'sending'}>
            <legend className="sr-only">Prioridade</legend>
            {view.priorities.map((p) => (
              <label key={p.id} className="flex items-center gap-2 text-sm text-ink">
                <input
                  type="radio"
                  name={`priority-${issue.key}`}
                  value={p.id}
                  checked={(chosen ?? current?.id) === p.id}
                  onChange={() => setChosen(p.id)}
                />
                {p.name}
              </label>
            ))}
          </fieldset>
          {changed && (
            <p className="type-caption text-ink">
              de {current?.name ?? 'sem prioridade'} para {target.name}
            </p>
          )}
          <Refusal issue={issue} message={refusal} />
        </div>
      )}
    </EditDialog>
  );
}

function AssignDialog({ issue, open, onClose }: DialogProps) {
  if (open !== 'assign') return null;
  return <AssignForm issue={issue} onClose={onClose} />;
}

function AssignForm({ issue, onClose }: { issue: JiraItem; onClose: () => void }) {
  const { onChanged } = useJiraActions();
  const { sending, refusal, send } = useWrite(() => {
    onClose();
    onChanged();
  });

  return (
    <EditDialog
      title="Atribuir a mim"
      description={`${issue.key} passa a ter você como responsável`}
      onClose={onClose}
      footer={
        <Actions
          sending={sending}
          onClose={onClose}
          onConfirm={() => void send(fieldsUrl(issue.key), 'PUT', { change: 'assign-self' })}
          idle="Atribuir"
          busy="Atribuindo…"
        />
      }
    >
      <Refusal issue={issue} message={refusal} />
    </EditDialog>
  );
}

function CreateStoryDialog({ issue, open, onClose }: DialogProps) {
  if (open !== 'create-story') return null;
  return <CreateStoryForm issue={issue} onClose={onClose} />;
}

type Created = { key: string; url: string };

function CreateStoryForm({ issue, onClose }: { issue: JiraItem; onClose: () => void }) {
  const { onChanged } = useJiraActions();
  const [summary, setSummary] = useState('');
  const [description, setDescription] = useState('');
  const [created, setCreated] = useState<Created | null>(null);
  const { sending, refusal, send } = useWrite((data) => {
    if (typeof data.key === 'string' && typeof data.url === 'string') setCreated({ key: data.key, url: data.url });
    onChanged();
  });
  const trimmed = summary.trim();
  const valid = trimmed.length > 0 && trimmed.length <= SUMMARY_MAX;

  if (created) {
    return (
      <EditDialog
        title="História criada"
        description={`dentro de ${issue.key}`}
        onClose={onClose}
        footer={<Button onClick={onClose}>Fechar</Button>}
      >
        <p role="status" className="text-sm text-ink">
          <OpenInJira url={created.url}>{created.key}</OpenInJira> criada
        </p>
      </EditDialog>
    );
  }

  return (
    <EditDialog
      title="Criar história"
      description={`nova história em ${issue.project} dentro de ${issue.key}`}
      onClose={onClose}
      footer={
        <Actions
          sending={sending}
          disabled={!valid}
          onClose={onClose}
          onConfirm={() =>
            void send(storiesUrl(issue.key), 'POST', {
              summary: trimmed,
              ...(description.trim() ? { description } : {}),
            })
          }
          idle="Criar"
          busy="Criando…"
        />
      }
    >
      <div className="flex flex-col gap-2">
        <Label htmlFor={`story-summary-${issue.key}`}>Resumo</Label>
        <Input
          id={`story-summary-${issue.key}`}
          value={summary}
          maxLength={SUMMARY_MAX}
          disabled={sending === 'sending'}
          onChange={(event) => setSummary(event.target.value)}
        />
        <Label htmlFor={`story-description-${issue.key}`}>Descrição (opcional)</Label>
        <Textarea
          id={`story-description-${issue.key}`}
          value={description}
          disabled={sending === 'sending'}
          onChange={(event) => setDescription(event.target.value)}
        />
        <Refusal issue={issue} message={refusal} />
      </div>
    </EditDialog>
  );
}
