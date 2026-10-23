import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { parseTasks } from '@/lib/parsers/mstodo';

const fixture = readFileSync(path.join(__dirname, '../../fixtures/mstodo-tasks.json'), 'utf8');

describe('parseTasks', () => {
  it('normalizes only the known Microsoft monthly recurrence', () => {
    const tasks = parseTasks(JSON.stringify(['absoluteMonthly', 'monthly', 'future-pattern'].map(recur => ({id: recur, title: 'Task', completed: false, recur}))));
    expect(tasks.map(task => task.recur)).toEqual(['monthly', 'monthly', 'future-pattern']);
  });

  it('faz o parse dos campos básicos', () => {
    const raw = '[{"id":"a1","title":"Comprar café","completed":false,"due":"2026-06-10","notes":""},' +
      '{"id":"b2","title":"Feito","completed":true,"due":"","notes":"obs"}]';
    const tasks = parseTasks(raw);
    expect(tasks).toHaveLength(2);
    expect(tasks[0].title).toBe('Comprar café');
    expect(tasks[0].due).toBe('2026-06-10');
    expect(tasks[1].completed).toBe(true);
    expect(tasks[1].notes).toBe('obs');
  });

  it('faz o parse das subtarefas mantendo o estado', () => {
    const tasks = parseTasks(fixture);
    expect(tasks[0].subtasks).toHaveLength(2);
    expect(tasks[0].subtasks[0]).toEqual({ id: 'S1', title: 'Medir a fiação', completed: true });
    expect(tasks[1].subtasks).toEqual([]);
  });

  it('campo subtasks ausente vira lista vazia', () => {
    const tasks = parseTasks('[{"id":"a","title":"t","completed":false}]');
    expect(tasks[0].subtasks).toEqual([]);
  });

  it('prioridade ausente ou inválida vira "normal"', () => {
    const tasks = parseTasks('[{"id":"a","title":"t","completed":false,"priority":"esquisita"}]');
    expect(tasks[0].priority).toBe('normal');
  });

  it('prioridade válida é preservada', () => {
    const tasks = parseTasks(fixture);
    expect(tasks[0].priority).toBe('high');
  });
});
