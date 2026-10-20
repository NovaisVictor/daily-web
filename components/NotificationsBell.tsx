'use client';

import { useEffect, useState, useLayoutEffect, useRef } from 'react';
import { Check, CheckCheck } from 'lucide-react';
import { createPortal } from 'react-dom';
import type { NotificationItem, NotificationSource, PanelResult } from '@/lib/types';
import { Bell } from 'lucide-react';
import { Badge } from '@/components/ui/badge';
import { IconAction } from '@/components/data/IconAction';
import { Button } from '@/components/ui/button';
import { tabular } from '@/lib/theme';
import { cn } from '@/lib/utils';
import { Chip } from '@/components/ui/Chip';
import { NARROW_BREAKPOINT } from '@/lib/dashboardLayout';
import { isJiraKey } from '@/lib/jiraKey';
import { CommentForm } from '@/components/jira/actions/CommentAction';

/** De onde o aviso veio, em uma palavra. O rótulo era fixo em "JIRA", que
 *  passou a mentir quando o sino ganhou pull request e e-mail. */
const SOURCE_LABEL: Record<NotificationSource, string> = {
  jira_mention: 'JIRA',
  pull_request: 'PR',
  email: 'E-MAIL',
  slack: 'SLACK',
};

const MENTION_PREFIX = 'jira_mention:';

function mentionKey(item: NotificationItem): string | null {
  if (item.source !== 'jira_mention' || !item.id.startsWith(MENTION_PREFIX)) return null;
  const key = item.id.slice(MENTION_PREFIX.length);
  return isJiraKey(key) ? key : null;
}

type Reply = { id: string; stage: 'writing' | 'published' } | null;

interface Props {
  notifications: PanelResult<NotificationItem[]>;
  onChanged: () => void;
  /** Marca como lida na tela antes de o servidor responder. */
  onMarkedRead: (id: string) => void;
  /** O mesmo, para o lote inteiro. */
  onMarkedAllRead: (ids: string[]) => void;
  desktop?: {
    supported: boolean;
    enabled: boolean;
    permission: string;
    onEnable: () => void;
    onDisable: () => void;
  };
}

export function NotificationsBell({
  notifications,
  onChanged,
  onMarkedRead,
  onMarkedAllRead,
  desktop,
}: Props) {
  const [open, setOpen] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [marcandoTodas, setMarcandoTodas] = useState(false);
  const [reply, setReply] = useState<Reply>(null);
  const items = notifications.data ?? [];
  const naoLidas = items.filter((n) => !n.read);
  const unreadCount = naoLidas.length;

  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') setOpen(false);
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [open]);

  const markRead = async (item: NotificationItem) => {
    // O badge cai agora, não quando o servidor responder: a ação é local e
    // não há motivo para a tela esperar uma ida ao banco.
    onMarkedRead(item.id);
    setError(null);

    const res = await fetch('/api/notifications/read', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ id: item.id }),
    });
    if (!res.ok) {
      const data = await res.json().catch(() => ({}));
      setError(data.error ?? 'Falha ao marcar como lida');
      // Desfaz recarregando do servidor, que é a fonte da verdade.
      onChanged();
      return;
    }
  };

  const markAllRead = async () => {
    if (marcandoTodas || unreadCount === 0) return;
    // Os ids são fixados antes da ida ao servidor: um ciclo do refresher no
    // meio dela mudaria a lista, e o pedido tem de valer para o que estava
    // na tela quando você clicou.
    const ids = naoLidas.map((n) => n.id);

    setMarcandoTodas(true);
    onMarkedAllRead(ids);
    setError(null);

    const res = await fetch('/api/notifications/read', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ ids }),
    });
    setMarcandoTodas(false);
    if (!res.ok) {
      const data = await res.json().catch(() => ({}));
      setError(data.error ?? 'Falha ao marcar todas como lidas');
      onChanged();
    }
  };

  // O painel é levado para o body por portal. Sem isso ele fica preso ao
  // contexto de empilhamento do <main>, que tem overflow-y-auto e vizinhos com
  // backdrop-filter: o menu era recortado e pintado por baixo do conteúdo,
  // e nenhum z-index resolve isso de dentro.
  const anchorRef = useRef<HTMLDivElement>(null);
  const [pos, setPos] = useState<
    | { top: number; right: number; left?: undefined; narrow: false }
    | { top: number; right: number; left: number; narrow: true }
    | null
  >(null);

  useLayoutEffect(() => {
    if (!open) return;
    const medir = () => {
      const r = anchorRef.current?.getBoundingClientRect();
      if (!r) return;
      const top = r.bottom + 8;
      if (window.innerWidth <= NARROW_BREAKPOINT) {
        setPos({ top, left: 12, right: 12, narrow: true });
        return;
      }
      const width = Math.min(460, window.innerWidth - 32);
      const anchoredRight = window.innerWidth - r.right;
      const right = Math.min(anchoredRight, window.innerWidth - width - 12);
      setPos({ top, right, narrow: false });
    };
    medir();
    window.addEventListener('resize', medir);
    // O <main> é quem rola nesta moldura; sem ouvi-lo o painel fica para trás.
    const scroller = anchorRef.current?.closest('main');
    scroller?.addEventListener('scroll', medir, { passive: true });
    return () => {
      window.removeEventListener('resize', medir);
      scroller?.removeEventListener('scroll', medir);
    };
  }, [open]);

  return (
    <div className="relative" ref={anchorRef}>
      <IconAction
        variant="outline"
        label={`notificações (${unreadCount} não lidas)`}
        aria-expanded={open}
        onClick={() => setOpen((o) => !o)}
        icon={<Bell className="size-4" />}
        // O número é informação, não enfeite: fica dentro do botão, como texto,
        // num disco redondo — nunca só a cor do sino dizendo que há algo.
        badge={
          unreadCount > 0 ? (
            <Badge
              className={cn(
                'min-w-5 justify-center rounded-full px-1 type-caption leading-none',
                tabular,
              )}
            >
              {unreadCount}
            </Badge>
          ) : undefined
        }
      />

      {open &&
        createPortal(
          <>
            <div className="fixed inset-0 z-40" onClick={() => setOpen(false)} />
            <div
              style={
                pos
                  ? {
                      top: pos.top,
                      right: pos.right,
                      left: pos.left,
                      maxHeight: pos.narrow
                        ? `calc(100dvh - ${pos.top}px - 5.5rem - env(safe-area-inset-bottom))`
                        : undefined,
                    }
                  : undefined
              }
              className={cn(
                'fixed z-50 overflow-y-auto rounded-lg border border-line-strong bg-glass-strong p-4 shadow-e4 backdrop-blur-xl backdrop-saturate-150',
                pos?.narrow ? 'w-auto' : 'max-h-[70vh] w-[min(460px,calc(100vw-2rem))]',
              )}
              role="dialog"
              aria-label="central de notificações"
            >
              {desktop?.supported && (
                <div className="mb-2 flex items-center justify-between gap-3 border-b border-line pb-3">
                  {desktop.permission === 'denied' ? (
                    <p className="type-caption text-ink-dim">
                      Avisos bloqueados no navegador — libere nas permissões do site.
                    </p>
                  ) : (
                    <Chip
                      active={desktop.enabled}
                      onClick={desktop.enabled ? desktop.onDisable : desktop.onEnable}
                    >
                      Avisar no computador
                    </Chip>
                  )}
                </div>
              )}
              {/* Dispensar um a um custa um clique por aviso, e o sino chega a
                60. O botão só existe quando há o que dispensar. */}
              {unreadCount > 0 && (
                <div className="mb-2 flex items-center justify-between gap-3 border-b border-line pb-3">
                  <span className="type-caption text-ink-dim">
                    {unreadCount === 1 ? '1 não lida' : `${unreadCount} não lidas`}
                  </span>
                  <IconAction
                    size="icon-xs"
                    className="min-h-10 min-w-10"
                    label={marcandoTodas ? 'Marcando…' : 'Marcar todas como lidas'}
                    disabled={marcandoTodas}
                    onClick={() => void markAllRead()}
                    icon={<CheckCheck className={cn('size-4', marcandoTodas && 'animate-pulse')} />}
                  />
                </div>
              )}

              {notifications.error && (
                <p
                  role="alert"
                  className="type-caption my-2 rounded-r-md border-l-2 border-warning/40 bg-warning-tint p-3 text-ink-mid [overflow-wrap:anywhere]"
                >
                  {notifications.error}
                </p>
              )}
              {error && (
                <p
                  role="alert"
                  className="type-caption my-2 rounded-r-md border-l-2 border-warning/40 bg-warning-tint p-3 text-ink-mid [overflow-wrap:anywhere]"
                >
                  {error}
                </p>
              )}

              {items.length === 0 && (
                <p className="type-caption py-8 text-ink-dim">Nada por aqui.</p>
              )}

              <ul>
                {items.map((item) => {
                  const mention = mentionKey(item);
                  return (
                    <li
                      key={item.id}
                      className={cn(
                        'flex flex-col gap-2 border-b border-line py-3 last:border-b-0',
                        item.read && 'text-ink-dim',
                      )}
                    >
                      {/* O aviso de e-mail não tem página para abrir: vira texto,
                        porque um href vazio recarregaria o dashboard. */}
                      {item.url ? (
                        <a
                          href={item.url}
                          target="_blank"
                          rel="noreferrer"
                          className={cn(
                            'type-body block leading-snug hover:underline [overflow-wrap:anywhere]',
                            item.read ? 'text-ink-dim' : 'text-ink',
                          )}
                        >
                          {item.title}
                        </a>
                      ) : (
                        <span className="type-body [overflow-wrap:anywhere]">{item.title}</span>
                      )}
                      <div className="flex items-center justify-between gap-2">
                        <span className="type-caption tracking-wider text-ink-dim">
                          {SOURCE_LABEL[item.source]}
                        </span>
                        <span className="flex-1" />
                        {mention && (
                          <Button
                            size="xs"
                            variant="ghost"
                            className="min-h-10"
                            aria-label={`responder ${item.title}`}
                            aria-expanded={reply?.id === item.id && reply.stage === 'writing'}
                            onClick={() =>
                              setReply((r) =>
                                r?.id === item.id && r.stage === 'writing' ? null : { id: item.id, stage: 'writing' },
                              )
                            }
                          >
                            Responder
                          </Button>
                        )}
                        {!item.read && (
                          <IconAction
                            size="icon-xs"
                            className="min-h-10 min-w-10"
                            label={`marcar ${item.title} como lida`}
                            onClick={() => void markRead(item)}
                            icon={<Check className="size-4" />}
                          />
                        )}
                      </div>
                      {mention && reply?.id === item.id && reply.stage === 'writing' && (
                        <CommentForm
                          issueKey={mention}
                          onCancel={() => setReply(null)}
                          onPublished={() => {
                            setReply({ id: item.id, stage: 'published' });
                            if (!item.read) void markRead(item);
                          }}
                        />
                      )}
                      {reply?.id === item.id && reply.stage === 'published' && (
                        <p role="status" className="type-caption text-ink-mid">
                          resposta publicada
                        </p>
                      )}
                    </li>
                  );
                })}
              </ul>
            </div>
          </>,
          document.body,
        )}
    </div>
  );
}
