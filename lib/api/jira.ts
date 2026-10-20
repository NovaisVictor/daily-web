import { NextResponse } from 'next/server';
import { requireUser, type ConnectionContext, type Guard } from '@/lib/api/context';
import { jiraConnectionOf } from '@/lib/jiraPeople';
import { isJiraKey } from '@/lib/preferences';
import { dropCache } from '@/lib/refresher';

/** A sessão e a conexão do Jira dela. A escrita usa sempre o token de quem
 *  está logado: quem decide o que ele pode fazer é o Jira, issue por issue. */
export async function requireJira(): Promise<Guard<ConnectionContext>> {
  const auth = await requireUser();
  if (!auth.ok) return auth;
  const connection = jiraConnectionOf(auth.value.id);
  if (!connection) {
    return { ok: false, response: NextResponse.json({ error: 'Jira não conectado' }, { status: 400 }) };
  }
  return { ok: true, value: { user: auth.value, connection } };
}

/** A chave do segmento da rota, já validada: ela entra em caminho de URL e em
 *  JQL, e um valor livre ali seria injeção. */
export function issueKeyParam(value: unknown): string | null {
  return isJiraKey(value) ? String(value).toUpperCase() : null;
}

export function invalidKey(): NextResponse {
  return NextResponse.json({ error: 'chave inválida — use o formato ABC-123' }, { status: 400 });
}

/** Depois de gravar, o estado em cache mente: a próxima leitura busca de novo. */
export function writeDone(userId: string, payload: Record<string, unknown> = {}): NextResponse {
  dropCache(userId);
  return NextResponse.json({ ok: true, ...payload });
}
