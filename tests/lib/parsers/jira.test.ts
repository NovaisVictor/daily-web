import { describe, expect, it } from 'vitest';
import { typeMarker, issueMarker, groupByParent, buildJiraTree } from '@/lib/parsers/jira';
import type { JiraItem } from '@/lib/types';

// Estes testes montavam JiraItem a partir de um JSON de fixture, que era a
// saída da CLI `jira`. A CLI saiu do caminho: o cliente REST monta o item em
// `toJiraItem`, testado em jiraApi. Aqui interessa só a lógica de árvore e de
// marcador, então o item é construído direto.
function issue(over: Partial<JiraItem>): JiraItem {
  return {
    key: 'ENG-1',
    summary: 'Uma issue',
    status: 'Em andamento',
    statusCategory: 'indeterminate',
    project: 'ENG',
    url: 'https://x/ENG-1',
    parent: null,
    role: 'assignee',
    awaitingApproval: false,
    kind: 'História',
    subtask: false,
    hierarchyLevel: null,
    impediment: 'none',
    updatedAt: '2026-08-26T10:00:00.000Z',
    dueDate: '',
    ...over,
  };
}

const real: JiraItem[] = [
  issue({
    key: 'ENG-101',
    project: 'ENG',
    parent: { key: 'ENG-1', summary: 'Iniciativa de Engenharia' },
  }),
  issue({ key: 'OPS-55', project: 'OPS' }),
  issue({ key: 'OPS-56', project: 'OPS' }),
];

describe('typeMarker', () => {
  it('reconhece o tipo nos dois idiomas', () => {
    expect(typeMarker('História')).toBe('[S]');
    expect(typeMarker('Story')).toBe('[S]');
    expect(typeMarker('Epic')).toBe('[E]');
    expect(typeMarker('Épico')).toBe('[E]');
    expect(typeMarker('Iniciativa')).toBe('[I]');
    expect(typeMarker('Objetivo')).toBe('[O]');
  });

  it('reconhece requisição de serviço em várias formas', () => {
    expect(typeMarker('[System] Service request')).toBe('[R]');
    expect(typeMarker('Requisição')).toBe('[R]');
  });

  it('devolve [?] para tipo desconhecido', () => {
    expect(typeMarker('Subtarefa')).toBe('[?]');
    expect(typeMarker('')).toBe('[?]');
  });
});

describe('issueMarker', () => {
  it('usa [s] para subtarefa mesmo quando o nome do tipo não é reconhecido', () => {
    const subtask = issue({ key: 'ENG-9', kind: 'Subtarefa', subtask: true });
    expect(typeMarker(subtask.kind)).toBe('[?]');
    expect(issueMarker(subtask)).toBe('[s]');
  });

  it('história segue com o marcador do tipo', () => {
    expect(issueMarker(issue({ key: 'ENG-7', kind: 'História' }))).toBe('[S]');
  });
});

describe('groupByParent', () => {
  it('agrupa issues pelo pai e junta as sem pai em "sem pai"', () => {
    const groups = groupByParent(real);
    const withParent = groups.find((g) => g.parentKey === 'ENG-1');
    expect(withParent?.issues.map((i) => i.key)).toEqual(['ENG-101']);
    const orphanGroup = groups.find((g) => g.parentKey === null);
    expect(orphanGroup?.issues.map((i) => i.key).sort()).toEqual(['OPS-55', 'OPS-56']);
  });
});

describe('buildJiraTree', () => {
  const item = (over: Partial<JiraItem>): JiraItem => issue({ project: 'A', url: 'u', ...over });

  it('separa cada projeto em seu próprio grupo, em ordem alfabética', () => {
    const groups = buildJiraTree([
      item({ key: 'TT-1', project: 'TT' }),
      item({ key: 'PDS-1', project: 'PDS' }),
    ]);
    expect(groups.map((g) => g.project)).toEqual(['PDS', 'TT']);
  });

  it('aninha a filha sob a mãe quando as duas estão na lista', () => {
    const groups = buildJiraTree([
      item({ key: 'TT-1', project: 'TT' }),
      item({ key: 'TT-9', project: 'TT', parent: { key: 'TT-1', summary: 'mãe' } }),
    ]);
    expect(groups[0].roots).toHaveLength(1);
    expect(groups[0].roots[0].issue.key).toBe('TT-1');
    expect(groups[0].roots[0].children[0].issue.key).toBe('TT-9');
  });

  it('trata como raiz a issue cuja mãe não está na lista', () => {
    const groups = buildJiraTree([
      item({ key: 'TT-9', project: 'TT', parent: { key: 'TT-1', summary: 'ausente' } }),
    ]);
    expect(groups[0].roots).toHaveLength(1);
    expect(groups[0].roots[0].issue.key).toBe('TT-9');
  });

  it('conta a árvore inteira, não só as raízes', () => {
    const groups = buildJiraTree([
      item({ key: 'TT-1', project: 'TT' }),
      item({ key: 'TT-9', project: 'TT', parent: { key: 'TT-1', summary: 'mãe' } }),
      item({ key: 'TT-10', project: 'TT', parent: { key: 'TT-9', summary: 'filha' } }),
    ]);
    expect(groups[0].count).toBe(3);
  });

  it('ignora uma issue que aponta para si mesma como mãe', () => {
    const groups = buildJiraTree([
      item({ key: 'TT-1', project: 'TT', parent: { key: 'TT-1', summary: 'ela mesma' } }),
    ]);
    expect(groups[0].roots[0].issue.key).toBe('TT-1');
    expect(groups[0].roots[0].children).toHaveLength(0);
  });

  it('começa no objetivo quando os ancestrais vêm junto', () => {
    const historia = item({
      key: 'TT-9',
      project: 'TT',
      parent: { key: 'TT-5', summary: 'épico' },
    });
    const groups = buildJiraTree(
      [historia],
      [
        item({ key: 'TT-5', project: 'TT', kind: 'Epic', parent: { key: 'TT-2', summary: 'ini' } }),
        item({
          key: 'TT-2',
          project: 'TT',
          kind: 'Iniciativa',
          parent: { key: 'TT-1', summary: 'obj' },
        }),
        item({ key: 'TT-1', project: 'TT', kind: 'Objective' }),
      ],
    );

    const objetivo = groups[0].roots[0];
    expect(groups[0].roots).toHaveLength(1);
    expect(objetivo.issue.key).toBe('TT-1');
    expect(objetivo.children[0].issue.key).toBe('TT-2');
    expect(objetivo.children[0].children[0].issue.key).toBe('TT-5');
    expect(objetivo.children[0].children[0].children[0].issue.key).toBe('TT-9');
  });

  it('marca como caminho o ancestral, e como item o que veio da busca', () => {
    const groups = buildJiraTree(
      [item({ key: 'TT-9', project: 'TT', parent: { key: 'TT-1', summary: 'obj' } })],
      [item({ key: 'TT-1', project: 'TT', kind: 'Objective' })],
    );
    expect(groups[0].roots[0].origin).toBe('ancestor');
    expect(groups[0].roots[0].children[0].origin).toBe('match');
  });

  it('conta só o que veio da busca: o caminho não é trabalho', () => {
    const groups = buildJiraTree(
      [item({ key: 'TT-9', project: 'TT', parent: { key: 'TT-1', summary: 'obj' } })],
      [item({ key: 'TT-1', project: 'TT', kind: 'Objective' })],
    );
    expect(groups[0].count).toBe(1);
  });

  it('descarta o ramo de ancestrais que não leva a nenhuma issue da busca', () => {
    const groups = buildJiraTree(
      [item({ key: 'TT-9', project: 'TT', parent: { key: 'TT-2', summary: 'ini viva' } })],
      [
        item({ key: 'TT-2', project: 'TT', parent: { key: 'TT-1', summary: 'obj' } }),
        item({ key: 'TT-3', project: 'TT', parent: { key: 'TT-1', summary: 'obj' } }),
        item({ key: 'TT-1', project: 'TT', kind: 'Objective' }),
      ],
    );
    expect(groups[0].roots[0].children.map((n) => n.issue.key)).toEqual(['TT-2']);
  });

  it('agrupa pelo projeto do objetivo, que pode não ser o da história', () => {
    const groups = buildJiraTree(
      [item({ key: 'TT-9', project: 'TT', parent: { key: 'EST-1', summary: 'obj' } })],
      [item({ key: 'EST-1', project: 'EST', kind: 'Objective' })],
    );
    expect(groups.map((g) => g.project)).toEqual(['EST']);
  });

  it('mantém como item a issue que também chegou como ancestral de outra', () => {
    const epico = item({ key: 'TT-5', project: 'TT', kind: 'Epic' });
    const groups = buildJiraTree(
      [epico, item({ key: 'TT-9', project: 'TT', parent: { key: 'TT-5', summary: 'épico' } })],
      [epico],
    );
    expect(groups[0].roots[0].origin).toBe('match');
    expect(groups[0].count).toBe(2);
  });
});
