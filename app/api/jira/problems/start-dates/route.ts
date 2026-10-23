import { jiraActions } from '@/lib/operations/jira';
import { NextRequest, NextResponse } from 'next/server';
import { upstreamError } from '@/lib/api/context';
import { issueKeyParam, requireJira, writeDone } from '@/lib/api/jira';
import { isCalendarDate } from '@/lib/integrations/jira/parse';
import { START_DATE_BATCH } from '@/lib/jiraLimits';

function badRequest(error: string): NextResponse {
  return NextResponse.json({ error }, { status: 400 });
}

function keysOf(raw: string | null): string[] | null {
  if (!raw) return null;
  const keys = raw.split(',').map((part) => issueKeyParam(part.trim()));
  if (keys.length > START_DATE_BATCH || keys.some((key) => key === null)) return null;
  return [...new Set(keys as string[])];
}

export async function GET(request: NextRequest) {
  const auth = await requireJira();
  if (!auth.ok) return auth.response;
  const keys = keysOf(request.nextUrl.searchParams.get('keys'));
  if (!keys) return badRequest(`chaves inválidas — informe de 1 a ${START_DATE_BATCH} no formato ABC-123`);

  try {
    const suggestions = await jiraActions.suggestStartDates(auth.value.connection, keys);
    const failed = suggestions.flatMap((s) => (s.status === 'failed' ? [s.error] : []));
    if (failed.length === suggestions.length) return upstreamError(new Error(failed[0]));
    return NextResponse.json({ suggestions });
  } catch (err) {
    return upstreamError(err);
  }
}

function today(): string {
  const now = new Date();
  const pad = (n: number) => String(n).padStart(2, '0');
  return `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}`;
}

type Items = { key: string; date: string }[];

function itemsOf(body: unknown): Items | string {
  const raw = typeof body === 'object' && body !== null ? (body as { items?: unknown }).items : undefined;
  if (!Array.isArray(raw) || raw.length === 0 || raw.length > START_DATE_BATCH) {
    return `informe de 1 a ${START_DATE_BATCH} datas`;
  }
  const limit = today();
  const items: Items = [];
  for (const entry of raw) {
    if (typeof entry !== 'object' || entry === null) return 'item inválido';
    const { key: rawKey, date } = entry as { key?: unknown; date?: unknown };
    const key = issueKeyParam(rawKey);
    if (!key) return 'chave inválida — use o formato ABC-123';
    if (items.some((item) => item.key === key)) return `chave repetida (${key})`;
    if (!isCalendarDate(date)) return `data inválida para ${key} — use AAAA-MM-DD`;
    if (date > limit) return `a data de início de ${key} não pode estar no futuro`;
    items.push({ key, date });
  }
  return items;
}

export async function POST(request: NextRequest) {
  const auth = await requireJira();
  if (!auth.ok) return auth.response;
  const items = itemsOf(await request.json().catch(() => null));
  if (typeof items === 'string') return badRequest(items);

  let results;
  try {
    results = await jiraActions.startDates({userId: auth.value.user.id, connection: auth.value.connection}, items);
  } catch (err) {
    return upstreamError(err);
  }
  if (results.some((r) => r.outcome === 'written')) return writeDone(auth.value.user.id, { results });
  return NextResponse.json({ results });
}
