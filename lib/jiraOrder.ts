import type { JiraItem } from '@/lib/types';
import type { JiraNode, JiraProjectGroup } from '@/lib/parsers/jira';

/** Como a lista do Jira se ordena. A padrão é a que o Jira já devolve, da
 *  alteração mais recente para a mais antiga. */
export type JiraOrder = 'atualizacao' | 'prazo' | 'prioridade' | 'parado';

export const JIRA_ORDER_PARAM = 'jiraOrdem';
export const JIRA_ORDER_DEFAULT: JiraOrder = 'atualizacao';

export const JIRA_ORDER_LABEL: Record<JiraOrder, string> = {
  atualizacao: 'Atualização',
  prazo: 'Prazo',
  prioridade: 'Prioridade',
  parado: 'Parado há mais tempo',
};

export function parseJiraOrder(value: string | null): JiraOrder {
  return value && Object.hasOwn(JIRA_ORDER_LABEL, value) ? (value as JiraOrder) : JIRA_ORDER_DEFAULT;
}

const time = (iso: string) => {
  const t = Date.parse(iso);
  return Number.isNaN(t) ? null : t;
};

/** Ausente vai para o fim em qualquer critério: a issue sem prazo não vence
 *  antes da que vence amanhã. */
function ascending(a: number | null, b: number | null): number {
  if (a === null && b === null) return 0;
  if (a === null) return 1;
  if (b === null) return -1;
  return a - b;
}

const negate = (t: number | null) => (t === null ? null : -t);

const recentFirst = (a: JiraItem, b: JiraItem) =>
  ascending(negate(time(a.updatedAt)), negate(time(b.updatedAt)));

export function compareJira(order: JiraOrder): (a: JiraItem, b: JiraItem) => number {
  switch (order) {
    case 'prazo':
      return (a, b) => ascending(time(a.dueDate), time(b.dueDate)) || recentFirst(a, b);
    case 'prioridade':
      return (a, b) => ascending(a.priority?.rank ?? null, b.priority?.rank ?? null) || recentFirst(a, b);
    case 'parado':
      return (a, b) => ascending(time(a.updatedAt), time(b.updatedAt));
    case 'atualizacao':
      return recentFirst;
  }
}

export function sortJira<T extends JiraItem>(items: T[], order: JiraOrder): T[] {
  return order === JIRA_ORDER_DEFAULT ? items : [...items].sort(compareJira(order));
}

/** A árvore na ordem pedida. Um ramo vale pelo que ele tem de mais urgente:
 *  o épico que é só caminho sobe junto com a história que vence amanhã. */
export function sortJiraTree(groups: JiraProjectGroup[], order: JiraOrder): JiraProjectGroup[] {
  if (order === JIRA_ORDER_DEFAULT) return groups;
  const compare = compareJira(order);

  const sortNode = (node: JiraNode): { node: JiraNode; best: JiraItem | null } => {
    const children = node.children.map(sortNode).sort((a, b) => byBest(a.best, b.best));
    const candidates = [
      ...(node.origin === 'match' ? [node.issue] : []),
      ...children.flatMap((c) => (c.best ? [c.best] : [])),
    ];
    const best = candidates.sort(compare)[0] ?? null;
    return { node: { ...node, children: children.map((c) => c.node) }, best };
  };
  const byBest = (a: JiraItem | null, b: JiraItem | null) =>
    a && b ? compare(a, b) : a ? -1 : b ? 1 : 0;

  return groups.map((group) => ({
    ...group,
    roots: group.roots
      .map(sortNode)
      .sort((a, b) => byBest(a.best, b.best))
      .map((r) => r.node),
  }));
}
