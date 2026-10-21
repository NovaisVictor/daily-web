import { describe, expect, it } from 'vitest';
import { compareJira, parseJiraOrder, sortJira, sortJiraTree } from '@/lib/jiraOrder';
import { buildJiraTree } from '@/lib/parsers/jira';
import type { JiraItem } from '@/lib/types';

const issue = (key: string, over: Partial<JiraItem> = {}): JiraItem => ({
  key,
  summary: key,
  status: 'Em andamento',
  statusCategory: 'indeterminate',
  project: key.split('-')[0],
  url: `https://acme.atlassian.net/browse/${key}`,
  parent: null,
  role: 'assignee',
  awaitingApproval: false,
  kind: 'História',
  subtask: false,
  hierarchyLevel: 0,
  updatedAt: '2026-10-10T10:00:00Z',
  dueDate: '',
  priority: null,
  flag: 'none',
  ...over,
});

const keys = (items: JiraItem[]) => items.map((i) => i.key);

describe('parseJiraOrder', () => {
  it('cai na ordem padrão com valor ausente ou desconhecido', () => {
    expect(parseJiraOrder(null)).toBe('atualizacao');
    expect(parseJiraOrder('toString')).toBe('atualizacao');
    expect(parseJiraOrder('lixo')).toBe('atualizacao');
    expect(parseJiraOrder('prioridade')).toBe('prioridade');
  });
});

describe('sortJira', () => {
  const a = issue('A-1', { updatedAt: '2026-10-01T10:00:00Z', dueDate: '2026-10-30', priority: { name: 'Baixa', rank: 3 } });
  const b = issue('A-2', { updatedAt: '2026-10-15T10:00:00Z', dueDate: '', priority: { name: 'Crítica', rank: 0 } });
  const c = issue('A-3', { updatedAt: '2026-10-10T10:00:00Z', dueDate: '2026-10-21', priority: null });

  it('na ordem padrão devolve a lista como veio do Jira', () => {
    const lista = [a, b, c];
    expect(sortJira(lista, 'atualizacao')).toBe(lista);
  });

  it('por prazo, o que vence antes primeiro e sem prazo por último', () => {
    expect(keys(sortJira([a, b, c], 'prazo'))).toEqual(['A-3', 'A-1', 'A-2']);
  });

  it('por prioridade, a mais alta primeiro e sem prioridade por último', () => {
    expect(keys(sortJira([a, b, c], 'prioridade'))).toEqual(['A-2', 'A-1', 'A-3']);
  });

  it('parado há mais tempo é a alteração mais antiga primeiro', () => {
    expect(keys(sortJira([a, b, c], 'parado'))).toEqual(['A-1', 'A-3', 'A-2']);
  });

  it('empata pela alteração mais recente', () => {
    const x = issue('A-4', { updatedAt: '2026-10-01T10:00:00Z', priority: { name: 'Alta', rank: 1 } });
    const y = issue('A-5', { updatedAt: '2026-10-09T10:00:00Z', priority: { name: 'Alta', rank: 1 } });
    expect(keys(sortJira([x, y], 'prioridade'))).toEqual(['A-5', 'A-4']);
  });

  it('não muda a lista recebida', () => {
    const lista = [a, b, c];
    sortJira(lista, 'prazo');
    expect(keys(lista)).toEqual(['A-1', 'A-2', 'A-3']);
  });

  it('data inválida conta como ausente', () => {
    const ruim = issue('A-9', { dueDate: 'sem data' });
    expect(compareJira('prazo')(ruim, c)).toBeGreaterThan(0);
  });
});

describe('sortJiraTree', () => {
  // O épico é caminho; quem decide a posição dele é a história mais urgente.
  it('sobe o ramo cuja história tem a prioridade mais alta', () => {
    const epicoA = issue('A-10', { kind: 'Epic', hierarchyLevel: 1 });
    const epicoB = issue('A-20', { kind: 'Epic', hierarchyLevel: 1 });
    const baixa = issue('A-11', { parent: { key: 'A-10', summary: '' }, priority: { name: 'Baixa', rank: 3 } });
    const critica = issue('A-21', { parent: { key: 'A-20', summary: '' }, priority: { name: 'Crítica', rank: 0 } });

    const tree = buildJiraTree([baixa, critica], [epicoA, epicoB]);
    expect(tree[0].roots.map((r) => r.issue.key)).toEqual(['A-10', 'A-20']);

    const sorted = sortJiraTree(tree, 'prioridade');
    expect(sorted[0].roots.map((r) => r.issue.key)).toEqual(['A-20', 'A-10']);
    expect(sorted[0].count).toBe(2);
  });

  it('ordena as filhas dentro do ramo', () => {
    const epico = issue('A-10', { kind: 'Epic', hierarchyLevel: 1 });
    const tarde = issue('A-11', { parent: { key: 'A-10', summary: '' }, dueDate: '2026-12-01' });
    const cedo = issue('A-12', { parent: { key: 'A-10', summary: '' }, dueDate: '2026-10-25' });

    const [group] = sortJiraTree(buildJiraTree([tarde, cedo], [epico]), 'prazo');
    expect(group.roots[0].children.map((c) => c.issue.key)).toEqual(['A-12', 'A-11']);
  });
});
