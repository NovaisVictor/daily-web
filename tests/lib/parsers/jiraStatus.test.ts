import { describe, expect, it } from 'vitest';
import {
  daysSince,
  dueLabel,
  groupByStatusCategory,
  isOverdue,
  normalizeStatus,
  stalenessLabel,
  STALE_AFTER_DAYS,
} from '@/lib/parsers/jira';
import type { JiraItem } from '@/lib/types';

const AGORA = new Date(2026, 7, 26, 15, 0, 0); // 26/08/2026, hora local

function issue(over: Partial<JiraItem>): JiraItem {
  return {
    key: 'TT-1',
    summary: 'Uma issue',
    status: 'Em andamento',
    statusCategory: 'indeterminate',
    project: 'TT',
    url: 'https://x/TT-1',
    parent: null,
    role: 'assignee',
    awaitingApproval: false,
    kind: 'História',
    subtask: false,
    hierarchyLevel: null,
    impediment: 'none',
    updatedAt: '2026-08-26T10:00:00.000-0300',
    dueDate: '',
    ...over,
  };
}

describe('normalizeStatus', () => {
  // Este Jira tem "Em andamento" e "Em Andamento" como status distintos, e a
  // lista os contava como dois estados diferentes.
  it('junta o mesmo status escrito com caixas diferentes', () => {
    expect(normalizeStatus('Em andamento')).toBe(normalizeStatus('Em Andamento'));
    expect(normalizeStatus('EM ANDAMENTO')).toBe('Em andamento');
  });

  it('preserva acento e devolve vazio para vazio', () => {
    expect(normalizeStatus('concluído')).toBe('Concluído');
    expect(normalizeStatus('   ')).toBe('');
  });
});

// Datas construídas a partir de AGORA, para o teste não depender do fuso da
// máquina que roda a suíte — o servidor está em UTC e o Jira devolve -0300.
function diasAtras(dias: number): string {
  return new Date(AGORA.getTime() - dias * 86_400_000).toISOString();
}

describe('daysSince', () => {
  it('conta os dias inteiros desde a data', () => {
    expect(daysSince(diasAtras(6), AGORA)).toBe(6);
    expect(daysSince(diasAtras(0), AGORA)).toBe(0);
  });

  it('devolve null para data inválida ou ausente', () => {
    expect(daysSince('', AGORA)).toBeNull();
    expect(daysSince('não é data', AGORA)).toBeNull();
  });
});

describe('stalenessLabel', () => {
  // Quase tudo é mexido a cada dois dias; marcar todos apagaria o sinal.
  it('cala sobre o que é recente', () => {
    expect(stalenessLabel(issue({ updatedAt: diasAtras(1) }), AGORA)).toBeNull();
    expect(stalenessLabel(issue({ updatedAt: diasAtras(4) }), AGORA)).toBeNull();
  });

  it('avisa a partir do limite', () => {
    expect(stalenessLabel(issue({ updatedAt: diasAtras(STALE_AFTER_DAYS) }), AGORA)).toBe(
      `parado há ${STALE_AFTER_DAYS}d`,
    );
  });

  it('destaca o esquecido de verdade', () => {
    expect(stalenessLabel(issue({ updatedAt: diasAtras(14) }), AGORA)).toBe('parado há 14d');
  });

  it('cala quando não há data de atualização', () => {
    expect(stalenessLabel(issue({ updatedAt: '' }), AGORA)).toBeNull();
  });
});

describe('dueLabel', () => {
  it('usa a forma relativa na semana à frente', () => {
    expect(dueLabel('2026-08-26', AGORA)).toBe('vence hoje');
    expect(dueLabel('2026-08-27', AGORA)).toBe('vence amanhã');
    expect(dueLabel('2026-08-29', AGORA)).toBe('vence em 3d');
    expect(dueLabel('2026-09-02', AGORA)).toBe('vence em 7d');
  });

  it('mostra a data quando está longe', () => {
    expect(dueLabel('2026-09-30', AGORA)).toBe('vence 30/09');
  });

  it('conta os dias de atraso', () => {
    expect(dueLabel('2026-08-24', AGORA)).toBe('venceu há 2d');
  });

  it('devolve null quando não há prazo', () => {
    expect(dueLabel('', AGORA)).toBeNull();
    expect(dueLabel('qualquer coisa', AGORA)).toBeNull();
  });

  // A comparação é por dia local: às 15h de hoje, algo que vence hoje ainda
  // não está atrasado.
  it('não trata o vencimento de hoje como atraso', () => {
    expect(isOverdue('2026-08-26', AGORA)).toBe(false);
    expect(isOverdue('2026-08-25', AGORA)).toBe(true);
    expect(isOverdue('', AGORA)).toBe(false);
  });
});

describe('groupByStatusCategory', () => {
  it('põe o que já começou antes do que não começou', () => {
    const grupos = groupByStatusCategory([
      issue({ key: 'A', statusCategory: 'new' }),
      issue({ key: 'B', statusCategory: 'indeterminate' }),
    ]);
    expect(grupos.map((g) => g.label)).toEqual(['Em andamento', 'Pendentes']);
    expect(grupos[0].issues.map((i) => i.key)).toEqual(['B']);
  });

  it('não cria grupo vazio', () => {
    const grupos = groupByStatusCategory([issue({ statusCategory: 'indeterminate' })]);
    expect(grupos).toHaveLength(1);
  });

  it('devolve vazio para lista vazia', () => {
    expect(groupByStatusCategory([])).toEqual([]);
  });
});
