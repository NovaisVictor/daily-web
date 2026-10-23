import { describe, expect, it } from 'vitest';
import { groupTasksByDueWindow, isOverdue } from '@/lib/taskGrouping';
import type { TodoTask } from '@/lib/types';

const today = new Date('2026-08-25T12:00:00Z');

function task(over: Partial<TodoTask>): TodoTask {
  return {
    id: over.id ?? 'x', title: over.title ?? 't', completed: over.completed ?? false,
    due: over.due ?? '', priority: over.priority ?? 'normal', time: '', recur: '', notes: '',
    subtasks: [],
    doing: false,
    paper: null,
    pin: null,
  };
}

describe('groupTasksByDueWindow', () => {
  it('separa em atrasada/hoje/semana/mês/depois/sem data, nessa ordem', () => {
    const tasks = [
      task({ id: 'a', due: '2026-08-20' }),
      task({ id: 'b', due: '2026-08-25' }),
      task({ id: 'c', due: '2026-08-28' }),
      task({ id: 'd', due: '2026-09-15' }),
      task({ id: 'e', due: '2026-12-01' }),
      task({ id: 'f', due: '' }),
    ];
    const groups = groupTasksByDueWindow(tasks, today);
    expect(groups.map((g) => g.key)).toEqual(['overdue', 'today', 'week', 'month', 'later', 'noDate']);
  });

  it('omite faixas vazias', () => {
    const groups = groupTasksByDueWindow([task({ due: '2026-08-25' })], today);
    expect(groups).toHaveLength(1);
    expect(groups[0].key).toBe('today');
    expect(groups[0].label).toBe('HOJE');
  });

  it('ordena por vencimento, depois prioridade, concluídas no fim', () => {
    const tasks = [
      task({ id: 'low', due: '2026-08-25', priority: 'low' }),
      task({ id: 'high', due: '2026-08-25', priority: 'high' }),
      task({ id: 'done', due: '2026-08-25', priority: 'high', completed: true }),
    ];
    const groups = groupTasksByDueWindow(tasks, today);
    expect(groups[0].tasks.map((t) => t.id)).toEqual(['high', 'low', 'done']);
  });

  it('tarefa sem data cai em SEM DATA independente de estar completada', () => {
    const groups = groupTasksByDueWindow([task({ due: '', completed: true })], today);
    expect(groups[0].key).toBe('noDate');
  });

  it('classifica corretamente mesmo tarde da noite em fuso horário negativo (ex.: Brasil, UTC-3)', () => {
    // getFullYear/getMonth/getDate resolvem contra o fuso horário LOCAL do processo, não o
    // offset embutido na string ISO abaixo — então, para reproduzir de forma determinística
    // "22h em São Paulo" independente do TZ da máquina que roda o teste (aqui, UTC), fixamos
    // o TZ do processo para a janela do teste e restauramos em seguida.
    const originalTz = process.env.TZ;
    process.env.TZ = 'America/Sao_Paulo';
    try {
      const today = new Date('2026-08-25T22:00:00-03:00'); // 22h em São Paulo, ainda dia 25 local
      const tasks = [
        task({ id: '1', title: 'Tarefa de hoje', due: '2026-08-25' }),
      ];
      const groups = groupTasksByDueWindow(tasks, today);
      const todayGroup = groups.find((g) => g.key === 'today');
      expect(todayGroup?.tasks.map((t) => t.id)).toEqual(['1']);
      expect(groups.find((g) => g.key === 'overdue')).toBeUndefined();
    } finally {
      process.env.TZ = originalTz;
    }
  });
});

describe('isOverdue', () => {
  const now = new Date(2026, 9, 23, 10, 0);

  it('uma tarefa aberta com data passada está atrasada', () => {
    expect(isOverdue(task({ due: '2026-10-22' }), now)).toBe(true);
  });

  it('vencer hoje ainda não é atraso', () => {
    expect(isOverdue(task({ due: '2026-10-23' }), now)).toBe(false);
  });

  it('concluída ou sem data nunca está atrasada', () => {
    expect(isOverdue(task({ due: '2026-10-01', completed: true }), now)).toBe(false);
    expect(isOverdue(task({}), now)).toBe(false);
  });
});
