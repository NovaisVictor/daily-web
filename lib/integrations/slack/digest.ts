import type { SlackDigest, SlackMessage } from '@/lib/types';
import type { Connection } from '@/lib/vault/connections';
import { slackCall } from './api';

interface SlackUser {
  id?: string;
  name?: string;
  real_name?: string;
  profile?: { display_name?: string; real_name?: string };
}

interface SearchMatch {
  channel?: {
    id?: string;
    name?: string;
    is_im?: boolean;
    is_mpim?: boolean;
    is_private?: boolean;
  };
  user?: string;
  username?: string;
  text?: string;
  ts?: string;
  permalink?: string;
}

interface ImChannel {
  id?: string;
  user?: string;
  unread_count_display?: number;
}

interface HistoryMessage {
  user?: string;
  text?: string;
  ts?: string;
}

interface OkResponse {
  ok?: boolean;
  error?: string;
}

type SearchResponse = OkResponse & { messages?: { matches?: SearchMatch[] } };
type InfoResponse = OkResponse & { channel?: ImChannel };
type HistoryResponse = OkResponse & { messages?: HistoryMessage[] };
type UserResponse = OkResponse & { user?: SlackUser };

export class SlackDigestError extends Error {
  constructor(
    message: string,
    readonly digest: SlackDigest,
  ) {
    super(message);
    this.name = 'SlackDigestError';
  }
}

function isoFromTs(ts: string): string {
  const seconds = Number(ts);
  return Number.isFinite(seconds) ? new Date(seconds * 1000).toISOString() : '';
}

function safePermalink(value: string | undefined): string {
  if (!value) return '';
  try {
    const url = new URL(value);
    return url.protocol === 'https:' && url.hostname.endsWith('slack.com') ? value : '';
  } catch {
    return '';
  }
}

function channelLabel(channel: SearchMatch['channel']): string {
  if (channel?.is_im) return 'mensagem direta';
  if (channel?.is_mpim || channel?.is_private) return 'grupo privado';
  return channel?.name ? `#${channel.name}` : 'grupo privado';
}

function userName(user: SlackUser | undefined): string {
  return (
    user?.profile?.display_name ||
    user?.profile?.real_name ||
    user?.real_name ||
    user?.name ||
    'alguém'
  );
}

function decodeEntities(text: string): string {
  return text.replaceAll('&lt;', '<').replaceAll('&gt;', '>').replaceAll('&amp;', '&');
}

function truncate(text: string): string {
  return text.length <= 280 ? text : `${text.slice(0, 279)}…`;
}

function createNameResolver(token: string) {
  const cache = new Map<string, Promise<string>>();
  return (id: string): Promise<string> => {
    const known = cache.get(id);
    if (known) return known;
    if (cache.size >= 30) return Promise.resolve('alguém');
    const pending = slackCall<UserResponse>(token, 'users.info', { user: id })
      .then((response) => userName(response.user))
      .catch(() => 'alguém');
    cache.set(id, pending);
    return pending;
  };
}

async function formatText(text: string, resolveName: (id: string) => Promise<string>) {
  const ids = [...text.matchAll(/<@(U[A-Z0-9]+)>/g)].map((match) => match[1]);
  const names = new Map<string, string>();
  await Promise.all([...new Set(ids)].map(async (id) => names.set(id, await resolveName(id))));

  const formatted = text
    .replace(/<@(U[A-Z0-9]+)>/g, (_, id: string) => `@${names.get(id) ?? 'alguém'}`)
    .replace(/<#(?:[A-Z0-9]+)\|([^>]+)>/g, '#$1')
    .replace(/<(https?:\/\/[^|>]+)\|([^>]+)>/g, '$2')
    .replace(/<(https?:\/\/[^>]+)>/g, '$1');
  return truncate(decodeEntities(formatted).replace(/\s+/g, ' ').trim());
}

async function fetchMentions(
  token: string,
  ownUserId: string,
  resolveName: (id: string) => Promise<string>,
): Promise<SlackMessage[]> {
  const response = await slackCall<SearchResponse>(token, 'search.messages', {
    query: `<@${ownUserId}>`,
    count: '30',
    sort: 'timestamp',
    sort_dir: 'desc',
  });
  const cutoff = Date.now() - 7 * 24 * 60 * 60 * 1000;
  const matches = (response.messages?.matches ?? [])
    .filter((match) => match.user !== ownUserId && Number(match.ts ?? 0) * 1000 >= cutoff)
    .slice(0, 20);
  return Promise.all(
    matches.map(async (match) => {
      const author = match.user
        ? await resolveName(match.user)
        : match.username?.trim() || 'alguém';
      const channelId = match.channel?.id ?? '';
      const ts = match.ts ?? '';
      return {
        id: `${channelId}:${ts}`,
        channel: channelLabel(match.channel),
        author,
        text: await formatText(match.text ?? '', resolveName),
        date: isoFromTs(ts),
        url: safePermalink(match.permalink),
      };
    }),
  );
}

async function fetchDirects(
  token: string,
  resolveName: (id: string) => Promise<string>,
): Promise<SlackMessage[]> {
  // conversations.list leaves the unread counts out; only conversations.info
  // carries them, one call per conversation. The latest DMs in search tell
  // which conversations are worth asking about.
  const response = await slackCall<SearchResponse>(token, 'search.messages', {
    query: 'is:dm',
    count: '100',
    sort: 'timestamp',
    sort_dir: 'desc',
  });
  const recent = [
    ...new Set(
      (response.messages?.matches ?? [])
        .filter((match) => match.channel?.is_im && match.channel.id)
        .map((match) => match.channel?.id ?? ''),
    ),
  ].slice(0, 15);
  const channels = (
    await Promise.all(
      recent.map((channel) => slackCall<InfoResponse>(token, 'conversations.info', { channel })),
    )
  ).flatMap((info) => (info.channel ? [info.channel] : []));
  if (
    channels.length > 0 &&
    !channels.some((channel) => channel.unread_count_display !== undefined)
  ) {
    throw new Error('o Slack não informou as mensagens não lidas');
  }
  const unread = channels.filter(
    (channel) => (channel.unread_count_display ?? 0) > 0 && channel.id,
  );
  const messages = await Promise.all(
    unread.map(async (channel): Promise<SlackMessage | null> => {
      const history = await slackCall<HistoryResponse>(token, 'conversations.history', {
        channel: channel.id ?? '',
        limit: '1',
      });
      const latest = history.messages?.[0];
      if (!latest) return null;
      const ts = latest.ts ?? '';
      return {
        id: `${channel.id}:${ts}`,
        channel: 'mensagem direta',
        author: channel.user ? await resolveName(channel.user) : 'alguém',
        text: await formatText(latest.text ?? '', resolveName),
        date: isoFromTs(ts),
        url: '',
      };
    }),
  );
  return messages.filter((message): message is SlackMessage => message !== null);
}

export async function fetchSlack(connection: Connection): Promise<SlackDigest> {
  const token = connection.values.token ?? '';
  const userId = connection.values.userId ?? '';
  const resolveName = createNameResolver(token);
  const [mentions, directs] = await Promise.allSettled([
    fetchMentions(token, userId, resolveName),
    fetchDirects(token, resolveName),
  ]);
  const digest: SlackDigest = {
    mentions: mentions.status === 'fulfilled' ? mentions.value : [],
    directs: directs.status === 'fulfilled' ? directs.value : [],
    team: connection.values.teamName ?? '',
  };
  const errors = [mentions, directs]
    .filter((result): result is PromiseRejectedResult => result.status === 'rejected')
    .map((result) =>
      result.reason instanceof Error ? result.reason.message : String(result.reason),
    );
  if (errors.length > 0) throw new SlackDigestError(errors.join('; '), digest);
  return digest;
}

export async function testConnection(connection: Connection): Promise<void> {
  await slackCall<OkResponse>(connection.values.token ?? '', 'auth.test', {});
}
