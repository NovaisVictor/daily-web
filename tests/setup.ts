import '@testing-library/jest-dom/vitest';
import { mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';

// Sem isto, um teste que esqueça de apontar DAILY_WEB_DB_PATH escreve no banco
// de verdade — `resolveDbPath` cai em `./data/daily-web.db`, que é o do
// servidor rodando. Já aconteceu: um mock incompleto deixou a rota chamar o
// provedor real e duas tarefas de teste foram parar na conta do operador.
// Cada arquivo de teste ganha um banco descartável; quem precisa de controle
// sobrescreve a variável no próprio beforeEach.
process.env.DAILY_WEB_DB_PATH = path.join(
  mkdtempSync(path.join(tmpdir(), 'daily-web-test-')),
  'test.db',
);

// jsdom has no matchMedia, and the shell's Toaster reads it to follow the
// system theme. A query that never matches is the neutral answer; a test that
// cares about a width or a scheme installs its own, as DashboardGrid does.
if (typeof window !== 'undefined' && !window.matchMedia) {
  window.matchMedia = ((query: string) => ({
    matches: false,
    media: query,
    onchange: null,
    addListener: () => {},
    removeListener: () => {},
    addEventListener: () => {},
    removeEventListener: () => {},
    dispatchEvent: () => false,
  })) as unknown as typeof window.matchMedia;
}
