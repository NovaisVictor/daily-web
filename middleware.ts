import { NextRequest, NextResponse } from 'next/server';
import { verifySessionToken, SESSION_MAX_AGE_MS, SESSION_COOKIE } from '@/lib/auth/session';

// O callback do OAuth trata a própria autenticação: ele exige um `state`
// assinado e uma sessão do mesmo usuário. Barrá-lo aqui devolveria
// {"error":"não autenticado"} cru na tela do navegador no retorno do Google;
// deixando passar, a própria rota redireciona para /config com uma mensagem
// legível — e continua recusando quem não tem sessão.
const PUBLIC_PATHS = ['/login', '/api/login', '/api/integrations/agenda/google/callback', '/mcp', '/.well-known/oauth-protected-resource/mcp'];

// O Chrome busca o manifest sem credenciais e registra o service worker antes
// de qualquer sessão: atrás do login eles receberiam o HTML do redirect em vez
// do arquivo, e a app deixaria de ser instalável. Nenhum destes revela dado de
// usuário — são o ícone, o nome e um worker que só repassa requisições.
const PUBLIC_PREFIXES = ['/_next', '/icons/'];
const PUBLIC_ASSETS = ['/manifest.webmanifest', '/sw.js', '/icon.svg'];

export async function middleware(request: NextRequest) {
  const { pathname } = request.nextUrl;
  if (
    PUBLIC_PATHS.includes(pathname) ||
    pathname.startsWith('/api/v1/agents/') ||
    PUBLIC_ASSETS.includes(pathname) ||
    PUBLIC_PREFIXES.some((prefix) => pathname.startsWith(prefix))
  ) {
    return NextResponse.next();
  }

  const token = request.cookies.get(SESSION_COOKIE)?.value;
  const secret = process.env.SESSION_SECRET;
  // Fail closed: sem SESSION_SECRET configurado, nenhum token pode ser
  // considerado válido — verificar contra um segredo vazio aceitaria
  // qualquer token forjado com esse mesmo segredo vazio, conhecido.
  const session = token && secret ? await verifySessionToken(token, secret, SESSION_MAX_AGE_MS) : null;

  if (!session) {
    if (pathname.startsWith('/api')) {
      return NextResponse.json({ error: 'não autenticado' }, { status: 401 });
    }
    const publicOrigin = process.env.PUBLIC_ORIGIN;
    const loginUrl = publicOrigin ? new URL('/login', publicOrigin) : new URL('/login', request.nextUrl.origin);
    return NextResponse.redirect(loginUrl);
  }

  return NextResponse.next();
}

export const config = {
  matcher: ['/((?!_next/static|_next/image|favicon.ico).*)'],
};

export const runtime = 'nodejs';
