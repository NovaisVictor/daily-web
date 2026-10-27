import { describe, expect, it, beforeEach, afterEach, vi } from 'vitest';
import { NextRequest } from 'next/server';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';

const currentUser = vi.fn();
vi.mock('@/lib/auth/currentUser', () => ({ getCurrentUser: () => currentUser() }));

import { PATCH as route } from '@/app/api/preferences/route';

let dir: string;
const ME = { id: 'u-1', username: 'joao', passwordHash: 'x', isAdmin: true, createdAt: '' };

function req(body: unknown): NextRequest {
  return new NextRequest('http://localhost/api/preferences', {
    method: 'PATCH',
    body: JSON.stringify(body),
  });
}

beforeEach(async () => {
  dir = mkdtempSync(path.join(tmpdir(), 'daily-web-prefs-'));
  process.env.DAILY_WEB_DB_PATH = path.join(dir, 'test.db');
  vi.clearAllMocks();
  currentUser.mockResolvedValue(ME);
  const { getDb } = await import('@/lib/db');
  getDb();
});

afterEach(() => rmSync(dir, { recursive: true, force: true }));

describe('sessão', () => {
  it('exige usuário logado', async () => {
    currentUser.mockResolvedValue(null);
    expect((await route(req({ layout: null }))).status).toBe(401);
  });

  it('recusa corpo que não é objeto', async () => {
    expect((await route(req('nada')))?.status).toBe(400);
  });
});


describe('disposição por tamanho de tela', () => {
  const disp = [{ i: 'email', x: 5, y: 0, w: 7, h: 14 }];

  it('grava junto com o tamanho da janela', async () => {
    const res = await route(req({ layout: disp, viewport: { width: 1920, height: 1080 } }));
    expect(res.status).toBe(200);

    const { layouts } = await res.json();
    expect(layouts).toHaveLength(1);
    expect(layouts[0]).toMatchObject({ width: 1920, height: 1080 });
    expect(layouts[0].layout.find((p: { i: string }) => p.i === 'email').x).toBe(5);
  });

  it('guarda um tamanho por tela e substitui ao repetir', async () => {
    await route(req({ layout: disp, viewport: { width: 1920, height: 1080 } }));
    await route(req({ layout: disp, viewport: { width: 1512, height: 945 } }));
    const res = await route(
      req({
        layout: [{ i: 'email', x: 0, y: 0, w: 6, h: 14 }],
        viewport: { width: 1920, height: 1080 },
      }),
    );

    const { layouts } = await res.json();
    expect(layouts).toHaveLength(2);
    const grande = layouts.find((l: { width: number }) => l.width === 1920);
    expect(grande.layout.find((p: { i: string }) => p.i === 'email').w).toBe(6);
  });

  // Um deploy deixa abas abertas rodando o cliente anterior, que gravava a
  // cada arraste sem mandar tamanho. Recusar isso fazia a aba antiga mostrar
  // erro no meio do arrasto.
  it('aceita o cliente antigo, que não manda tamanho', async () => {
    const res = await route(req({ layout: disp }));
    expect(res.status).toBe(200);

    // Vai para a disposição única, que é o que aquele cliente sempre gravou.
    const { layout, layouts } = await res.json();
    expect(layouts).toEqual([]);
    expect(layout.find((p: { i: string }) => p.i === 'email').x).toBe(5);
  });

  it('a disposição única do cliente antigo vale enquanto não há por tamanho', async () => {
    await route(req({ layout: disp }));

    const { dashboardLayout, dashboardLayouts } = await import('@/lib/preferences');
    expect(dashboardLayouts('u-1')).toEqual([]);
    expect(dashboardLayout('u-1').find((p) => p.i === 'email')?.x).toBe(5);
  });

  it('gravar por tamanho depois não é atrapalhado pelo cliente antigo', async () => {
    await route(req({ layout: disp }));
    const res = await route(
      req({ layout: [{ i: 'email', x: 0, y: 0, w: 6, h: 14 }], viewport: { width: 1920, height: 1080 } }),
    );
    const { layouts } = await res.json();
    expect(layouts).toHaveLength(1);
    expect(layouts[0].layout.find((p: { i: string }) => p.i === 'email').w).toBe(6);
  });

  // Tamanho presente e sem sentido é defeito de cliente, não aba velha.
  it('recusa tamanho que não vem de tela nenhuma', async () => {
    for (const viewport of [
      { width: 0, height: 900 },
      { width: -1, height: 900 },
      { width: 1920, height: 0 },
      { width: 999_999, height: 900 },
      { width: 'grande', height: 900 },
      { width: 1920 },
    ]) {
      const res = await route(req({ layout: disp, viewport }));
      expect(res.status, JSON.stringify(viewport)).toBe(400);
    }
  });

  it('restaurar apaga as disposições de todas as telas', async () => {
    await route(req({ layout: disp, viewport: { width: 1920, height: 1080 } }));
    await route(req({ layout: disp, viewport: { width: 1512, height: 945 } }));

    const res = await route(req({ layout: null }));
    expect((await res.json()).layouts).toEqual([]);
  });
});

describe('visualização das tarefas', () => {
  it('grava a lista para o usuário logado', async () => {
    const res = await route(req({ tasksView: 'list' }));
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ tasksView: 'list' });

    const { tasksView } = await import('@/lib/preferences');
    expect(tasksView('u-1')).toBe('list');
    expect(tasksView('u-2')).toBe('board');
  });

  it('recusa uma visualização que a tela não oferece', async () => {
    const res = await route(req({ tasksView: 'calendario' }));
    expect(res.status).toBe(400);
    const { tasksView } = await import('@/lib/preferences');
    expect(tasksView('u-1')).toBe('board');
  });
});

describe('aparência', () => {
  it('grava só o que veio e devolve o que está guardado', async () => {
    const res = await route(req({ appearance: { width: 'limited' } }));
    expect(res.status).toBe(200);
    expect((await res.json()).appearance).toEqual({ width: 'limited' });

    const again = await route(req({ appearance: { theme: 'dark', density: 'compact' } }));
    expect((await again.json()).appearance).toEqual({
      theme: 'dark',
      density: 'compact',
      width: 'limited',
    });
  });

  it('guarda o padrão quando é escolhido, para valer mais que um cookie antigo', async () => {
    await route(req({ appearance: { theme: 'dark' } }));
    const res = await route(req({ appearance: { theme: 'system' } }));

    expect((await res.json()).appearance.theme).toBe('system');
  });

  it('é por usuário: o que um guarda não aparece para o outro', async () => {
    await route(req({ appearance: { width: 'limited' } }));
    currentUser.mockResolvedValue({ ...ME, id: 'u-2', username: 'maria' });

    const res = await route(req({ appearance: { theme: 'light' } }));
    expect((await res.json()).appearance).toEqual({ theme: 'light' });
  });

  it.each([
    ['um valor que não existe', { theme: 'sepia' }],
    ['uma chave que não existe', { fonte: 'grande' }],
    ['um valor de outro tipo', { width: true }],
    ['um objeto vazio', {}],
    ['algo que não é objeto', 'dark'],
    ['uma lista', ['dark']],
    ['um valor válido junto de um inválido', { theme: 'dark', width: 'enorme' }],
  ])('recusa %s', async (_nome, appearance) => {
    const res = await route(req({ appearance }));
    expect(res.status).toBe(400);
  });

  it('não grava nada quando um dos valores é inválido', async () => {
    await route(req({ appearance: { theme: 'dark', width: 'enorme' } }));
    const ok = await route(req({ appearance: { density: 'compact' } }));

    expect((await ok.json()).appearance).toEqual({ density: 'compact' });
  });
});
