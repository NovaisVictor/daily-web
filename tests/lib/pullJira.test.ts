import { describe, expect, it } from 'vitest';
import { jiraKeysInPulls, jiraKeysInTitle, pullsByJiraKey, withJira } from '@/lib/pullJira';
import type { JiraItem, PullRequestItem } from '@/lib/types';

const pull = (title: string, number = 1): PullRequestItem => ({
  repo: 'acme/app',
  number,
  title,
  url: `https://github.com/acme/app/pull/${number}`,
  author: 'eu',
  draft: false,
  awaitingYou: false,
  mine: true,
  isPullRequest: true,
  id: 'PR_test',
  createdAt: '',
  ci: 'none',
  failedChecks: [],
  review: 'none',
  pendingReviewers: [],
  merge: 'unknown',
  size: { additions: 1, deletions: 1, files: 1 },
  headRef: 'feature/x',
  baseRef: 'main',
  headSha: 'abc123',
  updatedAt: '2026-10-20T10:00:00Z',
});

const issue = (key: string, status: string, statusCategory: JiraItem['statusCategory']): JiraItem => ({
  key,
  summary: key,
  status,
  statusCategory,
  project: key.split('-')[0],
  url: `https://acme.atlassian.net/browse/${key}`,
  parent: null,
  role: 'assignee',
  awaitingApproval: false,
  kind: 'História',
  subtask: false,
  hierarchyLevel: 0,
  updatedAt: '',
  dueDate: '',
  priority: null,
  flag: 'none',
});

describe('jiraKeysInTitle', () => {
  // Os formatos tirados dos títulos reais dos PRs.
  it.each([
    ['feat(conta): trust das roles da casa sem ExternalId (TT-4887)', ['TT-4887']],
    ['docs(CYB-195): rascunho do padrão de triagem', ['CYB-195']],
    ['feat(jenkins): core LTS (TT-4994, TT-4995)', ['TT-4994', 'TT-4995']],
    ['feat(messaging): CMS e SMS (epic TT-4770)', ['TT-4770']],
    ['chore(deps): bump next from 16.2.10 to 16.3.8', []],
  ])('%s', (title, keys) => {
    expect(jiraKeysInTitle(title)).toEqual(keys);
  });

  it('não repete a chave citada duas vezes', () => {
    expect(jiraKeysInTitle('TT-1 depois de TT-1')).toEqual(['TT-1']);
  });

  it('ignora o que só parece chave em minúscula ou com zero à esquerda', () => {
    expect(jiraKeysInTitle('tt-12 e TT-012')).toEqual([]);
  });
});

describe('jiraKeysInPulls', () => {
  it('junta as chaves de todos os PRs sem repetir', () => {
    expect(jiraKeysInPulls([pull('a (TT-1)', 1), pull('b (TT-1, CYB-2)', 2)])).toEqual(['TT-1', 'CYB-2']);
  });
});

describe('withJira', () => {
  it('põe o status de cada card citado no PR', () => {
    const [item] = withJira([pull('feat (TT-1, TT-2)')], [issue('TT-1', 'Em Andamento', 'indeterminate'), issue('TT-2', 'Resolvido', 'done')]);
    expect(item.jira).toEqual([
      { key: 'TT-1', url: 'https://acme.atlassian.net/browse/TT-1', status: 'Em Andamento', statusCategory: 'indeterminate' },
      { key: 'TT-2', url: 'https://acme.atlassian.net/browse/TT-2', status: 'Resolvido', statusCategory: 'done' },
    ]);
  });

  // "UTF-8" tem forma de chave; o Jira não a devolve e ela não vira card.
  it('deixa de fora a chave que o Jira não devolveu', () => {
    const [item] = withJira([pull('fix: aceitar UTF-8 (TT-1)')], [issue('TT-1', 'Backlog', 'new')]);
    expect(item.jira?.map((r) => r.key)).toEqual(['TT-1']);
  });

  it('mantém o PR sem campo quando nenhum card voltou', () => {
    const original = pull('chore: sem card');
    expect(withJira([original], [])[0]).toBe(original);
  });
});

describe('pullsByJiraKey', () => {
  it('agrupa por card e conta o mesmo PR uma vez só', () => {
    const [a] = withJira([pull('feat (TT-1, TT-2)', 1)], [issue('TT-1', 'x', 'new'), issue('TT-2', 'x', 'new')]);
    const [b] = withJira([pull('fix (TT-1)', 2)], [issue('TT-1', 'x', 'new')]);
    const byKey = pullsByJiraKey([a, b, a]);
    expect(byKey.get('TT-1')?.map((p) => p.number)).toEqual([1, 2]);
    expect(byKey.get('TT-2')?.map((p) => p.number)).toEqual([1]);
  });

  it('PR sem card resolvido não entra', () => {
    expect(pullsByJiraKey([pull('feat (TT-9)')]).size).toBe(0);
  });
});
