import { describe, expect, it, beforeEach, afterEach, vi } from 'vitest';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';

const REAL_IP = '203.0.113.42';
const ORIGINAL_ENV = { ...process.env };
let dir: string;

beforeEach(() => {
  dir = mkdtempSync(path.join(tmpdir(), 'daily-web-login-'));
  process.env.DAILY_WEB_DB_PATH = path.join(dir, 'test.db');
  process.env.SESSION_SECRET = 'segredo-de-teste';
  delete process.env.DASHBOARD_USER;
  delete process.env.DASHBOARD_PASSWORD_HASH;
  vi.resetModules();
});

afterEach(() => {
  rmSync(dir, { recursive: true, force: true });
  process.env = { ...ORIGINAL_ENV };
});

function loginRequest(username: string, password: string, xForwardedFor = REAL_IP): Request {
  return new Request('http://localhost/api/login', {
    method: 'POST',
    headers: { 'x-forwarded-for': xForwardedFor, 'content-type': 'application/json' },
    body: JSON.stringify({ username, password }),
  });
}

async function load() {
  const { POST } = await import('@/app/api/login/route');
  const users = await import('@/lib/auth/users');
  const session = await import('@/lib/auth/session');
  return { POST, ...users, ...session };
}

function sessionCookie(res: Response): string {
  const raw = res.headers.get('set-cookie') ?? '';
  return raw.split(';')[0].replace('daily_web_session=', '');
}

describe('POST /api/login com usuários no banco', () => {
  it('registra cada login: o primeiro recebe boas-vindas, o segundo recebe "de volta"', async () => {
    const { POST, createUser } = await load();
    const { welcomeKind } = await import('@/lib/preferences');
    const created = await createUser('maria', 'senha-da-maria');
    expect(welcomeKind(created.id)).toBe('first');

    await POST(loginRequest('maria', 'senha-da-maria') as never);
    expect(welcomeKind(created.id)).toBe('first');

    await POST(loginRequest('maria', 'senha-da-maria') as never);
    expect(welcomeKind(created.id)).toBe('returning');
  });

  it('não conta uma tentativa com a senha errada', async () => {
    const { POST, createUser } = await load();
    const { welcomeKind } = await import('@/lib/preferences');
    const created = await createUser('maria', 'senha-da-maria');

    await POST(loginRequest('maria', 'errada') as never);
    await POST(loginRequest('maria', 'errada') as never);
    await POST(loginRequest('maria', 'senha-da-maria') as never);

    expect(welcomeKind(created.id)).toBe('first');
  });

  it('aceita a senha correta e devolve uma sessão com o userId', async () => {
    const { POST, createUser, verifySessionToken } = await load();
    const created = await createUser('maria', 'senha-da-maria');

    const res = await POST(loginRequest('maria', 'senha-da-maria') as never);
    expect(res.status).toBe(200);

    const payload = await verifySessionToken(sessionCookie(res), 'segredo-de-teste', 60_000);
    expect(payload?.userId).toBe(created.id);
    expect(payload?.user).toBe('maria');
  });

  it('dá sessões diferentes para usuários diferentes', async () => {
    const { POST, createUser, verifySessionToken } = await load();
    await createUser('maria', 'senha-da-maria');
    await createUser('joao', 'senha-do-joao');

    const resMaria = await POST(loginRequest('maria', 'senha-da-maria') as never);
    const resJoao = await POST(loginRequest('joao', 'senha-do-joao', '198.51.100.9') as never);

    const maria = await verifySessionToken(sessionCookie(resMaria), 'segredo-de-teste', 60_000);
    const joao = await verifySessionToken(sessionCookie(resJoao), 'segredo-de-teste', 60_000);
    expect(maria?.userId).not.toBe(joao?.userId);
  });

  it('recusa a senha errada', async () => {
    const { POST, createUser } = await load();
    await createUser('maria', 'senha-da-maria');
    const res = await POST(loginRequest('maria', 'senha-errada') as never);
    expect(res.status).toBe(401);
  });

  it('recusa usuário inexistente', async () => {
    const { POST } = await load();
    const res = await POST(loginRequest('ninguem', 'qualquer-senha') as never);
    expect(res.status).toBe(401);
  });

  // Sem comparar contra um hash descartável, "usuário não existe" responde
  // muito mais rápido que "senha errada" e denuncia quais contas existem.
  it('não distingue usuário inexistente de senha errada pelo tempo', async () => {
    const { POST, createUser } = await load();
    await createUser('maria', 'senha-da-maria');

    const time = async (req: Request) => {
      const t0 = performance.now();
      await POST(req as never);
      return performance.now() - t0;
    };

    const existente = await time(loginRequest('maria', 'senha-errada', '198.51.100.1'));
    const inexistente = await time(loginRequest('ninguem', 'senha-errada', '198.51.100.2'));
    const menor = Math.min(existente, inexistente);
    const maior = Math.max(existente, inexistente);
    // bcrypt domina os dois caminhos; a folga larga evita teste instável.
    expect(maior).toBeLessThan(menor * 5 + 20);
  });

  it('sem SESSION_SECRET responde 500 em vez de emitir sessão', async () => {
    delete process.env.SESSION_SECRET;
    const { POST, createUser } = await load();
    await createUser('maria', 'senha-da-maria');
    const res = await POST(loginRequest('maria', 'senha-da-maria') as never);
    expect(res.status).toBe(500);
  });
});

describe('POST /api/login — rate limit resistente a X-Forwarded-For forjado', () => {
  it('bloqueia após 5 tentativas mesmo quando o cliente varia a entrada forjável a cada tentativa', async () => {
    const { POST, createUser } = await load();
    await createUser('maria', 'senha-da-maria');
    for (let i = 0; i < 5; i += 1) {
      const res = await POST(loginRequest('maria', 'errada', `forjado-${i}, ${REAL_IP}`) as never);
      expect(res.status).toBe(401);
    }
    const res = await POST(loginRequest('maria', 'errada', `forjado-outro, ${REAL_IP}`) as never);
    expect(res.status).toBe(429);
  });

  it('IPs reais diferentes (última entrada) continuam com limites independentes', async () => {
    const { POST, createUser } = await load();
    await createUser('maria', 'senha-da-maria');
    for (let i = 0; i < 5; i += 1) {
      await POST(loginRequest('maria', 'errada', `x, ${REAL_IP}`) as never);
    }
    const res = await POST(loginRequest('maria', 'errada', 'x, 198.51.100.9') as never);
    expect(res.status).toBe(401);
  });
});

describe('atributos do cookie de sessão', () => {
  // `strict` não envia o cookie quando a navegação vem de outro site, o que
  // quebrava a volta do consentimento do Google com 401. `lax` resolve isso e
  // continua barrando CSRF, porque toda mutação desta app é POST/PUT/PATCH/
  // DELETE — métodos em que `lax` também não envia cookie cross-site.
  it('usa lax, para o retorno do OAuth chegar com sessão', async () => {
    const { POST, createUser } = await load();
    await createUser('maria', 'senha-da-maria');

    const res = await POST(loginRequest('maria', 'senha-da-maria') as never);
    const raw = res.headers.get('set-cookie') ?? '';

    expect(raw.toLowerCase()).toContain('samesite=lax');
    expect(raw.toLowerCase()).toContain('httponly');
    expect(raw.toLowerCase()).toContain('secure');
    expect(raw.toLowerCase()).toContain('path=/');
  });
});
