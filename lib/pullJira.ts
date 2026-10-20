import type { PullJiraRef, PullRequestItem, JiraItem } from '@/lib/types';
import { isJiraKey } from '@/lib/jiraKey';

// O título traz a chave de vários jeitos — "(TT-4887)", "docs(CYB-195):",
// "(TT-4994, TT-4995)". O que parece chave mas não é ("UTF-8") some na busca:
// o Jira ignora a chave de projeto que não existe, sem erro.
const KEY_IN_TEXT = /\b[A-Z][A-Z0-9_]*-[1-9]\d*\b/g;

// Um título com mais do que isto não é de um card só; é lista colada.
const MAX_KEYS_PER_TITLE = 5;

// A busca por chave devolve uma página só, de cem issues.
const MAX_KEYS = 100;

export function jiraKeysInTitle(title: string): string[] {
  const keys = (title.match(KEY_IN_TEXT) ?? []).filter(isJiraKey);
  return [...new Set(keys)].slice(0, MAX_KEYS_PER_TITLE);
}

/** As chaves de todos os PRs, sem repetição, para uma busca só no Jira. */
export function jiraKeysInPulls(items: PullRequestItem[]): string[] {
  return [...new Set(items.flatMap((item) => jiraKeysInTitle(item.title)))].slice(0, MAX_KEYS);
}

/** Cada PR com os cards que o título cita e o Jira devolveu. A chave que o
 *  Jira não conhece fica de fora: não há status a mostrar para ela. */
export function withJira(items: PullRequestItem[], issues: JiraItem[]): PullRequestItem[] {
  const byKey = new Map(issues.map((issue) => [issue.key, issue]));
  return items.map((item) => {
    const jira: PullJiraRef[] = jiraKeysInTitle(item.title).flatMap((key) => {
      const issue = byKey.get(key);
      return issue
        ? [{ key, url: issue.url, status: issue.status, statusCategory: issue.statusCategory }]
        : [];
    });
    return jira.length > 0 ? { ...item, jira } : item;
  });
}

/** Os PRs que citam cada card, pela chave. Só entra o card que o Jira
 *  devolveu: é o mesmo vínculo que a lista de PRs mostra. O PR que aparece nas
 *  duas listas — seu e com revisão pedida — conta uma vez. */
export function pullsByJiraKey(items: PullRequestItem[]): Map<string, PullRequestItem[]> {
  const byKey = new Map<string, PullRequestItem[]>();
  for (const item of items) {
    for (const ref of item.jira ?? []) {
      const list = byKey.get(ref.key) ?? [];
      if (!list.some((known) => known.url === item.url)) list.push(item);
      byKey.set(ref.key, list);
    }
  }
  return byKey;
}
