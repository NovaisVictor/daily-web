import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';

let dir: string;
const USER = 'user-1';

beforeEach(async () => {
  dir = mkdtempSync(path.join(tmpdir(), 'daily-web-appearance-'));
  process.env.DAILY_WEB_DB_PATH = path.join(dir, 'test.db');
  const { getDb } = await import('@/lib/db');
  getDb();
});

afterEach(() => {
  rmSync(dir, { recursive: true, force: true });
});

const cookies = (values: Record<string, string>) => (name: string) => values[name];

describe('resolveAppearance', () => {
  it('sem ninguém logado, vale o cookie do navegador', async () => {
    const { resolveAppearance } = await import('@/lib/appearance');

    expect(resolveAppearance(cookies({ theme: 'dark', width: 'limited' }), null)).toEqual({
      theme: 'dark',
      density: 'comfortable',
      backdrop: 'mesh',
      width: 'limited',
    });
  });

  it('sem cookie nem conta, são os padrões: largura toda inclusive', async () => {
    const { resolveAppearance } = await import('@/lib/appearance');

    expect(resolveAppearance(cookies({}), USER)).toEqual({
      theme: 'system',
      density: 'comfortable',
      backdrop: 'mesh',
      width: 'full',
    });
  });

  // É o que faz a escolha acompanhar a pessoa para outro navegador.
  it('o que a conta guardou vale mais que o cookie do navegador', async () => {
    const { resolveAppearance } = await import('@/lib/appearance');
    const { setAppearance } = await import('@/lib/preferences');
    setAppearance(USER, { theme: 'light', width: 'limited' });

    expect(resolveAppearance(cookies({ theme: 'dark', width: 'full' }), USER)).toMatchObject({
      theme: 'light',
      width: 'limited',
    });
  });

  it('o que a conta nunca guardou cai no cookie, campo a campo', async () => {
    const { resolveAppearance } = await import('@/lib/appearance');
    const { setAppearance } = await import('@/lib/preferences');
    setAppearance(USER, { width: 'limited' });

    expect(resolveAppearance(cookies({ theme: 'dark', density: 'compact' }), USER)).toEqual({
      theme: 'dark',
      density: 'compact',
      backdrop: 'mesh',
      width: 'limited',
    });
  });

  it('a escolha de outra pessoa não vaza', async () => {
    const { resolveAppearance } = await import('@/lib/appearance');
    const { setAppearance } = await import('@/lib/preferences');
    setAppearance('user-2', { theme: 'dark', width: 'limited' });

    expect(resolveAppearance(cookies({}), USER).width).toBe('full');
  });
});
