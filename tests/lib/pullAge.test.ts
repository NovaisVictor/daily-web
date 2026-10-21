import { describe, expect, it } from 'vitest';
import { pullAge } from '@/lib/pullAge';

const NOW = new Date('2026-10-21T12:00:00Z');

describe('pullAge', () => {
  it('conta os dias desde a abertura', () => {
    expect(pullAge({ createdAt: '2026-10-12T12:00:00Z', updatedAt: '2026-10-21T10:00:00Z' }, NOW)?.opened).toBe(
      'aberto há 9 dias',
    );
  });

  it('usa o singular para um dia', () => {
    expect(pullAge({ createdAt: '2026-10-20T11:00:00Z', updatedAt: '2026-10-21T10:00:00Z' }, NOW)?.opened).toBe(
      'aberto há 1 dia',
    );
  });

  it('diz hoje para o que abriu há menos de um dia', () => {
    expect(pullAge({ createdAt: '2026-10-21T01:00:00Z', updatedAt: '2026-10-21T01:00:00Z' }, NOW)?.opened).toBe(
      'aberto hoje',
    );
  });

  it('marca como parado o que não muda há mais de três dias', () => {
    expect(pullAge({ createdAt: '2026-10-01T12:00:00Z', updatedAt: '2026-10-17T11:00:00Z' }, NOW)?.stalled).toBe(
      'parado há 4 dias',
    );
  });

  it('não marca como parado o que mudou há exatamente três dias', () => {
    expect(pullAge({ createdAt: '2026-10-01T12:00:00Z', updatedAt: '2026-10-18T12:00:00Z' }, NOW)?.stalled).toBeNull();
  });

  it('não inventa idade sem data de abertura', () => {
    expect(pullAge({ createdAt: '', updatedAt: '2026-10-18T12:00:00Z' }, NOW)).toBeNull();
  });

  it('não inventa idade com data inválida', () => {
    expect(pullAge({ createdAt: 'ontem', updatedAt: '2026-10-18T12:00:00Z' }, NOW)).toBeNull();
  });
});
