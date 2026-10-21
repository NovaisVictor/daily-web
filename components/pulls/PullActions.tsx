'use client';

import { useId, useState, type ReactNode } from 'react';
import { Check, GitMerge, MessageSquare, MoreHorizontal, RotateCw, UserPlus, XCircle } from 'lucide-react';
import type { PullRequestItem } from '@/lib/types';
import { Button } from '@/components/ui/button';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from '@/components/ui/dropdown-menu';
import { Input } from '@/components/ui/input';
import { Textarea } from '@/components/ui/textarea';
import { sendJiraWrite } from '@/components/jira/actions/context';
import { cn } from '@/lib/utils';
import { focusRing } from '@/lib/theme';
import {
  isLogin,
  MERGE_METHODS,
  REVIEWERS_MAX,
  teamSlug,
  TEXT_MAX,
  type MergeMethod,
  type ReviewEvent,
} from '@/lib/integrations/github/actions';
import { usePullsActions } from './context';

/** Which dialog an item of the row menu opened. The dialog lives outside the
 *  menu because the menu unmounts as soon as an item is picked. */
type PullDialog = 'approve' | 'request-changes' | 'comment' | 'rerequest' | 'merge' | 'rerun';

type Sending = 'idle' | 'sending';

type Outcome = { kind: 'editing' } | { kind: 'done'; message: string };

const NO_ACTIONS_RUN = 'nenhum workflow do GitHub Actions falhou neste commit (o check pode ser de outro serviço)';

const METHOD_LABEL: Record<MergeMethod, string> = {
  merge: 'merge commit',
  squash: 'squash',
  rebase: 'rebase',
};

function refOf(item: PullRequestItem): string {
  return `${item.repo}#${item.number}`;
}

function actionUrl(item: PullRequestItem, action: string): string {
  const [owner = '', name = ''] = item.repo.split('/');
  return `/api/pulls/${encodeURIComponent(owner)}/${encodeURIComponent(name)}/${item.number}/${action}`;
}

/** Entries the server accepts: a re-request of anything else would be refused. */
function requestable(reviewer: string): boolean {
  return isLogin(reviewer) || teamSlug(reviewer) !== null;
}

function typedLogins(text: string): string[] {
  return text.split(/[\s,]+/).filter((part) => part !== '');
}

/** One POST with the panel's write contract: pending disables the buttons, a
 *  refusal is shown as the server said it, success refreshes the panel. */
function useWrite(item: PullRequestItem, action: string) {
  const { onChanged } = usePullsActions();
  const [sending, setSending] = useState<Sending>('idle');
  const [refusal, setRefusal] = useState<string | null>(null);

  const send = async (body: unknown): Promise<Record<string, unknown> | null> => {
    setSending('sending');
    setRefusal(null);
    const result = await sendJiraWrite(actionUrl(item, action), 'POST', body);
    setSending('idle');
    if (!result.ok) {
      setRefusal(result.error);
      return null;
    }
    onChanged();
    return result.data;
  };

  return { sending, refusal, setRefusal, send };
}

interface ShellProps {
  item: PullRequestItem;
  open: boolean;
  title: string;
  onClose: () => void;
  outcome: Outcome;
  children: ReactNode;
}

function DialogShell({ item, open, title, onClose, outcome, children }: ShellProps) {
  return (
    <Dialog open={open} onOpenChange={(next) => !next && onClose()}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{title}</DialogTitle>
          <DialogDescription className="[overflow-wrap:anywhere]">{item.title}</DialogDescription>
        </DialogHeader>
        {outcome.kind === 'editing' ? (
          children
        ) : (
          <>
            <p role="status" className="type-body text-ink">
              {outcome.message} ·{' '}
              <a href={item.url} target="_blank" rel="noreferrer" className="underline">
                abrir {refOf(item)} no GitHub
              </a>
            </p>
            <DialogFooter>
              <Button size="sm" onClick={onClose}>
                Fechar
              </Button>
            </DialogFooter>
          </>
        )}
      </DialogContent>
    </Dialog>
  );
}

function Problem({ id, text }: { id: string; text: string | null }) {
  if (!text) return null;
  return (
    <p id={id} role="alert" className="type-caption text-danger [overflow-wrap:anywhere]">
      {text}
    </p>
  );
}

interface Footer {
  sending: Sending;
  ready: boolean;
  label: string;
  pendingLabel: string;
  destructive?: 'destructive';
  onCancel: () => void;
}

function FormFooter({ sending, ready, label, pendingLabel, destructive, onCancel }: Footer) {
  return (
    <div className="flex justify-end gap-2">
      <Button type="button" size="sm" variant="ghost" disabled={sending === 'sending'} onClick={onCancel}>
        Cancelar
      </Button>
      <Button type="submit" size="sm" variant={destructive ?? 'default'} disabled={!ready || sending === 'sending'}>
        {sending === 'sending' ? pendingLabel : label}
      </Button>
    </div>
  );
}

interface DialogProps {
  item: PullRequestItem;
  open: PullDialog | null;
  onClose: () => void;
}

const TEXT_ACTIONS = {
  approve: {
    action: 'reviews',
    title: 'Aprovar',
    label: 'Aprovar',
    pending: 'Aprovando…',
    hint: 'comentário opcional, publicado junto com a aprovação',
    done: 'PR aprovado',
  },
  'request-changes': {
    action: 'reviews',
    title: 'Pedir mudanças em',
    label: 'Pedir mudanças',
    pending: 'Enviando…',
    hint: 'diga o que precisa mudar — o comentário é obrigatório',
    done: 'mudanças pedidas',
  },
  comment: {
    action: 'comments',
    title: 'Comentar em',
    label: 'Comentar',
    pending: 'Comentando…',
    hint: 'vai aparecer como seu comentário no GitHub',
    done: 'comentário publicado',
  },
} as const;

type TextAction = keyof typeof TEXT_ACTIONS;

const REVIEW_EVENT: Record<Exclude<TextAction, 'comment'>, ReviewEvent> = {
  approve: 'APPROVE',
  'request-changes': 'REQUEST_CHANGES',
};

function TextDialog({ item, open, onClose, kind }: DialogProps & { kind: TextAction }) {
  const spec = TEXT_ACTIONS[kind];
  const write = useWrite(item, spec.action);
  const [text, setText] = useState('');
  const [outcome, setOutcome] = useState<Outcome>({ kind: 'editing' });
  const hintId = useId();
  const errorId = useId();

  const trimmed = text.trim();
  const required = kind !== 'approve';
  const tooLong = trimmed.length > TEXT_MAX;
  const ready = !tooLong && (!required || trimmed.length > 0);
  const problem = write.refusal ?? (tooLong ? `passou de ${TEXT_MAX} caracteres (${trimmed.length})` : null);

  const close = () => {
    setText('');
    setOutcome({ kind: 'editing' });
    write.setRefusal(null);
    onClose();
  };

  const submit = async () => {
    if (!ready || write.sending === 'sending') return;
    const body =
      kind === 'comment'
        ? { body: trimmed }
        : { event: REVIEW_EVENT[kind], ...(trimmed ? { body: trimmed } : {}) };
    if (await write.send(body)) setOutcome({ kind: 'done', message: spec.done });
  };

  return (
    <DialogShell
      item={item}
      open={open === kind}
      title={`${spec.title} ${refOf(item)}`}
      onClose={close}
      outcome={outcome}
    >
      <form
        className="flex flex-col gap-2"
        onSubmit={(e) => {
          e.preventDefault();
          void submit();
        }}
      >
        <Textarea
          aria-label={`comentário em ${refOf(item)}`}
          aria-describedby={problem ? `${hintId} ${errorId}` : hintId}
          aria-invalid={problem ? true : undefined}
          value={text}
          onChange={(e) => setText(e.target.value)}
          disabled={write.sending === 'sending'}
          autoFocus
          rows={4}
        />
        <Problem id={errorId} text={problem} />
        <p id={hintId} className="type-caption text-ink-dim">
          {spec.hint}
        </p>
        <FormFooter
          sending={write.sending}
          ready={ready}
          label={spec.label}
          pendingLabel={spec.pending}
          onCancel={close}
        />
      </form>
    </DialogShell>
  );
}

function RerequestDialog({ item, open, onClose }: DialogProps) {
  const write = useWrite(item, 'reviewers');
  const listed = item.pendingReviewers.filter(requestable);
  const [chosen, setChosen] = useState<string[]>([]);
  const [typed, setTyped] = useState('');
  const [outcome, setOutcome] = useState<Outcome>({ kind: 'editing' });
  const errorId = useId();

  const extra = typedLogins(typed);
  const badLogin = extra.find((login) => !isLogin(login)) ?? null;
  const reviewers = [...new Set([...chosen, ...extra])];
  const tooMany = reviewers.length > REVIEWERS_MAX;
  const ready = reviewers.length > 0 && !badLogin && !tooMany;
  const problem =
    write.refusal ??
    (badLogin ? `"${badLogin}" não é um login do GitHub` : tooMany ? `no máximo ${REVIEWERS_MAX} revisores` : null);

  const close = () => {
    setChosen([]);
    setTyped('');
    setOutcome({ kind: 'editing' });
    write.setRefusal(null);
    onClose();
  };

  const toggle = (reviewer: string) =>
    setChosen((current) =>
      current.includes(reviewer) ? current.filter((r) => r !== reviewer) : [...current, reviewer],
    );

  const submit = async () => {
    if (!ready || write.sending === 'sending') return;
    if (await write.send({ reviewers })) {
      setOutcome({ kind: 'done', message: `revisão pedida de novo a ${reviewers.join(', ')}` });
    }
  };

  return (
    <DialogShell
      item={item}
      open={open === 'rerequest'}
      title={`Pedir revisão de novo em ${refOf(item)}`}
      onClose={close}
      outcome={outcome}
    >
      <form
        className="flex flex-col gap-3"
        onSubmit={(e) => {
          e.preventDefault();
          void submit();
        }}
      >
        {listed.length > 0 && (
          <fieldset className="flex flex-col gap-1" disabled={write.sending === 'sending'}>
            <legend className="type-caption text-ink-dim">revisores pendentes</legend>
            {listed.map((reviewer) => (
              <label key={reviewer} className="flex items-center gap-2 text-sm text-ink">
                <input type="checkbox" checked={chosen.includes(reviewer)} onChange={() => toggle(reviewer)} />
                {reviewer}
              </label>
            ))}
          </fieldset>
        )}
        <label className="flex flex-col gap-1 text-sm text-ink">
          outros logins (separados por vírgula)
          <Input
            value={typed}
            onChange={(e) => setTyped(e.target.value)}
            disabled={write.sending === 'sending'}
            aria-invalid={badLogin ? true : undefined}
            aria-describedby={problem ? errorId : undefined}
          />
        </label>
        <Problem id={errorId} text={problem} />
        <FormFooter
          sending={write.sending}
          ready={ready}
          label="Pedir revisão"
          pendingLabel="Pedindo…"
          onCancel={close}
        />
      </form>
    </DialogShell>
  );
}

function MergeDialog({ item, open, onClose }: DialogProps) {
  const write = useWrite(item, 'merge');
  const [method, setMethod] = useState<MergeMethod>('squash');
  const [outcome, setOutcome] = useState<Outcome>({ kind: 'editing' });
  const errorId = useId();

  const close = () => {
    setMethod('squash');
    setOutcome({ kind: 'editing' });
    write.setRefusal(null);
    onClose();
  };

  const submit = async () => {
    if (write.sending === 'sending') return;
    if (await write.send({ method, headSha: item.headSha })) {
      setOutcome({ kind: 'done', message: `merge feito em ${item.baseRef}` });
    }
  };

  return (
    <DialogShell
      item={item}
      open={open === 'merge'}
      title={`Fazer merge de ${refOf(item)}`}
      onClose={close}
      outcome={outcome}
    >
      <form
        className="flex flex-col gap-3"
        onSubmit={(e) => {
          e.preventDefault();
          void submit();
        }}
      >
        <p className="type-body text-ink [overflow-wrap:anywhere]">
          <span className="font-mono">{item.headRef}</span> → <span className="font-mono">{item.baseRef}</span>
        </p>
        <fieldset className="flex flex-col gap-1" disabled={write.sending === 'sending'}>
          <legend className="type-caption text-ink-dim">método</legend>
          {MERGE_METHODS.map((m) => (
            <label key={m} className="flex items-center gap-2 text-sm text-ink">
              <input
                type="radio"
                name={`merge-${item.id}`}
                value={m}
                checked={method === m}
                onChange={() => setMethod(m)}
              />
              {METHOD_LABEL[m]}
            </label>
          ))}
        </fieldset>
        <p className="type-caption text-ink-dim">
          só entra o commit {item.headSha?.slice(0, 7)} que você está vendo; se o PR mudou, o merge é recusado
        </p>
        <Problem id={errorId} text={write.refusal} />
        <FormFooter
          sending={write.sending}
          ready
          label="Fazer merge"
          pendingLabel="Fazendo merge…"
          destructive="destructive"
          onCancel={close}
        />
      </form>
    </DialogShell>
  );
}

function RerunDialog({ item, open, onClose }: DialogProps) {
  const write = useWrite(item, 'rerun');
  const [outcome, setOutcome] = useState<Outcome>({ kind: 'editing' });
  const errorId = useId();

  const close = () => {
    setOutcome({ kind: 'editing' });
    write.setRefusal(null);
    onClose();
  };

  const submit = async () => {
    if (write.sending === 'sending') return;
    const data = await write.send({ headSha: item.headSha });
    if (!data) return;
    if (typeof data.rerun !== 'number') {
      write.setRefusal('resposta inesperada do servidor');
      return;
    }
    setOutcome({
      kind: 'done',
      message: data.rerun === 0 ? NO_ACTIONS_RUN : `${data.rerun} workflow(s) rodando de novo`,
    });
  };

  return (
    <DialogShell
      item={item}
      open={open === 'rerun'}
      title={`Rodar CI de novo em ${refOf(item)}`}
      onClose={close}
      outcome={outcome}
    >
      <form
        className="flex flex-col gap-3"
        onSubmit={(e) => {
          e.preventDefault();
          void submit();
        }}
      >
        <p className="type-body text-ink">roda de novo só os jobs que falharam no GitHub Actions deste commit</p>
        {item.failedChecks.length > 0 && (
          <ul aria-label="checks com falha" className="list-disc pl-5 type-caption text-ink-dim">
            {item.failedChecks.map((check) => (
              <li key={check.name}>{check.name}</li>
            ))}
          </ul>
        )}
        <Problem id={errorId} text={write.refusal} />
        <FormFooter
          sending={write.sending}
          ready
          label="Rodar de novo"
          pendingLabel="Pedindo…"
          onCancel={close}
        />
      </form>
    </DialogShell>
  );
}

interface MenuEntry {
  dialog: PullDialog;
  label: string;
  icon: ReactNode;
}

function menuEntries(item: PullRequestItem): MenuEntry[] {
  const comment: MenuEntry = { dialog: 'comment', label: 'Comentar', icon: <MessageSquare /> };
  if (!item.isPullRequest) return [comment];
  const entries: MenuEntry[] = [];
  if (!item.mine) {
    entries.push({ dialog: 'approve', label: 'Aprovar', icon: <Check /> });
    entries.push({ dialog: 'request-changes', label: 'Pedir mudanças', icon: <XCircle /> });
  }
  entries.push(comment);
  if (item.mine && (item.review === 'changes-requested' || item.review === 'pending')) {
    entries.push({ dialog: 'rerequest', label: 'Pedir revisão de novo', icon: <UserPlus /> });
  }
  if (item.merge === 'clean' && !item.draft && item.headSha) {
    entries.push({ dialog: 'merge', label: 'Fazer merge', icon: <GitMerge /> });
  }
  if (item.ci === 'failing' && item.headSha) {
    entries.push({ dialog: 'rerun', label: 'Rodar CI de novo', icon: <RotateCw /> });
  }
  return entries;
}

/** The row's "⋯" menu: review, comment, re-request, merge and re-run CI. */
export function PullActions({ item }: { item: PullRequestItem }) {
  const [open, setOpen] = useState<PullDialog | null>(null);
  const onClose = () => setOpen(null);
  const entries = menuEntries(item);
  const dialogs = new Set(entries.map((entry) => entry.dialog));

  return (
    <>
      <DropdownMenu>
        <DropdownMenuTrigger asChild>
          <button
            type="button"
            className={cn(
              'inline-flex size-7 shrink-0 items-center justify-center rounded-md text-ink-dim hover:bg-muted hover:text-ink',
              focusRing,
            )}
            aria-label={`ações de ${refOf(item)}`}
          >
            <MoreHorizontal className="size-4" />
          </button>
        </DropdownMenuTrigger>
        <DropdownMenuContent align="end">
          {entries.map((entry) => (
            <DropdownMenuItem key={entry.dialog} onSelect={() => setOpen(entry.dialog)}>
              {entry.icon}
              {entry.label}
            </DropdownMenuItem>
          ))}
        </DropdownMenuContent>
      </DropdownMenu>
      {dialogs.has('approve') && <TextDialog item={item} open={open} onClose={onClose} kind="approve" />}
      {dialogs.has('request-changes') && (
        <TextDialog item={item} open={open} onClose={onClose} kind="request-changes" />
      )}
      <TextDialog item={item} open={open} onClose={onClose} kind="comment" />
      {dialogs.has('rerequest') && <RerequestDialog item={item} open={open} onClose={onClose} />}
      {dialogs.has('merge') && <MergeDialog item={item} open={open} onClose={onClose} />}
      {dialogs.has('rerun') && <RerunDialog item={item} open={open} onClose={onClose} />}
    </>
  );
}
