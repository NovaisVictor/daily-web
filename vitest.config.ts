import { defineConfig, configDefaults } from 'vitest/config';
import react from '@vitejs/plugin-react';
import path from 'node:path';

export default defineConfig({
  plugins: [react()],
  test: {
    environment: 'jsdom',
    setupFiles: ['./tests/setup.ts'],
    globals: false,
    // The deploy runs the suite on the production host, which shares its CPU
    // with other jobs. Component tests that drive menus in jsdom take ~3 s on
    // their own and passed the 5 s default under that load, failing the deploy
    // without any change in behaviour.
    testTimeout: 15_000,
    exclude: [...configDefaults.exclude, '**/.claude/**', '**/.worktrees/**'],
  },
  resolve: {
    alias: {
      '@': path.resolve(__dirname, '.'),
    },
  },
});
