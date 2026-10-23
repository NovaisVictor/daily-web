import { describe, expect, it } from 'vitest';
import {
  columnOf,
  groupByColumn,
  neighbours,
  noteTilt,
  noteTone,
  planMove,
} from '@/lib/taskBoard';
import type { TodoTask } from '@/lib/types';

function task(over: Partial<TodoTask>): TodoTask {
  return {
    id: 'x', title: 't', completed: false, due: '', priority: 'normal', time: '', recur: '',
    notes: '', subtasks: [], doing: false, ...over,
  };
}

describe('coluna de cada tarefa', () => {
  it('aberta e sem marcação fica em A fazer', () => {
    expect(columnOf(task({}))).toBe('todo');
  });

  it('marcada como fazendo fica em Fazendo', () => {
    expect(columnOf(task({ doing: true }))).toBe('doing');
  });

  // A marcação pode sobrar de uma conclusão feita no celular, fora da app.
  it('concluída fica em Feito mesmo com a marcação de fazendo', () => {
    expect(columnOf(task({ completed: true, doing: true }))).toBe('done');
  });

  it('agrupa mantendo a ordem em que as tarefas chegaram', () => {
    const columns = groupByColumn([
      task({ id: 'a' }),
      task({ id: 'b', doing: true }),
      task({ id: 'c', completed: true }),
      task({ id: 'd' }),
    ]);
    expect(columns.todo.map((t) => t.id)).toEqual(['a', 'd']);
    expect(columns.doing.map((t) => t.id)).toEqual(['b']);
    expect(columns.done.map((t) => t.id)).toEqual(['c']);
  });

  it('cada coluna conhece as vizinhas, e as pontas só têm uma', () => {
    expect(neighbours('todo')).toEqual({ previous: null, next: 'doing' });
    expect(neighbours('doing')).toEqual({ previous: 'todo', next: 'done' });
    expect(neighbours('done')).toEqual({ previous: 'doing', next: null });
  });
});

describe('o que mover pede ao servidor', () => {
  it('mover para Feito conclui a tarefa, sem gravar status', () => {
    expect(planMove(task({ doing: true }), 'done')).toEqual([{ kind: 'complete', completed: true }]);
  });

  it('entre A fazer e Fazendo só grava o status', () => {
    expect(planMove(task({}), 'doing')).toEqual([{ kind: 'status', status: 'doing' }]);
    expect(planMove(task({ doing: true }), 'todo')).toEqual([{ kind: 'status', status: 'todo' }]);
  });

  it('sair de Feito reabre a tarefa antes de gravar a coluna nova', () => {
    expect(planMove(task({ completed: true }), 'doing')).toEqual([
      { kind: 'complete', completed: false },
      { kind: 'status', status: 'doing' },
    ]);
  });

  it('soltar na mesma coluna não pede nada', () => {
    expect(planMove(task({ doing: true }), 'doing')).toEqual([]);
  });
});

describe('aparência da nota', () => {
  it('a inclinação é a mesma a cada desenho e fica entre -2 e 2 graus', () => {
    const ids = ['a', 'b', 'AQMk+ADAw/abc==', '4f0c2a9e-1', 'tarefa-muito-longa'.repeat(5)];
    for (const id of ids) {
      expect(noteTilt(id)).toBe(noteTilt(id));
      expect(noteTilt(id)).toBeGreaterThanOrEqual(-2);
      expect(noteTilt(id)).toBeLessThanOrEqual(2);
    }
  });

  it('tarefas diferentes não ficam todas com a mesma inclinação', () => {
    const tilts = new Set(['1', '2', '3', '4', '5', '6'].map(noteTilt));
    expect(tilts.size).toBeGreaterThan(1);
  });

  it('a cor segue a prioridade e a concluída fica verde', () => {
    expect(noteTone(task({}))).toBe('yellow');
    expect(noteTone(task({ priority: 'high' }))).toBe('pink');
    expect(noteTone(task({ priority: 'low' }))).toBe('blue');
    expect(noteTone(task({ priority: 'high', completed: true }))).toBe('green');
  });
});
