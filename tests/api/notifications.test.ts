import { describe, expect, it, beforeEach, vi } from 'vitest';
import { mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';

const currentUser = vi.fn();
vi.mock('@/lib/auth/currentUser', () => ({ getCurrentUser: () => currentUser() }));

const ME = { id: 'u-1', username: 'joao', passwordHash: 'x', isAdmin: true, createdAt: '' };
const req = (id: unknown) =>
  new Request('http://localhost/api/notifications/read', { method: 'POST', body: JSON.stringify({ id }) });

beforeEach(() => {
  vi.resetModules();
  process.env.DAILY_WEB_DB_PATH = path.join(mkdtempSync(path.join(tmpdir(), 'daily-web-db-')), 'test.db');
  currentUser.mockReturnValue(ME);
});

describe('POST /api/notifications/read', () => {
  // A rota fixava a fonte em 'jira_mention'. O aviso de PR era gravado na
  // chave errada e voltava a aparecer no ciclo seguinte, para sempre.
  it('grava o aviso de PR na fonte pull_request', async () => {
    const { POST } = await import('@/app/api/notifications/read/route');
    const { isRead } = await import('@/lib/notifications');

    const res = await POST(req('pull_request:joao/repo#7'));
    expect(res.status).toBe(200);
    expect(isRead('u-1', 'pull_request', 'joao/repo#7')).toBe(true);
    expect(isRead('u-1', 'jira_mention', 'joao/repo#7')).toBe(false);
  });

  it('grava a revisão parada na sua própria chave, sem marcar o aviso do PR', async () => {
    const { POST } = await import('@/app/api/notifications/read/route');
    const { isRead } = await import('@/lib/notifications');

    const res = await POST(req('pull_request:joao/repo#7:stale-review'));
    expect(res.status).toBe(200);
    expect(isRead('u-1', 'pull_request', 'joao/repo#7:stale-review')).toBe(true);
    expect(isRead('u-1', 'pull_request', 'joao/repo#7')).toBe(false);
  });

  it('grava o aviso de e-mail na fonte email, com o id externo inteiro', async () => {
    const { POST } = await import('@/app/api/notifications/read/route');
    const { isRead } = await import('@/lib/notifications');

    await POST(req('email:mail-1:<a@x>'));
    expect(isRead('u-1', 'email', 'mail-1:<a@x>')).toBe(true);
  });

  it('continua gravando a menção do Jira como antes', async () => {
    const { POST } = await import('@/app/api/notifications/read/route');
    const { isRead } = await import('@/lib/notifications');

    await POST(req('jira_mention:ENG-1'));
    expect(isRead('u-1', 'jira_mention', 'ENG-1')).toBe(true);
  });

  it('recusa um id que não nomeia uma fonte conhecida', async () => {
    const { POST } = await import('@/app/api/notifications/read/route');
    const res = await POST(req('inventada:X-1'));
    expect(res.status).toBe(400);
  });

  it('não deixa quem não entrou marcar nada como lido', async () => {
    currentUser.mockReturnValue(null);
    const { POST } = await import('@/app/api/notifications/read/route');
    const res = await POST(req('jira_mention:ENG-1'));
    expect(res.status).toBe(401);
  });

  it('recusa um corpo sem id', async () => {
    const { POST } = await import('@/app/api/notifications/read/route');
    expect((await POST(req(undefined))).status).toBe(400);
  });
});

// Marcar tudo é a mesma escrita, em lote: o sino manda a lista que está na
// tela e a rota grava cada aviso na chave da sua própria fonte.
describe('POST /api/notifications/read com uma lista', () => {
  const reqIds = (ids: unknown) =>
    new Request('http://localhost/api/notifications/read', {
      method: 'POST',
      body: JSON.stringify({ ids }),
    });

  it('grava cada aviso na fonte certa', async () => {
    const { POST } = await import('@/app/api/notifications/read/route');
    const { isRead } = await import('@/lib/notifications');

    const res = await POST(reqIds(['jira_mention:ENG-1', 'pull_request:joao/repo#7', 'email:mail-1:<a@x>']));
    expect(res.status).toBe(200);
    expect(await res.json()).toMatchObject({ ok: true, marked: 3 });
    expect(isRead('u-1', 'jira_mention', 'ENG-1')).toBe(true);
    expect(isRead('u-1', 'pull_request', 'joao/repo#7')).toBe(true);
    expect(isRead('u-1', 'email', 'mail-1:<a@x>')).toBe(true);
  });

  // Gravar parte do lote deixaria a tela dizendo "tudo lido" com avisos que
  // voltam no ciclo seguinte.
  it('reprova o lote inteiro quando um id é irreconhecível', async () => {
    const { POST } = await import('@/app/api/notifications/read/route');
    const { isRead } = await import('@/lib/notifications');

    const res = await POST(reqIds(['jira_mention:ENG-1', 'inventada:X-1']));
    expect(res.status).toBe(400);
    expect(isRead('u-1', 'jira_mention', 'ENG-1')).toBe(false);
  });

  it('marcar de novo o que já estava lido não é erro', async () => {
    const { POST } = await import('@/app/api/notifications/read/route');
    await POST(reqIds(['jira_mention:ENG-1']));
    expect((await POST(reqIds(['jira_mention:ENG-1']))).status).toBe(200);
  });

  it('recusa uma lista vazia e uma que não é lista', async () => {
    const { POST } = await import('@/app/api/notifications/read/route');
    expect((await POST(reqIds([]))).status).toBe(400);
    expect((await POST(reqIds('jira_mention:ENG-1'))).status).toBe(400);
    expect((await POST(reqIds([1, 2]))).status).toBe(400);
  });

  // Teto de segurança: o sino traz no máximo 20 por fonte, três fontes.
  it('recusa um lote maior do que a tela poderia mostrar', async () => {
    const { POST } = await import('@/app/api/notifications/read/route');
    const muitos = Array.from({ length: 201 }, (_, i) => `jira_mention:ENG-${i}`);
    expect((await POST(reqIds(muitos))).status).toBe(400);
  });

  it('não deixa quem não entrou marcar o lote', async () => {
    currentUser.mockReturnValue(null);
    const { POST } = await import('@/app/api/notifications/read/route');
    expect((await POST(reqIds(['jira_mention:ENG-1']))).status).toBe(401);
  });
});
