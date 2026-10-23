import { ProviderRefusal } from '@/lib/integrations/refusal';
import { computeAgendaWindow } from '@/lib/agendaWindow';
import { accessToken, googleClient } from './oauth';
import type { Connection } from '@/lib/vault/connections';
import type { AgendaItem } from '@/lib/types';

const API = 'https://www.googleapis.com/calendar/v3';
const TIMEOUT_MS = 20_000;

export interface CalendarRef {
  id: string;
  label: string;
  primary: boolean;
}

export interface FocusBlockInput {
  title: string;
  description: string;
  start: Date;
  end: Date;
}

async function api(token: string, path: string): Promise<unknown> {
  const response = await fetch(`${API}${path}`, {
    headers: { authorization: `Bearer ${token}` },
    signal: AbortSignal.timeout(TIMEOUT_MS),
  });
  if (response.status === 401) throw new Error('o Google recusou o acesso — conecte de novo');
  if (response.status === 403) {
    const body = await response.text().catch(() => '');
    if (body.includes('accessNotConfigured')) {
      throw new Error(
        'a Google Calendar API não está ativada no projeto do Google Cloud deste servidor',
      );
    }
    throw new Error('o Google negou a permissão para ler a agenda');
  }
  if (!response.ok) throw new Error(`o Google respondeu ${response.status}`);
  return response.json();
}

interface RawCalendarList {
  items?: { id?: string; summary?: string; summaryOverride?: string; primary?: boolean; selected?: boolean }[];
}

export async function listCalendars(conn: Connection): Promise<CalendarRef[]> {
  const token = await accessToken(googleClient(), refreshToken(conn));
  const data = (await api(token, '/users/me/calendarList?minAccessRole=reader&maxResults=250')) as RawCalendarList;
  return (data.items ?? [])
    .filter((item): item is { id: string } & typeof item => Boolean(item.id))
    .map((item) => ({
      id: item.id,
      label: item.summaryOverride ?? item.summary ?? item.id,
      primary: item.primary === true,
    }));
}

interface RawEvent {
  summary?: string;
  status?: string;
  start?: { dateTime?: string; date?: string };
}

function pad(value: number): string {
  return String(value).padStart(2, '0');
}

function localDate(date: Date): string {
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
}

function localTime(date: Date): string {
  return `${pad(date.getHours())}:${pad(date.getMinutes())}`;
}

/** Converte um evento da API para a linha da agenda. Separada do fetch para
 *  poder ser testada sem rede. */
export function toAgendaItem(
  raw: RawEvent,
  account: string,
  accountLabel: string,
): AgendaItem | null {
  if (raw.status === 'cancelled') return null;

  // `date` é evento de dia inteiro e não tem hora; `dateTime` tem.
  if (raw.start?.date) {
    return {
      account,
      accountLabel,
      date: raw.start.date,
      time: '',
      title: (raw.summary ?? '').trim() || '(sem título)',
    };
  }
  if (!raw.start?.dateTime) return null;

  const start = new Date(raw.start.dateTime);
  if (Number.isNaN(start.getTime())) return null;
  return {
    account,
    accountLabel,
    date: localDate(start),
    time: localTime(start),
    title: (raw.summary ?? '').trim() || '(sem título)',
  };
}

export function refreshToken(conn: Connection): string {
  const token = conn.values.refreshToken ?? '';
  if (!token) throw new ProviderRefusal(`${conn.label}: conexão com o Google incompleta — conecte de novo`);
  return token;
}

export async function createFocusBlock(
  conn: Connection,
  input: FocusBlockInput,
): Promise<AgendaItem> {
  const token = await accessToken(googleClient(), refreshToken(conn));
  const response = await fetch(`${API}/calendars/primary/events`, {
    method: 'POST',
    headers: {
      authorization: `Bearer ${token}`,
      'content-type': 'application/json',
    },
    body: JSON.stringify({
      summary: input.title,
      description: input.description,
      start: { dateTime: input.start.toISOString() },
      end: { dateTime: input.end.toISOString() },
      transparency: 'opaque',
      extendedProperties: { private: { dailyWebFocus: '1' } },
    }),
    signal: AbortSignal.timeout(TIMEOUT_MS),
  });

  if (response.status === 401) throw new Error('o Google recusou o acesso — conecte de novo');
  if (response.status === 403) {
    throw new Error('o Google negou a permissão para criar eventos — reconecte a agenda');
  }
  if (!response.ok) {
    const body = (await response.text().catch(() => '')).slice(0, 200);
    throw new Error(`Google Agenda respondeu ${response.status}${body ? `: ${body}` : ''}`);
  }

  const item = toAgendaItem((await response.json()) as RawEvent, conn.id, conn.label);
  if (!item) throw new Error('Google Agenda respondeu com um evento inválido');
  return item;
}

export function selectedCalendars(conn: Connection): string[] {
  return (conn.values.calendarIds ?? '')
    .split(',')
    .map((id) => id.trim())
    .filter((id) => id.length > 0);
}

interface RawEventList {
  items?: RawEvent[];
}

export async function fetchAgenda(
  conn: Connection,
  now: Date = new Date(),
  days?: number,
): Promise<AgendaItem[]> {
  const token = await accessToken(googleClient(), refreshToken(conn));
  const window = computeAgendaWindow(now, days);
  const timeMin = new Date(`${window.start}T00:00:00`).toISOString();
  const timeMax = new Date(`${window.end}T23:59:59`).toISOString();

  // Sem calendário escolhido, vale o principal — é o que a pessoa espera ver
  // logo depois de conectar, sem passar por mais uma tela.
  const chosen = selectedCalendars(conn);
  const calendars = chosen.length > 0 ? chosen : ['primary'];

  const settled = await Promise.allSettled(
    calendars.map(async (calendarId) => {
      const query = new URLSearchParams({
        timeMin,
        timeMax,
        // `singleEvents` faz o Google expandir as repetições; sem isso viria a
        // regra e teríamos de reimplementar RRULE aqui.
        singleEvents: 'true',
        orderBy: 'startTime',
        maxResults: '250',
      });
      const data = (await api(
        token,
        `/calendars/${encodeURIComponent(calendarId)}/events?${query.toString()}`,
      )) as RawEventList;
      return (data.items ?? [])
        .map((item) => toAgendaItem(item, conn.id, conn.label))
        .filter((item): item is AgendaItem => item !== null);
    }),
  );

  const items = settled.flatMap((r) => (r.status === 'fulfilled' ? r.value : []));
  const errors = settled
    .filter((r): r is PromiseRejectedResult => r.status === 'rejected')
    .map((r) => (r.reason instanceof Error ? r.reason.message : String(r.reason)));

  // Um calendário compartilhado que perdeu acesso não pode zerar os outros.
  if (items.length === 0 && errors.length > 0) throw new Error(errors.join('; '));

  return items.sort((a, b) => a.date.localeCompare(b.date) || a.time.localeCompare(b.time));
}

export async function testConnection(conn: Connection): Promise<void> {
  await listCalendars(conn);
}
