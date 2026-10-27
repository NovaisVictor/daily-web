import { afterEach, describe, expect, it } from 'vitest';
import { BACKDROP_COOKIE, applyBackdrop, parseBackdrop } from '@/lib/theme';

afterEach(() => {
  delete document.documentElement.dataset.backdrop;
  document.cookie = `${BACKDROP_COOKIE}=; path=/; max-age=0`;
});

describe('parseBackdrop', () => {
  it('reconhece o Catppuccin', () => {
    expect(parseBackdrop('catppuccin')).toBe('catppuccin');
  });

  it('reconhece o Dracula', () => {
    expect(parseBackdrop('dracula')).toBe('dracula');
  });

  it('reconhece o WezTerm', () => {
    expect(parseBackdrop('wezterm')).toBe('wezterm');
  });

  // Cookie ausente, apagado ou escrito à mão cai no gradiente, que é o padrão.
  it('cai no gradiente para qualquer outro valor', () => {
    for (const valor of [undefined, '', 'mesh', 'Catppuccin', 'Dracula', 'WezTerm', 'lixo']) {
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

  it('marca o elemento raiz e grava o cookie ao escolher o WezTerm', () => {
    applyBackdrop('wezterm');

    expect(document.documentElement.dataset.backdrop).toBe('wezterm');
    expect(document.cookie).toContain(`${BACKDROP_COOKIE}=wezterm`);
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
