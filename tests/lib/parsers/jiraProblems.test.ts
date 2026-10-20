import { describe, expect, it } from 'vitest';
import { findProblems } from '@/lib/parsers/jiraProblems';
import type { JiraAuditIssue } from '@/lib/parsers/jiraProblems';
import type { JiraItem } from '@/lib/types';

function item(over: Partial<JiraItem> = {}): JiraItem {
  return {
    key: 'A-1',
    summary: 'Resumo',
    status: 'Aberto',
    statusCategory: 'new',
    project: 'A',
    url: 'https://acme.atlassian.net/browse/A-1',
    parent: null,
    role: 'assignee',
    awaitingApproval: false,
    kind: 'História',
    subtask: false,
    hierarchyLevel: null,
    updatedAt: '2026-09-10T12:00:00.000Z',
    dueDate: '',
    priority: null,
    flag: 'none',
    ...over,
  };
}

/** Uma história sem defeito nenhum: cada teste liga só o que quer ver. */
function story(over: Partial<JiraAuditIssue> = {}): JiraAuditIssue {
  return {
    ...item({ parent: { key: 'A-100', summary: 'Épico' } }),
    startDate: '2026-09-01',
    ...over,
  };
}

function epic(over: Partial<JiraAuditIssue> = {}): JiraAuditIssue {
  return { ...item({ key: 'A-100', kind: 'Epic' }), startDate: '', ...over };
}

const child = (over: Partial<JiraItem>) =>
  item({ key: 'A-2', parent: { key: 'A-100', summary: 'Épico' }, ...over });

const problemsOf = (scope: JiraAuditIssue[], children: JiraItem[] = [], key = scope[0].key) =>
  findProblems(scope, children).find((i) => i.key === key)?.problems ?? [];

describe('findProblems: histórias', () => {
  it('não lista a história bem preenchida', () => {
    expect(findProblems([story({ statusCategory: 'indeterminate' })], [])).toEqual([]);
  });

  it('aponta a história em andamento sem data de início', () => {
    expect(problemsOf([story({ statusCategory: 'indeterminate', startDate: '' })])).toEqual([
      'story-in-progress-without-start',
    ]);
  });

  it('não cobra data de início da história que ainda não começou', () => {
    expect(problemsOf([story({ statusCategory: 'new', startDate: '' })])).toEqual([]);
  });

  it('aponta a história concluída sem data de início', () => {
    expect(problemsOf([story({ statusCategory: 'done', startDate: '' })])).toEqual([
      'story-done-without-start',
    ]);
  });

  // A maioria dos workflows desta instância não aplica resolução ao concluir,
  // então a data de resolução fica vazia em história legitimamente fechada.
  it('não cobra data de conclusão da história concluída', () => {
    expect(problemsOf([story({ statusCategory: 'done' })])).toEqual([]);
  });

  it('aponta a história sem épico, em qualquer situação', () => {
    expect(problemsOf([story({ parent: null })])).toEqual(['story-without-epic']);
  });

  it('junta todos os problemas da mesma história numa linha só', () => {
    expect(
      problemsOf([story({ statusCategory: 'done', parent: null, startDate: '' })]),
    ).toEqual(['story-done-without-start', 'story-without-epic']);
  });

  it('reconhece a história pelo nome do tipo em português e em inglês', () => {
    expect(problemsOf([story({ kind: 'Story', parent: null })])).toEqual(['story-without-epic']);
  });

  it('ignora o que não é história nem épico', () => {
    expect(findProblems([story({ kind: 'Tarefa', parent: null })], [])).toEqual([]);
    expect(findProblems([story({ subtask: true, parent: null })], [])).toEqual([]);
  });
});

describe('findProblems: épicos', () => {
  it('aponta o épico sem nenhuma história', () => {
    expect(problemsOf([epic()])).toEqual(['epic-without-stories']);
  });

  it('não conta como história a filha de outro tipo', () => {
    expect(problemsOf([epic()], [child({ kind: 'Tarefa' })])).toEqual(['epic-without-stories']);
  });

  it('não conta a história de outro épico', () => {
    expect(
      problemsOf([epic()], [child({ parent: { key: 'A-999', summary: 'Outro' } })]),
    ).toEqual(['epic-without-stories']);
  });

  it('aceita o épico com história', () => {
    expect(findProblems([epic()], [child({})])).toEqual([]);
  });

  it('aponta o épico em andamento sem história em andamento', () => {
    expect(
      problemsOf(
        [epic({ statusCategory: 'indeterminate' })],
        [child({ statusCategory: 'new' }), child({ key: 'A-3', statusCategory: 'done' })],
      ),
    ).toEqual(['epic-in-progress-without-active-story']);
  });

  it('aceita o épico em andamento com uma história em andamento', () => {
    expect(
      findProblems(
        [epic({ statusCategory: 'indeterminate' })],
        [child({ statusCategory: 'new' }), child({ key: 'A-3', statusCategory: 'indeterminate' })],
      ),
    ).toEqual([]);
  });

  // Sem história nenhuma, "nenhuma em andamento" é consequência, não um
  // segundo defeito: a linha diz só o que precisa ser corrigido.
  it('no épico em andamento sem histórias, aponta só a falta de histórias', () => {
    expect(problemsOf([epic({ statusCategory: 'indeterminate' })])).toEqual([
      'epic-without-stories',
    ]);
  });

  it('não cobra história em andamento do épico que não está em andamento', () => {
    expect(findProblems([epic({ statusCategory: 'done' })], [child({ statusCategory: 'done' })])).toEqual([]);
  });
});

describe('findProblems: resultado', () => {
  it('mantém a issue inteira, com o link, junto dos problemas', () => {
    const [found] = findProblems([story({ parent: null })], []);
    expect(found.url).toBe('https://acme.atlassian.net/browse/A-1');
    expect(found.summary).toBe('Resumo');
  });

  it('preserva a ordem de entrada', () => {
    const keys = findProblems(
      [story({ key: 'A-5', parent: null }), epic(), story({ key: 'A-3', parent: null })],
      [],
    ).map((i) => i.key);
    expect(keys).toEqual(['A-5', 'A-100', 'A-3']);
  });
});
