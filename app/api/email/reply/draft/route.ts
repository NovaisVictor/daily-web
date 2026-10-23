import { NextRequest, NextResponse } from 'next/server';
import { fetchBody, mailConfig } from '@/lib/integrations/imap';
import { getCachedBody, putCachedBody } from '@/lib/emailCache';
import { draftReply, MissingApiKeyError } from '@/lib/ai/replyDraft';
import { isValidEmailId } from '@/lib/api/validation';
import { requireConnection, upstreamError } from '@/lib/api/context';

export async function POST(request: NextRequest) {
  const payload = await request.json().catch(() => null);
  if (!isValidEmailId(payload?.id)) {
    return NextResponse.json({ error: 'id inválido' }, { status: 400 });
  }

  const guard = await requireConnection('email', payload?.account);
  if (!guard.ok) return guard.response;
  const { user, connection } = guard.value;
  const { account, id, from, subject, instruction } = payload;

  try {
    // Mesmo caminho do corpo exibido no acordeão: o refresher normalmente já
    // deixou o texto em cache, então gerar o rascunho não custa uma ida ao IMAP.
    let body = getCachedBody(user.id, account, id);
    if (body === null) {
      body = await fetchBody(connection, id);
      putCachedBody(user.id, account, id, body);
    }
    const text = await draftReply({
      sender: mailConfig(connection).user,
      from: typeof from === 'string' ? from : '',
      subject: typeof subject === 'string' ? subject : '',
      body,
      instruction: typeof instruction === 'string' ? instruction : undefined,
    });
    return NextResponse.json({ text });
  } catch (err) {
    if (err instanceof MissingApiKeyError) {
      return NextResponse.json({ error: err.message }, { status: 503 });
    }
    return upstreamError(err);
  }
}
