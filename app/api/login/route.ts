import { NextRequest, NextResponse } from 'next/server';
import { verifyPassword } from '@/lib/auth/password';
import { createSessionToken, SESSION_COOKIE } from '@/lib/auth/session';
import { findUserByUsername } from '@/lib/auth/users';
import { recordLogin } from '@/lib/preferences';
import { isRateLimited, registerFailedAttempt, clearAttempts, extractClientIp } from '@/lib/auth/rateLimit';

const SESSION_MAX_AGE_SECONDS = 30 * 24 * 60 * 60;

// Hash bcrypt válido de uma senha que ninguém usa. Quando o username não
// existe, comparamos contra ele mesmo assim: sem isso, "usuário inexistente"
// responde em microssegundos e "senha errada" leva o tempo do bcrypt, o que
// denuncia quais contas existem.
const DUMMY_HASH = '$2a$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy';

export async function POST(request: NextRequest) {
  const ip = extractClientIp(request.headers.get('x-forwarded-for'));
  if (isRateLimited(ip)) {
    return NextResponse.json({ error: 'muitas tentativas, tente mais tarde' }, { status: 429 });
  }

  const body = await request.json().catch(() => null);
  const username = typeof body?.username === 'string' ? body.username : '';
  const password = typeof body?.password === 'string' ? body.password : '';

  const secret = process.env.SESSION_SECRET ?? '';
  if (!secret) {
    return NextResponse.json({ error: 'servidor sem configuração de autenticação' }, { status: 500 });
  }

  const user = findUserByUsername(username);
  const ok = await verifyPassword(password, user?.passwordHash ?? DUMMY_HASH);
  if (!user || !ok) {
    registerFailedAttempt(ip);
    return NextResponse.json({ error: 'usuário ou senha inválidos' }, { status: 401 });
  }

  clearAttempts(ip);
  recordLogin(user.id);
  const token = await createSessionToken(user.id, user.username, secret);
  const response = NextResponse.json({ ok: true });
  response.cookies.set(SESSION_COOKIE, token, {
    httpOnly: true,
    secure: true,
    // `strict` não envia o cookie quando a navegação vem de outro site, o que
    // inclui a volta do consentimento do Google: o retorno chegava sem sessão
    // e o middleware respondia 401. `lax` envia em navegação de topo com
    // método seguro — exatamente o caso do callback — e continua não enviando
    // em POST/PUT/PATCH/DELETE de outro site, que é onde mora o CSRF.
    // Toda mutação desta app usa um desses métodos; o único GET que altera
    // estado é o callback do OAuth, protegido pelo `state` assinado.
    sameSite: 'lax',
    maxAge: SESSION_MAX_AGE_SECONDS,
    path: '/',
  });
  return response;
}
