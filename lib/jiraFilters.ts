import { matchesQuery, type ActiveFilter } from '@/lib/filters';
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

const TIER_LEVEL: Record<JiraTier, number> = {
  initiative: 2,
  epic: 1,
  story: 0,
};

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
  status: groupOf(),
  tier: groupOf(),
  initiative: groupOf(),
  epic: groupOf(),
  story: groupOf(),
};

/** Os seletores do painel, na ordem em que aparecem. */
export type JiraFilterField = Exclude<keyof JiraFilterState, 'query'>;

type HierarchyField = 'initiative' | 'epic' | 'story';

type ValueOf<F extends JiraFilterField> = JiraFilterState[F]['values'][number];

interface FieldSpec<T> {
  label: string;
  param: string;
  modeParam: string;
  validate: (raw: string) => T | null;
}

const QUERY_PARAM = 'jiraBusca';

const MAX_TEXT = 200;

function text(raw: string | null): string {
  if (!raw) return '';
  return raw.length > MAX_TEXT ? '' : raw;
}

function validateKey(raw: string): string | null {
  return isJiraKey(raw) ? raw.toUpperCase() : null;
}

function validateTier(raw: string): JiraTier | null {
  return JIRA_TIERS.find((t) => t === raw) ?? null;
}

function validateStatus(raw: string): string | null {
  return text(raw) || null;
}

const FIELDS: { [F in JiraFilterField]: FieldSpec<ValueOf<F>> } = {
  status: {
    label: 'Status',
    param: 'jiraStatus',
    modeParam: 'jiraStatusModo',
    validate: validateStatus,
  },
  tier: {
    label: 'Tipo',
    param: 'jiraTipo',
    modeParam: 'jiraTipoModo',
    validate: validateTier,
  },
  initiative: {
    label: 'Iniciativa',
    param: 'jiraIniciativa',
    modeParam: 'jiraIniciativaModo',
    validate: validateKey,
  },
  epic: {
    label: 'Épico',
    param: 'jiraEpico',
    modeParam: 'jiraEpicoModo',
    validate: validateKey,
  },
  story: {
    label: 'História',
    param: 'jiraHistoria',
    modeParam: 'jiraHistoriaModo',
    validate: validateKey,
  },
};

export const JIRA_FILTER_FIELDS = Object.keys(FIELDS) as JiraFilterField[];

export function isJiraFilterField(id: string): id is JiraFilterField {
  return Object.hasOwn(FIELDS, id);
}

// O degrau de cima recorta as opções dos de baixo: o que foi escolhido neles
// só fazia sentido dentro dele.
const BELOW: Record<JiraFilterField, HierarchyField[]> = {
  status: [],
  tier: [],
  initiative: ['epic', 'story'],
  epic: ['story'],
  story: [],
};

function parseGroup<T>(params: URLSearchParams, spec: FieldSpec<T>): JiraFilterGroup<T> {
  let mode: FilterMode = params.get(spec.modeParam) === 'exclude' ? 'exclude' : 'include';
  const values: T[] = [];
  const tokens = params
    .getAll(spec.param)
    .flatMap((val) => val.split(','))
    .map((t) => t.trim())
    .filter(Boolean);

  for (const token of tokens) {
    let clean = token;
    if (clean.startsWith('!')) {
      mode = 'exclude';
      clean = clean.slice(1).trim();
    }
    const validated = clean ? spec.validate(clean) : null;
    if (validated !== null && !values.includes(validated)) values.push(validated);
  }

  return { values, mode };
}

/** A URL é entrada não confiável: o que não é um valor que a tela produz cai
 *  no padrão em vez de virar estado. */
export function parseJiraFilters(params: URLSearchParams): JiraFilterState {
  return {
    query: text(params.get(QUERY_PARAM)),
    status: parseGroup(params, FIELDS.status),
    tier: parseGroup(params, FIELDS.tier),
    initiative: parseGroup(params, FIELDS.initiative),
    epic: parseGroup(params, FIELDS.epic),
    story: parseGroup(params, FIELDS.story),
  };
}

/** Escreve o recorte na URL existente, preservando o resto. O vazio sai da
 *  URL para o link continuar limpo. */
export function jiraFiltersToParams(
  current: URLSearchParams,
  filters: JiraFilterState,
): URLSearchParams {
  const params = new URLSearchParams(current);
  if (filters.query) params.set(QUERY_PARAM, filters.query);
  else params.delete(QUERY_PARAM);

  for (const field of JIRA_FILTER_FIELDS) {
    const { param, modeParam } = FIELDS[field];
    const group: JiraFilterGroup<string> = filters[field];
    if (group.values.length === 0) params.delete(param);
    else params.set(param, group.values.join(','));
    if (group.values.length > 0 && group.mode === 'exclude') params.set(modeParam, 'exclude');
    else params.delete(modeParam);
  }
  return params;
}

export function hasJiraFilters(filters: JiraFilterState): boolean {
  return (
    filters.query.trim() !== '' ||
    JIRA_FILTER_FIELDS.some((field) => filters[field].values.length > 0)
  );
}

function clearedBelow(field: JiraFilterField): Partial<JiraFilterState> {
  return Object.fromEntries(BELOW[field].map((below) => [below, groupOf()]));
}

/** Tirar um filtro. Tirar um degrau de cima solta os de baixo. */
export function clearJiraFilter(field: JiraFilterField | 'query'): Partial<JiraFilterState> {
  if (field === 'query') return { query: '' };
  return { [field]: groupOf(), ...clearedBelow(field) };
}

/** Trocar a escolha de um seletor. Se nada do que estava escolhido continua,
 *  o degrau mudou de assunto e os de baixo são soltos; acrescentar um valor ou
 *  trocar o modo mantém o recorte de baixo. */
export function changeJiraFilter<F extends JiraFilterField>(
  filters: JiraFilterState,
  field: F,
  next: JiraFilterState[F],
): Partial<JiraFilterState> {
  const previous: string[] = filters[field].values;
  const nextValues: string[] = next.values;
  const switched = previous.length > 0 && !previous.some((v) => nextValues.includes(v));
  return { [field]: next, ...(switched ? clearedBelow(field) : {}) };
}

/** Os chips do recorte ativo. `describeIssue` dá o rótulo de uma chave de
 *  issue, que só o painel conhece. */
export function activeJiraFilters(
  filters: JiraFilterState,
  describeIssue: (key: string) => string,
): ActiveFilter[] {
  const describe = (field: JiraFilterField, value: string) =>
    field === 'status'
      ? value
      : field === 'tier'
        ? JIRA_TIER_LABEL[value as JiraTier]
        : describeIssue(value);

  const query = filters.query.trim();
  return [
    ...(query ? [{ id: 'query', label: `Busca: ${query}` }] : []),
    ...JIRA_FILTER_FIELDS.filter((field) => filters[field].values.length > 0).map((field) => {
      const group: JiraFilterGroup<string> = filters[field];
      const separator = group.mode === 'exclude' ? ' ≠ ' : ': ';
      const values = group.values.map((value) => describe(field, value)).join(', ');
      return {
        id: field,
        label: `${FIELDS[field].label}${separator}${values}`,
      };
    }),
  ];
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

function underAny(item: JiraItem, lineage: JiraItem[], keys: string[]): boolean {
  return keys.some((key) => item.key === key || lineage.some((a) => a.key === key));
}

function sameStatus(a: string, b: string): boolean {
  return a.trim().toLowerCase() === b.trim().toLowerCase();
}

/** Grupo vazio deixa passar; senão, incluir pede que case e excluir, que não. */
function passes(group: JiraFilterGroup<unknown>, matched: boolean): boolean {
  return group.values.length === 0 || matched === (group.mode === 'include');
}

export function matchesJiraFilters(
  item: JiraItem,
  filters: JiraFilterState,
  byKey: Map<string, JiraItem>,
): boolean {
  if (
    !passes(
      filters.status,
      filters.status.values.some((s) => sameStatus(item.status, s)),
    )
  ) {
    return false;
  }
  const itemTier = tierOf(item);
  if (!passes(filters.tier, itemTier !== null && filters.tier.values.includes(itemTier))) {
    return false;
  }

  const lineage = lineageOf(item, byKey);
  const hierarchy: HierarchyField[] = ['initiative', 'epic', 'story'];
  const inHierarchy = (field: HierarchyField) =>
    passes(filters[field], underAny(item, lineage, filters[field].values));
  if (!hierarchy.every(inHierarchy)) return false;

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
      .filter(
        ({ item, lineage }) =>
          (withinInitiatives.length === 0 || underAny(item, lineage, withinInitiatives)) &&
          (withinEpics.length === 0 || underAny(item, lineage, withinEpics)),
      )
      .map(({ item }) => item)
      .sort((a, b) => a.summary.localeCompare(b.summary));

  return {
    statuses: [...statuses.values()].sort((a, b) => a.localeCompare(b)),
    initiatives: ofTier('initiative', [], []),
    epics: ofTier('epic', activeInitiatives, []),
    stories: ofTier('story', activeInitiatives, activeEpics),
  };
}
