import { matchesQuery } from '@/lib/filters';
import { isJiraKey } from '@/lib/jiraKey';
import type { JiraItem } from '@/lib/types';

/** Os três degraus que o painel deixa escolher. O Jira desta instância tem
 *  objetivo acima e subtarefa abaixo, mas é nestes que o trabalho se organiza. */
export type JiraTier = 'initiative' | 'epic' | 'story';

export const JIRA_TIERS: readonly JiraTier[] = ['initiative', 'epic', 'story'];

export const JIRA_TIER_LABEL: Record<JiraTier, string> = {
  initiative: 'Iniciativas',
  epic: 'Épicos',
  story: 'Histórias',
};

const TIER_LEVEL: Record<JiraTier, number> = { initiative: 2, epic: 1, story: 0 };

export function tierOf(item: JiraItem): JiraTier | null {
  return JIRA_TIERS.find((tier) => TIER_LEVEL[tier] === item.hierarchyLevel) ?? null;
}

export type FilterMode = 'include' | 'exclude';

export interface JiraFilterGroup<T = string> {
  values: T[];
  mode: FilterMode;
}

export function groupOf<T>(values: T[] = [], mode: FilterMode = 'include'): JiraFilterGroup<T> {
  return { values, mode };
}

/** O recorte do painel do Jira. Vazio é "sem filtro"; cada campo é
 *  independente, e os três de hierarquia se somam: escolher épico dentro de
 *  uma iniciativa restringe mais, não troca. Cada seletor aceita valores
 *  compostos e modo de inclusão (igual a) ou exclusão (não é igual a). */
export interface JiraFilterState {
  query: string;
  status: JiraFilterGroup<string>;
  tier: JiraFilterGroup<JiraTier>;
  initiative: JiraFilterGroup<string>;
  epic: JiraFilterGroup<string>;
  story: JiraFilterGroup<string>;
}

export const EMPTY_JIRA_FILTERS: JiraFilterState = {
  query: '',
  status: { values: [], mode: 'include' },
  tier: { values: [], mode: 'include' },
  initiative: { values: [], mode: 'include' },
  epic: { values: [], mode: 'include' },
  story: { values: [], mode: 'include' },
};

const PARAMS = {
  query: 'jiraBusca',
  status: 'jiraStatus',
  statusMode: 'jiraStatusModo',
  tier: 'jiraTipo',
  tierMode: 'jiraTipoModo',
  initiative: 'jiraIniciativa',
  initiativeMode: 'jiraIniciativaModo',
  epic: 'jiraEpico',
  epicMode: 'jiraEpicoModo',
  story: 'jiraHistoria',
  storyMode: 'jiraHistoriaModo',
} as const;

const MAX_TEXT = 200;

function text(raw: string | null): string {
  if (!raw) return '';
  return raw.length > MAX_TEXT ? '' : raw;
}

function keyValidator(raw: string | null): string | null {
  return raw && isJiraKey(raw) ? raw.toUpperCase() : null;
}

function tierValidator(raw: string | null): JiraTier | null {
  return JIRA_TIERS.find((t) => t === raw) ?? null;
}

function statusValidator(raw: string | null): string | null {
  const t = text(raw);
  return t ? t : null;
}

function parseGroup<T>(
  params: URLSearchParams,
  paramKey: string,
  modeKey: string,
  validator: (raw: string) => T | null,
): JiraFilterGroup<T> {
  const modeParam = params.get(modeKey);
  let mode: FilterMode = modeParam === 'exclude' ? 'exclude' : 'include';

  const rawValues = params.getAll(paramKey);
  const tokens = rawValues
    .flatMap((val) => val.split(','))
    .map((t) => t.trim())
    .filter(Boolean);

  const values: T[] = [];
  for (const token of tokens) {
    let clean = token;
    if (clean.startsWith('!')) {
      mode = 'exclude';
      clean = clean.slice(1).trim();
    }
    const validated = validator(clean);
    if (validated !== null && !values.includes(validated)) {
      values.push(validated);
    }
  }

  return { values, mode };
}

/** A URL é entrada não confiável: o que não é um valor que a tela produz cai
 *  no padrão em vez de virar estado. */
export function parseJiraFilters(params: URLSearchParams): JiraFilterState {
  return {
    query: text(params.get(PARAMS.query)),
    status: parseGroup(params, PARAMS.status, PARAMS.statusMode, statusValidator),
    tier: parseGroup(params, PARAMS.tier, PARAMS.tierMode, tierValidator),
    initiative: parseGroup(params, PARAMS.initiative, PARAMS.initiativeMode, keyValidator),
    epic: parseGroup(params, PARAMS.epic, PARAMS.epicMode, keyValidator),
    story: parseGroup(params, PARAMS.story, PARAMS.storyMode, keyValidator),
  };
}

/** Escreve o recorte na URL existente, preservando o resto. O vazio sai da
 *  URL para o link continuar limpo. */
export function jiraFiltersToParams(
  current: URLSearchParams,
  filters: JiraFilterState,
): URLSearchParams {
  const params = new URLSearchParams(current);
  const putText = (name: string, value: string) => {
    if (value) params.set(name, value);
    else params.delete(name);
  };

  const putGroup = <T>(paramKey: string, modeKey: string, group: JiraFilterGroup<T>) => {
    if (group.values.length === 0) {
      params.delete(paramKey);
      params.delete(modeKey);
    } else {
      params.set(paramKey, group.values.join(','));
      if (group.mode === 'exclude') {
        params.set(modeKey, 'exclude');
      } else {
        params.delete(modeKey);
      }
    }
  };

  putText(PARAMS.query, filters.query);
  putGroup(PARAMS.status, PARAMS.statusMode, filters.status);
  putGroup(PARAMS.tier, PARAMS.tierMode, filters.tier);
  putGroup(PARAMS.initiative, PARAMS.initiativeMode, filters.initiative);
  putGroup(PARAMS.epic, PARAMS.epicMode, filters.epic);
  putGroup(PARAMS.story, PARAMS.storyMode, filters.story);
  return params;
}

export function hasJiraFilters(filters: JiraFilterState): boolean {
  return (
    filters.query.trim() !== '' ||
    filters.status.values.length > 0 ||
    filters.tier.values.length > 0 ||
    filters.initiative.values.length > 0 ||
    filters.epic.values.length > 0 ||
    filters.story.values.length > 0
  );
}

// Teto da subida: a hierarquia tem cinco degraus. O limite existe para um
// pai que aponte de volta não virar laço.
const MAX_LINEAGE = 8;

/** Os ancestrais conhecidos da issue, do pai para cima. */
export function lineageOf(item: JiraItem, byKey: Map<string, JiraItem>): JiraItem[] {
  const lineage: JiraItem[] = [];
  const seen = new Set([item.key]);
  let parentKey = item.parent?.key;
  while (parentKey && !seen.has(parentKey) && lineage.length < MAX_LINEAGE) {
    const parent = byKey.get(parentKey);
    if (!parent) break;
    lineage.push(parent);
    seen.add(parentKey);
    parentKey = parent.parent?.key;
  }
  return lineage;
}

function underOrSelf(item: JiraItem, lineage: JiraItem[], selected: string): boolean {
  return !selected || item.key === selected || lineage.some((a) => a.key === selected);
}

function sameStatus(a: string, b: string): boolean {
  return a.trim().toLowerCase() === b.trim().toLowerCase();
}

export function matchesJiraFilters(
  item: JiraItem,
  filters: JiraFilterState,
  byKey: Map<string, JiraItem>,
): boolean {
  if (filters.status.values.length > 0) {
    const matched = filters.status.values.some((s) => sameStatus(item.status, s));
    if (filters.status.mode === 'include' && !matched) return false;
    if (filters.status.mode === 'exclude' && matched) return false;
  }

  if (filters.tier.values.length > 0) {
    const itemTier = tierOf(item);
    const matched = itemTier !== null && filters.tier.values.includes(itemTier);
    if (filters.tier.mode === 'include' && !matched) return false;
    if (filters.tier.mode === 'exclude' && matched) return false;
  }

  const lineage = lineageOf(item, byKey);

  const matchesHierarchy = (group: JiraFilterGroup<string>): boolean => {
    if (group.values.length === 0) return true;
    const inHierarchy = group.values.some(
      (selected) => item.key === selected || lineage.some((a) => a.key === selected),
    );
    return group.mode === 'include' ? inHierarchy : !inHierarchy;
  };

  if (!matchesHierarchy(filters.initiative)) return false;
  if (!matchesHierarchy(filters.epic)) return false;
  if (!matchesHierarchy(filters.story)) return false;

  // A busca olha o caminho inteiro: procurar pelo nome da iniciativa traz o
  // que está debaixo dela, que é o que se quer ver ao lembrar só do tema.
  const campos = [item, ...lineage].flatMap((i) => [i.key, i.summary]);
  return matchesQuery(campos, filters.query);
}

export interface JiraFilterOptions {
  statuses: string[];
  initiatives: JiraItem[];
  epics: JiraItem[];
  stories: JiraItem[];
}

/**
 * O que cada seletor oferece para a lista da aba. Os de hierarquia descem em
 * cascata: com uma iniciativa escolhida, os épicos são só os dela, e as
 * histórias só as do épico (ou da iniciativa) escolhido. Uma opção sem nada da
 * lista debaixo dela não leva a lugar nenhum e não aparece.
 */
export function jiraFilterOptions(
  items: JiraItem[],
  byKey: Map<string, JiraItem>,
  filters: JiraFilterState,
): JiraFilterOptions {
  const statuses = new Map<string, string>();
  const pool = new Map<string, { item: JiraItem; lineage: JiraItem[] }>();

  for (const item of items) {
    const normalized = item.status.trim().toLowerCase();
    if (normalized && !statuses.has(normalized)) statuses.set(normalized, item.status.trim());
    const lineage = lineageOf(item, byKey);
    for (const [i, node] of [item, ...lineage].entries()) {
      if (!pool.has(node.key)) pool.set(node.key, { item: node, lineage: lineage.slice(i) });
    }
  }

  const activeInitiatives = filters.initiative.mode === 'include' ? filters.initiative.values : [];
  const activeEpics = filters.epic.mode === 'include' ? filters.epic.values : [];

  const ofTier = (tier: JiraTier, withinInitiatives: string[], withinEpics: string[]) =>
    [...pool.values()]
      .filter(({ item }) => tierOf(item) === tier)
      .filter(({ item, lineage }) => {
        if (withinInitiatives.length > 0) {
          const under = withinInitiatives.some((sel) => underOrSelf(item, lineage, sel));
          if (!under) return false;
        }
        if (withinEpics.length > 0) {
          const under = withinEpics.some((sel) => underOrSelf(item, lineage, sel));
          if (!under) return false;
        }
        return true;
      })
      .map(({ item }) => item)
      .sort((a, b) => a.summary.localeCompare(b.summary));

  return {
    statuses: [...statuses.values()].sort((a, b) => a.localeCompare(b)),
    initiatives: ofTier('initiative', [], []),
    epics: ofTier('epic', activeInitiatives, []),
    stories: ofTier('story', activeInitiatives, activeEpics),
  };
}
