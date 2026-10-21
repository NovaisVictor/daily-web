import { getDb } from './db';
import { fetchMentions } from './integrations/jiraApi';
import type { Connection } from './vault/connections';
import type {
  EmailEnvelope,
  NotificationItem,
  NotificationSource,
  PanelResult,
  PullRequestItem,
  PullsDigest,
  ReviewRequestsDigest,
  SlackDigest,
} from '@/lib/types';
import { elapsedMs, formatDays, STALE_REVIEW_MS } from './pullAge';

/** Um sino com tudo é um sino que ninguém lê. Cada fonte entra com os mais
 *  recentes até este teto; o painel continua mostrando a lista inteira. */
const PER_SOURCE_LIMIT = 20;

const SOURCES: NotificationSource[] = ['jira_mention', 'pull_request', 'email', 'slack'];

export function isRead(userId: string, source: string, externalId: string): boolean {
  const row = getDb()
    .prepare('SELECT 1 FROM notifications_read WHERE user_id = ? AND source = ? AND external_id = ?')
    .get(userId, source, externalId);
  return row !== undefined;
}

const INSERT_READ =
  'INSERT INTO notifications_read (user_id, source, external_id, read_at) VALUES (?, ?, ?, ?) ' +
  'ON CONFLICT (user_id, source, external_id) DO NOTHING';

export function markRead(userId: string, source: string, externalId: string): void {
  getDb().prepare(INSERT_READ).run(userId, source, externalId, new Date().toISOString());
}

/** Vários de uma vez, numa transação: dispensar o sino inteiro é uma decisão
 *  só, e meia gravação deixaria parte dos avisos voltando no ciclo seguinte.
 *  Devolve quantos foram gravados. */
export function markManyRead(
  userId: string,
  avisos: { source: string; externalId: string }[],
): number {
  if (avisos.length === 0) return 0;
  const db = getDb();
  const insert = db.prepare(INSERT_READ);
  const agora = new Date().toISOString();
  db.transaction(() => {
    for (const aviso of avisos) insert.run(userId, aviso.source, aviso.externalId, agora);
  })();
  return avisos.length;
}

export async function getNotifications(
  userId: string,
  connection: Connection,
): Promise<NotificationItem[]> {
  const mentions = await fetchMentions(connection);
  return mentions.map((issue) => ({
    id: notificationId('jira_mention', issue.key),
    source: 'jira_mention' as const,
    title: `${issue.key} — ${issue.summary}`,
    url: issue.url,
    read: isRead(userId, 'jira_mention', issue.key),
    date: issue.updatedAt,
  }));
}


/** O id que a tela usa e a rota de "lida" recebe de volta. A fonte vai no
 *  começo porque duas fontes podem ter o mesmo id externo, e é a fonte que
 *  diz em qual chave o "lida" precisa ser gravado. */
export function notificationId(source: NotificationSource, externalId: string): string {
  return `${source}:${externalId}`;
}

/** A volta de `notificationId`. O corte é no primeiro `:` apenas: o id
 *  externo de um e-mail carrega `:` dentro, e cortar em todos truncaria a
 *  chave usada para gravar o "lida". */
export function parseNotificationId(
  id: string,
): { source: NotificationSource; externalId: string } | null {
  const corte = id.indexOf(':');
  if (corte <= 0) return null;
  const source = id.slice(0, corte);
  const externalId = id.slice(corte + 1);
  if (!SOURCES.includes(source as NotificationSource) || externalId === '') return null;
  return { source: source as NotificationSource, externalId };
}

/** Um aviso por pull request aberto. Issue fica de fora: o painel traz as
 *  duas coisas na mesma lista, mas quem pediu aviso pediu de PR. */
export function pullNotifications(userId: string, items: PullRequestItem[]): NotificationItem[] {
  return items
    .filter((item) => item.isPullRequest)
    .sort((a, b) => b.updatedAt.localeCompare(a.updatedAt))
    .slice(0, PER_SOURCE_LIMIT)
    .map((item) => {
      const externalId = `${item.repo}#${item.number}`;
      return {
        id: notificationId('pull_request', externalId),
        source: 'pull_request' as const,
        title: `${externalId} — ${item.title}`,
        url: item.url,
        read: isRead(userId, 'pull_request', externalId),
        date: item.updatedAt,
      };
    });
}

/** Review requests waiting longer than a day. The search does not say when the
 *  review was requested, so the clock starts at the PR's creation. */
export function staleReviewNotifications(
  userId: string,
  items: PullRequestItem[],
  now: Date = new Date(),
): NotificationItem[] {
  return items
    .filter((item) => item.isPullRequest && item.awaitingYou)
    .flatMap((item) => {
      const waiting = elapsedMs(item.createdAt, now);
      return waiting !== null && waiting > STALE_REVIEW_MS ? [{ item, waiting }] : [];
    })
    .sort((a, b) => b.waiting - a.waiting)
    .slice(0, PER_SOURCE_LIMIT)
    .map(({ item, waiting }) => {
      const externalId = `${item.repo}#${item.number}`;
      return {
        id: notificationId('pull_request', externalId),
        source: 'pull_request' as const,
        title: `revisão parada há ${formatDays(waiting)} — ${externalId} ${item.title}`,
        url: item.url,
        read: isRead(userId, 'pull_request', externalId),
        date: item.updatedAt,
      };
    });
}

/** The stale review says more than the plain "PR open" entry for the same PR. */
function pullAndStaleReviews(
  userId: string,
  pulls: PullRequestItem[],
  reviewRequests: PullRequestItem[],
): NotificationItem[] {
  const stale = staleReviewNotifications(userId, reviewRequests);
  const staleIds = new Set(stale.map((item) => item.id));
  return [...stale, ...pullNotifications(userId, pulls).filter((item) => !staleIds.has(item.id))];
}

/** Um aviso por e-mail que chegou e ainda não foi lido. Marcar o aviso como
 *  lido não mexe na caixa: dispensar o aviso e ler o e-mail são coisas
 *  diferentes, e o sino não escreve no servidor de e-mail. */
export function emailNotifications(userId: string, envelopes: EmailEnvelope[]): NotificationItem[] {
  return envelopes
    .filter((envelope) => envelope.mailbox === 'inbox' && envelope.unread)
    .sort((a, b) => b.date.localeCompare(a.date))
    .slice(0, PER_SOURCE_LIMIT)
    .map((envelope) => {
      // O Message-Id acompanha a mensagem; o uid é por caixa e só serve
      // quando o servidor não mandou o header.
      const externalId = envelope.messageId || `${envelope.account}:${envelope.id}`;
      return {
        id: notificationId('email', externalId),
        source: 'email' as const,
        title: `${envelope.from} — ${envelope.subject || '(sem assunto)'}`,
        url: '',
        read: isRead(userId, 'email', externalId),
        date: envelope.date,
      };
    });
}

export function slackNotifications(userId: string, digest: SlackDigest): NotificationItem[] {
  return [...digest.mentions, ...digest.directs]
    .sort((a, b) => b.date.localeCompare(a.date))
    .slice(0, PER_SOURCE_LIMIT)
    .map((message) => ({
      id: notificationId('slack', message.id),
      source: 'slack' as const,
      title: `${message.author} — ${message.text}`,
      url: message.url,
      read: isRead(userId, 'slack', message.id),
      date: message.date,
    }));
}


/**
 * As três fontes do sino numa lista só. Cada painel já foi buscado para a
 * tela, então o aviso sai do que está em mãos — nenhuma ida a mais ao Jira,
 * ao GitHub ou ao IMAP.
 *
 * O sino fica ausente só quando nenhuma fonte está ligada; basta uma para a
 * lista existir. Erro de uma fonte não apaga o aviso das outras.
 */
export function combineNotifications(
  userId: string,
  mentions: PanelResult<NotificationItem[]>,
  pulls: PanelResult<PullsDigest>,
  email: PanelResult<EmailEnvelope[]>,
  slack: PanelResult<SlackDigest> = { data: null, error: null },
  reviewRequests: PanelResult<ReviewRequestsDigest> = { data: null, error: null },
): PanelResult<NotificationItem[]> {
  const desligado =
    mentions.data === null &&
    mentions.error === null &&
    pulls.data === null &&
    pulls.error === null &&
    email.data === null &&
    email.error === null &&
    slack.data === null &&
    slack.error === null &&
    reviewRequests.data === null &&
    reviewRequests.error === null;
  if (desligado) return { data: null, error: null };

  const items = [
    ...(mentions.data ?? []),
    ...pullAndStaleReviews(userId, pulls.data?.items ?? [], reviewRequests.data?.items ?? []),
    ...emailNotifications(userId, email.data ?? []),
    ...slackNotifications(userId, slack.data ?? { mentions: [], directs: [], team: '' }),
  ].sort((a, b) => b.date.localeCompare(a.date));
  return { data: items, error: [mentions.error, slack.error].filter(Boolean).join('; ') || null };
}
