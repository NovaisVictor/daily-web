import { describe, expect, it } from 'vitest';
import {
  CLASHES,
  NOTE_PAPERS,
  PIN_COLORS,
  columnOf,
  derivedPaper,
  groupByColumn,
  neighbours,
  noteCurls,
  notePaper,
  notePin,
  noteTilt,
  planMove,
} from '@/lib/taskBoard';
import type { TodoTask } from '@/lib/types';

function task(over: Partial<TodoTask>): TodoTask {
  return {
    id: 'x', title: 't', completed: false, due: '', priority: 'normal', time: '', recur: '',
    notes: '', subtasks: [], doing: false, paper: null, pin: null, ...over,
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
    expect(notePaper(task({}))).toBe('yellow');
    expect(notePaper(task({ priority: 'high' }))).toBe('pink');
    expect(notePaper(task({ priority: 'low' }))).toBe('blue');
    expect(notePaper(task({ priority: 'high', completed: true }))).toBe('green');
  });

  it('o alfinete nunca tem a cor que o papel esconderia', () => {
    const ids = Array.from({ length: 40 }, (_, i) => `t-${i}`);
    for (const id of ids) {
      expect(notePin(task({ id }))).not.toBe('yellow');
      expect(notePin(task({ id, priority: 'high' }))).not.toBe('red');
      expect(notePin(task({ id, priority: 'low' }))).not.toBe('blue');
      expect(notePin(task({ id, completed: true }))).not.toBe('green');
    }
  });

  it('o alfinete e o canto são os mesmos a cada desenho e variam pelo quadro', () => {
    const ids = Array.from({ length: 40 }, (_, i) => `t-${i}`);
    for (const id of ids) {
      expect(notePin(task({ id }))).toBe(notePin(task({ id })));
      expect(noteCurls(id)).toBe(noteCurls(id));
    }
    expect(new Set(ids.map((id) => notePin(task({ id })))).size).toBeGreaterThan(1);
    const curled = ids.filter(noteCurls).length;
    expect(curled).toBeGreaterThan(0);
    expect(curled).toBeLessThan(ids.length);
  });
});

describe('cores escolhidas para a nota', () => {
  const ids = Array.from({ length: 40 }, (_, i) => `t-${i}`);

  it('o papel escolhido vale mais que a prioridade', () => {
    expect(notePaper(task({ priority: 'high', paper: 'grey' }))).toBe('grey');
    expect(derivedPaper(task({ priority: 'high', paper: 'grey' }))).toBe('pink');
  });

  // A coluna Feito e o tachado já dizem que acabou; forçar verde apagaria a
  // cor justo onde as notas se acumulam.
  it('o papel escolhido vale mais que o verde da concluída', () => {
    expect(notePaper(task({ completed: true, paper: 'white' }))).toBe('white');
  });

  it('o alfinete automático foge do papel escolhido, não do da prioridade', () => {
    for (const id of ids) {
      // Prioridade normal daria papel amarelo; o papel rosa escolhido é o que
      // está na tela, então é o vermelho que precisa sumir das opções.
      expect(notePin(task({ id, paper: 'pink' }))).not.toBe('red');
      expect(notePin(task({ id, paper: 'white' }))).not.toBe('yellow');
      expect(notePin(task({ id, paper: 'grey' }))).not.toBe('yellow');
    }
    // E o amarelo, proibido no papel amarelo da prioridade normal, volta a
    // ser opção no papel azul escolhido.
    expect(new Set(ids.map((id) => notePin(task({ id, paper: 'blue' }))))).toContain('yellow');
  });

  it('o alfinete escolhido é respeitado, mesmo quando some no papel', () => {
    expect(notePin(task({ pin: 'yellow' }))).toBe('yellow');
    expect(notePin(task({ paper: 'pink', pin: 'red' }))).toBe('red');
  });

  it('a tabela de conflitos cobre todo papel e deixa sempre alfinete disponível', () => {
    expect(CLASHES).toEqual({
      yellow: ['yellow'],
      pink: ['red'],
      blue: ['blue'],
      green: ['green'],
      white: ['yellow'],
      grey: ['yellow'],
    });
    for (const paper of NOTE_PAPERS) {
      expect(PIN_COLORS.filter((c) => !CLASHES[paper].includes(c)).length).toBeGreaterThan(0);
      for (const id of ids) expect(CLASHES[paper]).not.toContain(notePin(task({ id, paper })));
    }
  });
});
