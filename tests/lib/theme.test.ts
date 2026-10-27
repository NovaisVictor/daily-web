import { afterEach, describe, expect, it } from 'vitest';
import {
  BACKDROP_COOKIE,
  WIDTH_COOKIE,
  applyBackdrop,
  applyContentWidth,
  parseAppearancePatch,
  parseBackdrop,
  parseContentWidth,
} from '@/lib/theme';

afterEach(() => {
  delete document.documentElement.dataset.backdrop;
  document.cookie = `${BACKDROP_COOKIE}=; path=/; max-age=0`;
  delete document.documentElement.dataset.width;
  document.cookie = `${WIDTH_COOKIE}=; path=/; max-age=0`;
});

describe('parseBackdrop', () => {
  it('reconhece o Catppuccin', () => {
    expect(parseBackdrop('catppuccin')).toBe('catppuccin');
  });

  it('reconhece o Dracula', () => {
    expect(parseBackdrop('dracula')).toBe('dracula');
  });

  // Cookie ausente, apagado ou escrito à mão cai no gradiente, que é o padrão.
  it('cai no gradiente para qualquer outro valor', () => {
    for (const valor of [undefined, '', 'mesh', 'Catppuccin', 'Dracula', 'lixo']) {
      expect(parseBackdrop(valor), String(valor)).toBe('mesh');
    }
  });
});

describe('applyBackdrop', () => {
  it('marca o elemento raiz e grava o cookie ao escolher o Catppuccin', () => {
    applyBackdrop('catppuccin');

    expect(document.documentElement.dataset.backdrop).toBe('catppuccin');
    expect(document.cookie).toContain(`${BACKDROP_COOKIE}=catppuccin`);
  });

  it('marca o elemento raiz e grava o cookie ao escolher o Dracula', () => {
    applyBackdrop('dracula');

    expect(document.documentElement.dataset.backdrop).toBe('dracula');
    expect(document.cookie).toContain(`${BACKDROP_COOKIE}=dracula`);
  });

  it('troca do Catppuccin para o Dracula sem deixar as duas marcas', () => {
    applyBackdrop('catppuccin');
    applyBackdrop('dracula');

    expect(document.documentElement.dataset.backdrop).toBe('dracula');
    expect(document.cookie).not.toContain(`${BACKDROP_COOKIE}=catppuccin`);
  });

  it('volta ao gradiente tirando a marca e o cookie', () => {
    applyBackdrop('catppuccin');
    applyBackdrop('mesh');

    expect(document.documentElement.dataset.backdrop).toBeUndefined();
    expect(document.cookie).not.toContain(`${BACKDROP_COOKIE}=`);
  });
});

describe('parseContentWidth', () => {
  it('é a largura toda quando não há cookie: é o padrão', () => {
    expect(parseContentWidth(undefined)).toBe('full');
  });

  it('reconhece a largura limitada', () => {
    expect(parseContentWidth('limited')).toBe('limited');
  });

  it('cai na largura toda para qualquer outro valor', () => {
    expect(parseContentWidth('1216')).toBe('full');
    expect(parseContentWidth('')).toBe('full');
  });
});

describe('applyContentWidth', () => {
  it('marca o elemento raiz e grava o cookie ao limitar', () => {
    applyContentWidth('limited');

    expect(document.documentElement.dataset.width).toBe('limited');
    expect(document.cookie).toContain(`${WIDTH_COOKIE}=limited`);
  });

  it('volta à largura toda tirando a marca e o cookie', () => {
    applyContentWidth('limited');
    applyContentWidth('full');

    expect(document.documentElement.dataset.width).toBeUndefined();
    expect(document.cookie).not.toContain(WIDTH_COOKIE);
  });
});

describe('parseAppearancePatch', () => {
  it('aceita um ou vários campos conhecidos', () => {
    expect(parseAppearancePatch({ width: 'limited' })).toEqual({ width: 'limited' });
    expect(
      parseAppearancePatch({ theme: 'dark', density: 'compact', backdrop: 'dracula', width: 'full' }),
    ).toEqual({ theme: 'dark', density: 'compact', backdrop: 'dracula', width: 'full' });
  });

  it('recusa qualquer valor ou chave desconhecidos, em vez de cair num padrão', () => {
    expect(parseAppearancePatch({ theme: 'sepia' })).toBeNull();
    expect(parseAppearancePatch({ fonte: 'grande' })).toBeNull();
    expect(parseAppearancePatch({ theme: 'dark', width: 'enorme' })).toBeNull();
  });

  it('recusa o que não é um objeto com ao menos um campo', () => {
    for (const raw of [null, undefined, 'dark', 3, [], {}]) {
      expect(parseAppearancePatch(raw)).toBeNull();
    }
  });
});
