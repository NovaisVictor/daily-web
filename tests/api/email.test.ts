import { describe, expect, it, beforeEach, afterEach, vi } from 'vitest';
import { NextRequest } from 'next/server';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';

vi.mock('@/lib/integrations/imap', async (importOriginal) => ({
  // The real mailConfig, so the sender the draft route reads comes from the
  // stored connection exactly as in production.
  mailConfig: (await importOriginal<typeof import('@/lib/integrations/imap')>()).mailConfig,
  setSeen: vi.fn(),
  applyTag: vi.fn(),
  deleteEmails: vi.fn(),
  listFolders: vi.fn(),
  sendReply: vi.fn(),
  fetchBody: vi.fn(),
}));

vi.mock('@/lib/ai/replyDraft', async (importOriginal) => ({
  ...(await importOriginal<typeof import('@/lib/ai/replyDraft')>()),
  draftReply: vi.fn(),
}));

const currentUser = vi.fn();
vi.mock('@/lib/auth/currentUser', () => ({ getCurrentUser: () => currentUser() }));

import { setSeen, applyTag, deleteEmails, listFolders, sendReply, fetchBody } from '@/lib/integrations/imap';
import { draftReply } from '@/lib/ai/replyDraft';
import { POST as markRoute } from '@/app/api/email/mark/route';
import { POST as batchRoute } from '@/app/api/email/batch/route';
import { GET as foldersRoute } from '@/app/api/email/folders/route';
import { POST as tagRoute } from '@/app/api/email/tag/route';
import { POST as replyRoute } from '@/app/api/email/reply/route';
import { POST as draftRoute } from '@/app/api/email/reply/draft/route';

let dir: string;
let mailId: string;
let otherMailId: string;

const ME = { id: 'u-1', username: 'joao', passwordHash: 'x', isAdmin: true, createdAt: '' };
const SOMEONE_ELSE = { id: 'u-2', username: 'maria', passwordHash: 'x', isAdmin: false, createdAt: '' };

function req(body: unknown): NextRequest {
  return new NextRequest('http://localhost/api', { method: 'POST', body: JSON.stringify(body) });
}

beforeEach(async () => {
  dir = mkdtempSync(path.join(tmpdir(), 'daily-web-email-api-'));
  process.env.DAILY_WEB_DB_PATH = path.join(dir, 'test.db');
  process.env.DAILY_WEB_SECRET_KEY = Buffer.alloc(32, 5).toString('base64');
  vi.clearAllMocks();
  currentUser.mockResolvedValue(ME);

  const { getDb } = await import('@/lib/db');
  getDb();
  const { saveConnection } = await import('@/lib/vault/connections');
  mailId = saveConnection(ME.id, 'email', 'Trabalho', {
    preset: 'gmail',
    user: 'a@x.com',
    password: 's',
  });
  otherMailId = saveConnection(SOMEONE_ELSE.id, 'email', 'Dela', {
    preset: 'gmail',
    user: 'b@x.com',
    password: 's',
  });
});

afterEach(() => {
  rmSync(dir, { recursive: true, force: true });
});

describe('POST /api/email/mark', () => {
  it('marca como lido na conexão do usuário', async () => {
    const res = await markRoute(req({ account: mailId, id: '42', seen: true }));
    expect(res.status).toBe(200);
    expect(vi.mocked(setSeen).mock.calls[0][0].id).toBe(mailId);
    expect(vi.mocked(setSeen).mock.calls[0][1]).toEqual(['42']);
  });

  it('rejeita id fora do formato sem tocar no IMAP', async () => {
    const res = await markRoute(req({ account: mailId, id: '../x', seen: true }));
    expect(res.status).toBe(400);
    expect(setSeen).not.toHaveBeenCalled();
  });

  // O isolamento não é "proibido": a conexão de outra pessoa simplesmente
  // não existe para esta sessão.
  it('não deixa usar a caixa de outro usuário', async () => {
    const res = await markRoute(req({ account: otherMailId, id: '42', seen: true }));
    expect(res.status).toBe(404);
    expect(setSeen).not.toHaveBeenCalled();
  });

  it('exige sessão', async () => {
    currentUser.mockResolvedValue(null);
    const res = await markRoute(req({ account: mailId, id: '42', seen: true }));
    expect(res.status).toBe(401);
    expect(setSeen).not.toHaveBeenCalled();
  });
});

describe('GET /api/email/folders', () => {
  it('lista as pastas da conexão', async () => {
    vi.mocked(listFolders).mockResolvedValue(['INBOX', 'Clientes']);
    const res = await foldersRoute(
      new NextRequest(`http://localhost/api/email/folders?account=${mailId}`),
    );
    expect((await res.json()).folders).toEqual(['INBOX', 'Clientes']);
  });

  it('recusa a caixa de outro usuário', async () => {
    const res = await foldersRoute(
      new NextRequest(`http://localhost/api/email/folders?account=${otherMailId}`),
    );
    expect(res.status).toBe(404);
    expect(listFolders).not.toHaveBeenCalled();
  });
});

describe('POST /api/email/tag', () => {
  it('aplica a etiqueta', async () => {
    const res = await tagRoute(req({ account: mailId, id: '42', tag: 'Clientes' }));
    expect(res.status).toBe(200);
    expect(vi.mocked(applyTag).mock.calls[0][2]).toBe('Clientes');
  });

  it('rejeita etiqueta com caractere fora do permitido', async () => {
    const res = await tagRoute(req({ account: mailId, id: '42', tag: '../etc' }));
    expect(res.status).toBe(400);
    expect(applyTag).not.toHaveBeenCalled();
  });
});

describe('POST /api/email/reply', () => {
  it('envia a resposta', async () => {
    const res = await replyRoute(req({ account: mailId, id: '42', body: 'Combinado.' }));
    expect(res.status).toBe(200);
    expect(vi.mocked(sendReply).mock.calls[0][2]).toBe('Combinado.');
  });

  it('recusa resposta vazia', async () => {
    const res = await replyRoute(req({ account: mailId, id: '42', body: '   ' }));
    expect(res.status).toBe(400);
    expect(sendReply).not.toHaveBeenCalled();
  });

  it('devolve 502 quando o SMTP falha', async () => {
    vi.mocked(sendReply).mockRejectedValue(new Error('Trabalho: senha recusada'));
    const res = await replyRoute(req({ account: mailId, id: '42', body: 'oi' }));
    expect(res.status).toBe(502);
    expect((await res.json()).error).toContain('senha recusada');
  });
});

describe('POST /api/email/reply/draft', () => {
  it('escreve o rascunho em nome da caixa que vai enviar a resposta', async () => {
    vi.mocked(fetchBody).mockResolvedValue('Pode confirmar a reunião?');
    vi.mocked(draftReply).mockResolvedValue('Confirmado.');
    const res = await draftRoute(
      req({ account: mailId, id: '42', from: 'cliente@y.com', subject: 'Reunião' }),
    );
    expect(res.status).toBe(200);
    expect(vi.mocked(draftReply).mock.calls[0][0]).toMatchObject({
      sender: 'a@x.com',
      from: 'cliente@y.com',
    });
  });
});

describe('POST /api/email/batch', () => {
  it('aplica a ação em cada alvo', async () => {
    const res = await batchRoute(
      req({
        action: 'read',
        targets: [
          { account: mailId, id: '1' },
          { account: mailId, id: '2' },
        ],
      }),
    );
    const data = await res.json();
    expect(data.results.every((r: { ok: boolean }) => r.ok)).toBe(true);
    // Uma chamada com os dois ids, não uma por id: cada chamada abre a sua
    // conexão IMAP, e o servidor recusa o lote inteiro por excesso delas.
    expect(setSeen).toHaveBeenCalledTimes(1);
    expect(vi.mocked(setSeen).mock.calls[0][1]).toEqual(['1', '2']);
  });

  // A ação vale quando fica gravada, não quando chega ao servidor: uma escrita
  // que falhou continua pendente e é repetida, em vez de a mensagem voltar
  // para a tela como se nada tivesse sido pedido.
  it('aceita os alvos e mantém a intenção quando a escrita falha', async () => {
    vi.mocked(deleteEmails).mockRejectedValueOnce(new Error('sumiu'));

    const res = await batchRoute(
      req({
        action: 'delete',
        targets: [
          { account: mailId, id: '1' },
          { account: mailId, id: '2' },
        ],
      }),
    );
    const data = await res.json();
    expect(data.results).toHaveLength(2);
    expect(data.results.every((r: { ok: boolean }) => r.ok)).toBe(true);

    const { listPendingActions } = await import('@/lib/email/pendingActions');
    const pendentes = listPendingActions(ME.id);
    expect(pendentes.map((a) => a.uid).sort()).toEqual(['1', '2']);
    expect(pendentes.every((a) => a.state === 'pending' && a.appliedAt === null)).toBe(true);
    expect(pendentes[0].lastError).toBe('sumiu');
  });

  // Um id fora do formato não pode arrastar o lote inteiro: ele é recusado
  // sozinho e o resto segue.
  it('separa o alvo inválido sem cancelar os válidos', async () => {
    const res = await batchRoute(
      req({
        action: 'delete',
        targets: [
          { account: mailId, id: '1' },
          { account: mailId, id: '../x' },
          { account: mailId, id: '2' },
        ],
      }),
    );
    const data = await res.json();
    const porId = Object.fromEntries(
      data.results.map((r: { id: string; ok: boolean }) => [r.id, r.ok]),
    );
    expect(porId['../x']).toBe(false);
    expect(porId['1']).toBe(true);
    expect(porId['2']).toBe(true);
    expect(vi.mocked(deleteEmails).mock.calls[0][1]).toEqual(['1', '2']);
  });

  it('marca como falha o alvo que aponta para a caixa de outro usuário', async () => {
    const res = await batchRoute(
      req({ action: 'read', targets: [{ account: otherMailId, id: '1' }] }),
    );
    const data = await res.json();
    expect(data.results[0]).toMatchObject({ ok: false, error: 'conta não encontrada' });
    expect(setSeen).not.toHaveBeenCalled();
  });

  it('recusa ação desconhecida', async () => {
    const res = await batchRoute(
      req({ action: 'apagar-tudo', targets: [{ account: mailId, id: '1' }] }),
    );
    expect(res.status).toBe(400);
  });

  it('exige pasta na ação de mover', async () => {
    const res = await batchRoute(
      req({ action: 'move', targets: [{ account: mailId, id: '1' }] }),
    );
    expect(res.status).toBe(400);
    expect(applyTag).not.toHaveBeenCalled();
  });
});
