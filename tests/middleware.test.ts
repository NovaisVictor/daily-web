import { describe, expect, it, afterEach } from 'vitest';
import { createHmac } from 'node:crypto';
import { NextRequest } from 'next/server';
import { createSessionToken } from '@/lib/auth/session';
import { middleware } from '@/middleware';

const ORIGINAL_SECRET = process.env.SESSION_SECRET;

afterEach(() => {
  process.env.SESSION_SECRET = ORIGINAL_SECRET;
});

function makeRequest(pathname: string, token?: string): NextRequest {
  const headers = new Headers();
  if (token) headers.set('cookie', `daily_web_session=${token}`);
  return new NextRequest(new URL(`http://localhost${pathname}`), { headers });
}

// crypto.subtle.importKey rejeita chave HMAC de tamanho zero (por isso
// createSessionToken('', ...) não pode ser usado aqui para forjar o token) —
// mas HMAC-SHA256 com chave vazia é perfeitamente válido fora do WebCrypto
// (ex.: node:crypto ou openssl), então um atacante consegue forjar um token
// assim caso descubra que SESSION_SECRET está vazio.
function forgeTokenWithEmptySecret(user: string): string {
  const payloadB64 = Buffer.from(JSON.stringify({ user, issuedAt: Date.now() }), 'utf8').toString(
    'base64url',
  );
  const sig = createHmac('sha256', '').update(payloadB64).digest('base64url');
  return `${payloadB64}.${sig}`;
}

describe('middleware', () => {
  it('deixa passar uma requisição de API com token válido quando SESSION_SECRET está configurado', async () => {
    process.env.SESSION_SECRET = 'real-secret';
    const token = await createSessionToken('u-1', 'joao', 'real-secret');
    const res = await middleware(makeRequest('/api/tasks', token));
    expect(res.status).toBe(200);
  });

  it('falha fechado (401) em rota de API quando SESSION_SECRET está ausente, mesmo com token forjado com segredo vazio', async () => {
    process.env.SESSION_SECRET = '';
    const forgedToken = forgeTokenWithEmptySecret('attacker');
    const res = await middleware(makeRequest('/api/tasks', forgedToken));
    expect(res.status).toBe(401);
  });

  it('redireciona para /login em rota de página quando SESSION_SECRET está ausente, mesmo com token forjado com segredo vazio', async () => {
    process.env.SESSION_SECRET = '';
    const forgedToken = forgeTokenWithEmptySecret('attacker');
    const res = await middleware(makeRequest('/', forgedToken));
    expect(res.status).toBe(307);
    expect(res.headers.get('location')).toContain('/login');
  });

  it('nega acesso a rota de API sem nenhum token, independentemente do segredo', async () => {
    process.env.SESSION_SECRET = 'real-secret';
    const res = await middleware(makeRequest('/api/tasks'));
    expect(res.status).toBe(401);
  });

  // O Chrome busca o manifest sem credenciais e registra o service worker
  // antes de qualquer sessão. Atrás do login eles receberiam o HTML do
  // redirect e a app deixaria de ser instalável.
  it.each(['/manifest.webmanifest', '/sw.js', '/icon.svg', '/icons/icon-192.png'])(
    'deixa %s passar sem sessão, para a app continuar instalável',
    async (path) => {
      process.env.SESSION_SECRET = 'real-secret';
      const res = await middleware(makeRequest(path));
      expect(res.status).toBe(200);
      expect(res.headers.get('location')).toBeNull();
    },
  );

  // Barrado no middleware, o retorno do Google virava {"error":"não
  // autenticado"} cru na tela. A rota trata a própria autenticação e
  // redireciona com uma mensagem legível.
  it('deixa o callback do OAuth passar para a rota tratar', async () => {
    process.env.SESSION_SECRET = 'real-secret';
    const res = await middleware(makeRequest('/api/integrations/agenda/google/callback?code=x'));
    expect(res.status).toBe(200);
  });

  it('não abre as demais rotas de integração junto com o callback', async () => {
    process.env.SESSION_SECRET = 'real-secret';
    for (const path of [
      '/api/integrations',
      '/api/integrations/agenda/google/start',
      '/api/integrations/agenda/google/calendars',
    ]) {
      expect((await middleware(makeRequest(path))).status).toBe(401);
    }
  });

  it('não abre a app inteira junto com os arquivos públicos', async () => {
    process.env.SESSION_SECRET = 'real-secret';
    for (const path of ['/', '/config', '/api/state', '/iconsxx']) {
      const res = await middleware(makeRequest(path));
      expect(res.status).not.toBe(200);
    }
  });
});

describe('MCP OAuth public protocol routes',()=>{
  it.each(['/oauth/auth','/oauth/token','/oauth/reg','/.well-known/oauth-authorization-server','/.well-known/oauth-authorization-server/oauth','/.well-known/openid-configuration','/.well-known/openid-configuration/oauth'])('delegates %s authentication to the provider',async path=>{
    process.env.SESSION_SECRET='';expect((await middleware(makeRequest(path))).status).toBe(200);
  });
  it.each(['/access/consent','/api/agent-access/grants','/oauth-elsewhere'])('keeps %s browser-authenticated',async path=>{
    process.env.SESSION_SECRET='';expect((await middleware(makeRequest(path))).status).not.toBe(200);
  });
});
