import type { Connection } from '@/lib/vault/connections';
import type {
  JiraDatedItem,
  JiraFlag,
  JiraItem,
  JiraProblemItem,
  JiraRole,
  JiraStatusCategory,
  JiraPerson,
} from '@/lib/types';
import type { JiraFilter } from '@/lib/parsers/jira';
import { findProblems, isEpic } from '@/lib/parsers/jiraProblems';
import type { JiraAuditIssue } from '@/lib/parsers/jiraProblems';
import { isJiraKey } from '@/lib/preferences';
import { isJiraAccountId } from '@/lib/jiraAccount';

export type JiraSubject = { kind: 'me' } | { kind: 'person'; accountId: string };
export const ME: JiraSubject = { kind: 'me' };

function jqlUser(subject: JiraSubject): string {
  if (subject.kind === 'me') return 'currentUser()';
  if (!isJiraAccountId(subject.accountId)) throw new Error('conta do Jira inválida');
  return `"${subject.accountId}"`;
}

function jqlPending(subject: JiraSubject): string {
  if (subject.kind === 'me') return 'myPending()';
  if (!isJiraAccountId(subject.accountId)) throw new Error('conta do Jira inválida');
  return `pendingBy("${subject.accountId}")`;
}

const TIMEOUT_MS = 20_000;
const PAGE_SIZE = 100;

// `updated` e `duedate` são o que transforma a lista em "o que precisa de
// mim": sem eles não dá para saber o que está parado nem o que vence.
const FIELDS = ['summary', 'status', 'project', 'parent', 'issuetype', 'updated', 'duedate', 'priority'];

export interface JiraAuth {
  baseUrl: string;
  header: string;
}

/** Aceita "acme", "acme.atlassian.net" ou a URL inteira: quem está
 *  configurando copia da barra de endereços, não do manual. */
export function jiraBaseUrl(cloud: string): string {
  const raw = cloud.trim().replace(/\/+$/, '');
  if (!raw) throw new Error('domínio do Jira não configurado');
  if (/^https?:\/\//i.test(raw)) return raw;
  if (raw.includes('.')) return `https://${raw}`;
  return `https://${raw}.atlassian.net`;
}

export function jiraAuth(conn: Connection): JiraAuth {
  const { cloud = '', email = '', token = '' } = conn.values;
  if (!email.trim() || !token.trim()) throw new Error('e-mail ou API token do Jira não configurados');
  return {
    baseUrl: jiraBaseUrl(cloud),
    header: `Basic ${Buffer.from(`${email.trim()}:${token.trim()}`).toString('base64')}`,
  };
}

interface RawIssue {
  key: string;
  fields?: {
    summary?: string | null;
    updated?: string | null;
    duedate?: string | null;
    status?: {
      name?: string | null;
      statusCategory?: { key?: string | null } | null;
    } | null;
    project?: { key?: string | null } | null;
    issuetype?: {
      name?: string | null;
      subtask?: boolean | null;
      hierarchyLevel?: number | null;
    } | null;
    parent?: { key?: string; fields?: { summary?: string | null } | null } | null;
    priority?: { id?: string | null; name?: string | null } | null;
  } | null;
  /** O que depende de campo personalizado ou da ordem da instância, resolvido
   *  pela busca que trouxe a issue. Ausente quando ela veio de outro caminho. */
  resolved?: { flag: JiraFlag; priorityRank: number | null };
}

/** O Jira usa três chaves de categoria; qualquer outra coisa é tratada como
 *  pendente, que é o palpite seguro para uma issue que ainda aparece aqui. */
function toCategory(key: string | null | undefined): JiraStatusCategory {
  if (key === 'indeterminate' || key === 'done') return key;
  return 'new';
}

export function toJiraItem(raw: RawIssue, baseUrl: string, role: JiraRole): JiraItem {
  const fields = raw.fields ?? {};
  return {
    key: raw.key,
    summary: fields.summary ?? '',
    status: fields.status?.name ?? '',
    statusCategory: toCategory(fields.status?.statusCategory?.key),
    updatedAt: fields.updated ?? '',
    dueDate: fields.duedate ?? '',
    project: fields.project?.key ?? raw.key.split('-')[0] ?? '',
    url: `${baseUrl}/browse/${raw.key}`,
    parent: fields.parent
      ? { key: fields.parent.key ?? '', summary: fields.parent.fields?.summary ?? '' }
      : null,
    role,
    awaitingApproval: false,
    kind: fields.issuetype?.name ?? '',
    subtask: fields.issuetype?.subtask ?? false,
    hierarchyLevel:
      typeof fields.issuetype?.hierarchyLevel === 'number' ? fields.issuetype.hierarchyLevel : null,
    priority: fields.priority?.name
      ? { name: fields.priority.name, rank: raw.resolved?.priorityRank ?? null }
      : null,
    flag: raw.resolved?.flag ?? 'none',
  };
}

async function request(
  auth: JiraAuth,
  path: string,
  body: unknown,
  method: 'GET' | 'POST' | 'PUT' = body ? 'POST' : 'GET',
): Promise<unknown> {
  const response = await fetch(`${auth.baseUrl}${path}`, {
    method,
    headers: {
      authorization: auth.header,
      accept: 'application/json',
      ...(body ? { 'content-type': 'application/json' } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
    signal: AbortSignal.timeout(TIMEOUT_MS),
  });

  if (response.status === 401) throw new Error('Jira recusou o e-mail ou o API token');
  if (response.status === 403) throw new Error('o API token do Jira não tem permissão para isso');
  if (response.status === 404) throw new Error('domínio do Jira não encontrado');
  if (!response.ok) {
    const text = await response.text().catch(() => '');
    throw new Error(`Jira respondeu ${response.status}${text ? `: ${text.slice(0, 200)}` : ''}`);
  }
  // A edição de issue responde 204, sem corpo.
  if (response.status === 204) return null;
  return response.json();
}

interface JiraField {
  id?: string;
  name?: string;
}

interface JiraPriorityEntry {
  id?: string;
}

/** O que muda de uma instância do Jira para outra e quase nunca muda dentro
 *  dela: os ids dos campos personalizados e a ordem das prioridades. */
export interface InstanceMeta {
  startField: string | null;
  flaggedField: string | null;
  priorityRank: Map<string, number>;
}

const NO_META: InstanceMeta = { startField: null, flaggedField: null, priorityRank: new Map() };

// A data de início e a bandeira são campos personalizados, com id diferente
// em cada instância. O nome é o que se repete — em inglês ou no idioma do
// perfil.
const START_FIELD_NAMES = ['start date', 'data de início', 'data de inicio'];
const FLAGGED_FIELD_NAMES = ['flagged', 'sinalizado'];

// Seis horas: o campo só muda se alguém reconfigurar a instância, e cada
// ciclo de cinco minutos pagava duas idas ao Jira só para redescobri-lo.
const META_TTL_MS = 6 * 60 * 60 * 1000;

// No processo, não no módulo: o build empacota este arquivo mais de uma vez,
// e uma cópia do cache por pacote voltaria a pagar a descoberta.
const META_KEY = Symbol.for('daily-web.jira-instance-meta');
const metaState = ((globalThis as Record<symbol, unknown>)[META_KEY] ??= {
  cache: new Map(),
  inFlight: new Map(),
}) as {
  cache: Map<string, { at: number; meta: InstanceMeta }>;
  // As buscas de um ciclo saem juntas; sem isto, cada uma pagaria a
  // descoberta quando o cache está frio.
  inFlight: Map<string, Promise<InstanceMeta>>;
};
const metaCache = metaState.cache;

const fieldIdByName = (fields: JiraField[], names: string[]) =>
  fields.find((f) => names.includes(f.name?.trim().toLowerCase() ?? ''))?.id ?? null;

async function loadInstanceMeta(auth: JiraAuth): Promise<InstanceMeta> {
  const [fields, priorities] = await Promise.all([
    request(auth, '/rest/api/3/field', undefined),
    request(auth, '/rest/api/3/priority', undefined),
  ]);
  const list = Array.isArray(fields) ? (fields as JiraField[]) : [];
  // A lista de prioridades vem na ordem da instância, da mais alta para a
  // mais baixa; é a posição, e não o id, que diz qual vem antes.
  const ordered = Array.isArray(priorities) ? (priorities as JiraPriorityEntry[]) : [];
  return {
    startField: fieldIdByName(list, START_FIELD_NAMES),
    flaggedField: fieldIdByName(list, FLAGGED_FIELD_NAMES),
    priorityRank: new Map(
      ordered.flatMap((p, index) => (p.id ? [[p.id, index] as [string, number]] : [])),
    ),
  };
}

/** Os metadados da instância, do cache quando ainda valem. A falha não é
 *  guardada nem derruba a busca: sem eles a lista sai sem bandeira e sem
 *  ordem de prioridade, e a próxima busca tenta de novo. */
export async function instanceMeta(auth: JiraAuth): Promise<InstanceMeta> {
  const cached = metaCache.get(auth.baseUrl);
  if (cached && Date.now() - cached.at < META_TTL_MS) return cached.meta;
  const pending = metaState.inFlight.get(auth.baseUrl);
  if (pending) return pending;

  const loading = loadInstanceMeta(auth)
    .then((meta) => {
      metaCache.set(auth.baseUrl, { at: Date.now(), meta });
      return meta;
    })
    .catch(() => NO_META)
    .finally(() => metaState.inFlight.delete(auth.baseUrl));
  metaState.inFlight.set(auth.baseUrl, loading);
  return loading;
}

export function setInstanceMetaForTests(baseUrl: string, meta: InstanceMeta | null): void {
  metaState.inFlight.delete(baseUrl);
  if (meta) metaCache.set(baseUrl, { at: Date.now(), meta });
  else metaCache.delete(baseUrl);
}

const searchFields = (meta: InstanceMeta, extra: string[] = []) => [
  ...FIELDS,
  ...(meta.flaggedField ? [meta.flaggedField] : []),
  ...extra,
];

function resolve(issues: RawIssue[], meta: InstanceMeta): RawIssue[] {
  return issues.map((issue) => {
    const fields = (issue.fields ?? {}) as Record<string, unknown>;
    const flagged = meta.flaggedField ? fields[meta.flaggedField] : null;
    const priorityId = issue.fields?.priority?.id;
    return {
      ...issue,
      resolved: {
        flag: Array.isArray(flagged) && flagged.length > 0 ? 'impediment' : 'none',
        priorityRank: priorityId ? (meta.priorityRank.get(priorityId) ?? null) : null,
      },
    };
  });
}

interface SearchResponse {
  issues?: RawIssue[];
  nextPageToken?: string;
  isLast?: boolean;
}

async function search(auth: JiraAuth, jql: string): Promise<RawIssue[]> {
  const meta = await instanceMeta(auth);
  const payload = { jql, fields: searchFields(meta), maxResults: PAGE_SIZE };
  const data = (await request(auth, '/rest/api/3/search/jql', payload)) as SearchResponse;
  return resolve(data.issues ?? [], meta);
}

const OPEN = 'statusCategory != Done';

// O que espera por uma decisão do usuário ou da pessoa acompanhada. Para
// o usuário logado, `myPending()` funciona. Para outra pessoa, usa-se
// `pendingBy("<accountId>")` (com a ID em aspas — o formato sem aspas ou
// com `currentUser()` é recusado pela API).
const awaitingApprovalJql = (subject: JiraSubject) =>
  `approvals = ${jqlPending(subject)} AND ${OPEN} ORDER BY updated DESC`;

/** Uma issue pode ser de quem está sendo olhado como responsável e como relator ao mesmo tempo; a
 *  união é feita por chave para ela não aparecer duas vezes na lista.
 *
 *  A aprovação entra na mesma união, e não como lista à parte, porque é a
 *  mesma pergunta — "o que ainda pede algo" — e porque uma issue que
 *  seja de quem está sendo olhado e espere aprovação precisa continuar sendo uma linha só. */
export async function fetchIssues(conn: Connection, filter: JiraFilter, subject = ME): Promise<JiraItem[]> {
  const auth = jiraAuth(conn);
  const byKey = new Map<string, JiraItem>();

  const wantAssignee = filter === 'assignee' || filter === 'both';
  const wantReporter = filter === 'reporter' || filter === 'both';
  const userStr = jqlUser(subject);

  if (wantAssignee) {
    for (const raw of await search(auth, `assignee = ${userStr} AND ${OPEN} ORDER BY updated DESC`)) {
      byKey.set(raw.key, toJiraItem(raw, auth.baseUrl, 'assignee'));
    }
  }
  if (wantReporter) {
    for (const raw of await search(auth, `reporter = ${userStr} AND ${OPEN} ORDER BY updated DESC`)) {
      const existing = byKey.get(raw.key);
      if (existing) existing.role = 'both';
      else byKey.set(raw.key, toJiraItem(raw, auth.baseUrl, 'reporter'));
    }
  }

  // Buscada sempre, inclusive quando o filtro é só responsável ou só relator:
  // aprovar não é um papel na issue, e o filtro de papel não deveria
  // esconder o que espera aprovação.
  for (const raw of await search(auth, awaitingApprovalJql(subject))) {
    const existing = byKey.get(raw.key);
    // A issue que já veio pelo papel mantém o papel e ganha a marca. A que só
    // aparece por aprovação não tem papel: nem responsável, nem relator.
    // Entra com o valor neutro que o resto do módulo já usa nesse caso, para
    // não afirmar um papel que não se aplica — quem explica a presença dela na
    // lista é a marca de aprovação, não o papel.
    const item = existing ?? toJiraItem(raw, auth.baseUrl, 'assignee');
    item.awaitingApproval = true;
    byKey.set(raw.key, item);
  }

  return [...byKey.values()];
}

// As duas janelas que o painel oferece. A lista buscada é sempre a maior, e a
// menor serve só para marcar o que cabe no dia: trocar o período na tela é um
// recorte do que já está em memória, não uma nova ida ao Jira. O corte do dia
// continua sendo o do Jira (`startOfDay()`, no fuso do perfil), e não uma
// conta de data feita no navegador, que divergiria do que a interface do
// Atlassian mostra.
const WEEK = 'startOfDay(-7d)';
const TODAY = 'startOfDay()';

/** Marca, na lista da semana, quem também apareceu na busca do dia. */
function withToday(week: RawIssue[], today: RawIssue[], baseUrl: string): JiraDatedItem[] {
  const doDia = new Set(today.map((issue) => issue.key));
  return week.map((issue) => ({
    ...toJiraItem(issue, baseUrl, 'assignee'),
    today: doDia.has(issue.key),
  }));
}

// O que saiu das mãos de quem está sendo olhado. Duas condições, unidas porque as instâncias
// se comportam de formas diferentes:
//
//   - `status CHANGED BY currentUser() DURING (startOfDay(), now())` pega a
//     transição que você mesmo fez. Não depende do nome do status final, que
//     é livre por workflow — este Jira encerra em "Resolvido" e "Fechado",
//     outro encerra em "Done", e listar nomes quebraria fora daqui.
//   - `resolved >= startOfDay()` pega o que foi resolvido no nome de quem está
//     sendo olhado sem que a transição tenha sido dele, que é o caso de automação.
//
// `statusCategory = Done` por fora descarta o que foi fechado e alguém
// reabriu depois: reaberto não é entregue.
const delivered = (desde: string, subject: JiraSubject) => {
  const userStr = jqlUser(subject);
  return 'statusCategory = Done AND (' +
    `status CHANGED BY ${userStr} DURING (${desde}, now())` +
    ` OR (assignee = ${userStr} AND resolved >= ${desde})` +
    ') ORDER BY updated DESC';
};

/** Issues que este usuário (ou a pessoa olhada) encerrou nos últimos sete dias, marcadas conforme
 *  caiam ou não no dia de hoje. */
export async function fetchDelivered(conn: Connection, subject = ME): Promise<JiraDatedItem[]> {
  const auth = jiraAuth(conn);
  const [week, today] = await Promise.all([
    search(auth, delivered(WEEK, subject)),
    search(auth, delivered(TODAY, subject)),
  ]);
  return withToday(week, today, auth.baseUrl);
}

// O que foi aprovado por quem está sendo olhado. Não há função JQL para isto: `myApproved()` e
// `myDecided()` não existem, e `approvedBy(currentUser())` é recusada — o
// campo `approvals` não aceita função com argumento. `approved()` sozinho
// responde "aprovada por alguém", incluindo aprovações de outras pessoas.
//
// O que restringe a quem está sendo olhado é a transição de saída da aprovação ter sido sua.
// Diferente das outras consultas deste módulo, esta cita o nome do status:
// sem `FROM "Aprovação"`, uma issue aprovada por outra pessoa entra na lista
// assim que o status muda — foi medido contra a API de aprovação,
// e o nome é o que separa os dois casos. O preço é conhecido: se o workflow
// renomear esse status, a lista esvazia em silêncio.
const approved = (desde: string, subject: JiraSubject) =>
  'approvals = approved() AND ' +
  `status CHANGED FROM "Aprovação" BY ${jqlUser(subject)} DURING (${desde}, now())` +
  ' ORDER BY updated DESC';

/** Issues que este usuário (ou a pessoa olhada) aprovou nos últimos sete dias, marcadas conforme
 *  caiam ou não no dia de hoje. */
export async function fetchApproved(conn: Connection, subject = ME): Promise<JiraDatedItem[]> {
  const auth = jiraAuth(conn);
  const [week, today] = await Promise.all([
    search(auth, approved(WEEK, subject)),
    search(auth, approved(TODAY, subject)),
  ]);
  return withToday(week, today, auth.baseUrl);
}

interface Myself {
  accountId?: string;
}

// O JQL não tem operador de menção. A menção fica gravada no corpo do
// comentário como `[~accountid:XXX]`, e esse texto é indexado — procurar pelo
// accountId é o caminho que a própria Atlassian documenta.
export async function fetchMentions(conn: Connection): Promise<JiraItem[]> {
  const auth = jiraAuth(conn);
  const me = (await request(auth, '/rest/api/3/myself', undefined)) as Myself;
  if (!me.accountId) return [];

  const raw = await search(
    auth,
    `comment ~ "${me.accountId}" AND updated >= -30d ORDER BY updated DESC`,
  );
  return raw.map((issue) => toJiraItem(issue, auth.baseUrl, 'assignee'));
}

/**
 * Busca issues por chave, para a lista de acompanhamento. As chaves são
 * validadas antes de chegar aqui (`isJiraKey`) porque entram numa JQL — um
 * valor livre nesse ponto seria injeção de consulta.
 */
export async function fetchByKeys(conn: Connection, keys: string[]): Promise<JiraItem[]> {
  if (keys.length === 0) return [];
  const auth = jiraAuth(conn);
  const lista = keys.map((k) => `"${k}"`).join(', ');
  const raw = await search(auth, `key in (${lista}) ORDER BY updated DESC`);
  return raw.map((issue) => toJiraItem(issue, auth.baseUrl, 'assignee'));
}

// Quantos degraus a subida percorre. Uma subtarefa fica a quatro degraus do
// objetivo (história, épico, iniciativa, objetivo) e a hierarquia do Jira
// admite outro nível acima do épico, então o teto tem folga sobre isso. Ele
// existe para a subida terminar mesmo diante de uma corrente sem fim; cada
// degrau só custa uma consulta quando ainda há pai novo para buscar.
const ANCESTOR_LEVELS = 6;

// Chaves por consulta de ancestrais: o mesmo teto da busca de filhas.
const ANCESTOR_CHUNK = 50;

/** Os ancestrais das issues dadas, de pai em pai até o topo da hierarquia.
 *
 *  As buscas do painel trazem só o que é da pessoa — em geral a história e o
 *  épico. O que dá sentido a elas, a iniciativa e o objetivo, não é delas e
 *  nunca vem. Sem estes ancestrais a árvore começa no meio.
 *
 *  Um nível é uma ida ao Jira, não uma por issue: as chaves do nível inteiro
 *  vão juntas em `key in (...)`. O que já está na lista não é buscado de novo.
 *
 *  O papel não se aplica a um ancestral — ele está na lista por causa de uma
 *  descendente, não por ser de alguém. Quem separa os dois é a árvore, que
 *  marca estes nós como contexto. */
export async function fetchAncestors(conn: Connection, items: JiraItem[]): Promise<JiraItem[]> {
  if (items.length === 0) return [];
  const auth = jiraAuth(conn);

  const known = new Set(items.map((i) => i.key));
  const ancestors: JiraItem[] = [];
  let level: JiraItem[] = items;

  for (let degrau = 0; degrau < ANCESTOR_LEVELS && level.length > 0; degrau += 1) {
    // As chaves vêm do próprio Jira, mas entram numa JQL: a mesma validação
    // da lista de acompanhamento vale aqui.
    const keys = [...new Set(level.map((i) => i.parent?.key ?? ''))]
      .filter((key) => key && !known.has(key) && isJiraKey(key));
    if (keys.length === 0) break;
    for (const key of keys) known.add(key);

    const chunks: string[][] = [];
    for (let i = 0; i < keys.length; i += ANCESTOR_CHUNK) {
      chunks.push(keys.slice(i, i + ANCESTOR_CHUNK));
    }

    const raw = (
      await Promise.all(
        chunks.map((lote) => search(auth, `key in (${lote.map((k) => `"${k}"`).join(', ')})`)),
      )
    ).flat();

    level = raw.map((issue) => toJiraItem(issue, auth.baseUrl, 'assignee'));
    ancestors.push(...level);
  }

  return ancestors;
}

// A aba de problemas não pode parar na primeira página como as outras: uma
// filha que ficasse de fora faria o épico dela aparecer como "sem histórias".
// Então pagina até o fim, com um teto — passar dele é erro dito, não uma
// lista cortada em silêncio.
const MAX_PAGES = 10;

async function searchAll(
  auth: JiraAuth,
  jql: string,
  meta: InstanceMeta,
  extraFields: string[] = [],
): Promise<RawIssue[]> {
  const issues: RawIssue[] = [];
  const fields = searchFields(meta, extraFields);
  let nextPageToken: string | undefined;
  for (let page = 0; page < MAX_PAGES; page++) {
    const payload = { jql, fields, maxResults: PAGE_SIZE, ...(nextPageToken ? { nextPageToken } : {}) };
    const data = (await request(auth, '/rest/api/3/search/jql', payload)) as SearchResponse;
    issues.push(...resolve(data.issues ?? [], meta));
    if (data.isLast !== false || !data.nextPageToken) return issues;
    nextPageToken = data.nextPageToken;
  }
  throw new Error(`a busca do Jira passou de ${MAX_PAGES * PAGE_SIZE} issues`);
}

async function startDateField(auth: JiraAuth): Promise<{ meta: InstanceMeta; startField: string }> {
  const meta = await instanceMeta(auth);
  // Sem o campo, toda história em andamento pareceria sem início. Melhor dizer
  // que não dá para checar do que acusar a lista inteira.
  if (!meta.startField) throw new Error('campo "Start date" não encontrado no Jira');
  return { meta, startField: meta.startField };
}

// Histórias e épicos sob a responsabilidade de quem está sendo olhado que ainda pedem atenção:
// o que está aberto e o que mudou no último mês. Ser só o relator não basta — corrigir o
// preenchimento é trabalho de quem responde pela issue. Sem o recorte de tempo, todo o
// histórico concluído entraria só para ser conferido.
const problemScope = (subject: JiraSubject) => {
  const userStr = jqlUser(subject);
  return `assignee = ${userStr} AND ` +
    '(statusCategory != Done OR updated >= -30d) ORDER BY updated DESC';
};

// Arquivar é tirar do trabalho, não concluir: a issue arquivada não tem mais
// o que ser corrigido. O corte é pelo nome do status, feito aqui e não na
// JQL — `status != "Arquivado"` é recusado com erro onde o status não existe,
// e derrubaria a aba inteira nessas instâncias.
const ARCHIVED_STATUS_NAMES = ['arquivado', 'archived'];

const isArchived = (issue: JiraItem) =>
  ARCHIVED_STATUS_NAMES.includes(issue.status.trim().toLowerCase());

// Chaves por consulta de filhas: mantém a JQL de tamanho previsível.
const EPIC_CHUNK = 50;

/** Histórias e épicos com defeito de preenchimento. São duas idas ao
 *  Jira além da descoberta do campo, e não uma por épico: as filhas de todos
 *  os épicos vêm juntas, por `parent in (...)`. */
export async function fetchProblems(conn: Connection, subject = ME): Promise<JiraProblemItem[]> {
  const auth = jiraAuth(conn);
  const { meta, startField } = await startDateField(auth);

  const raw = await searchAll(auth, problemScope(subject), meta, [startField]);
  const scope: JiraAuditIssue[] = raw
    .map((issue) => {
      const fields = (issue.fields ?? {}) as Record<string, unknown>;
      const text = (value: unknown) => (typeof value === 'string' ? value : '');
      return {
        ...toJiraItem(issue, auth.baseUrl, 'assignee'),
        startDate: text(fields[startField]),
      };
    })
    .filter((issue) => !isArchived(issue));

  // As chaves vêm do próprio Jira, mas entram numa JQL: a mesma validação da
  // lista de acompanhamento vale aqui.
  const epicKeys = scope.filter(isEpic).map((i) => i.key).filter(isJiraKey);
  const chunks: string[][] = [];
  for (let i = 0; i < epicKeys.length; i += EPIC_CHUNK) chunks.push(epicKeys.slice(i, i + EPIC_CHUNK));

  const children = (
    await Promise.all(
      chunks.map((keys) =>
        searchAll(auth, `parent in (${keys.map((k) => `"${k}"`).join(', ')})`, meta),
      ),
    )
  )
    .flat()
    .map((issue) => toJiraItem(issue, auth.baseUrl, 'assignee'));

  return findProblems(scope, children);
}

interface ChangelogPage {
  values?: {
    created?: string;
    items?: { fieldId?: string; field?: string; to?: string | null }[];
  }[];
  isLast?: boolean;
}

interface JiraStatusEntry {
  id?: string;
  statusCategory?: { key?: string | null } | null;
}

// Um histórico de issue raramente passa de uma página; o teto existe para a
// leitura terminar mesmo diante de uma issue com milhares de alterações.
const CHANGELOG_PAGES = 10;

/** De onde veio a data sugerida. A preferida é a passagem por andamento; sem
 *  ela, o que o histórico tiver de mais próximo do começo do trabalho. */
export type StartDateBasis = 'started' | 'finished' | 'created';

export interface StartDateSuggestion {
  date: string;
  basis: StartDateBasis;
}

interface IssueCreated {
  fields?: { created?: string | null; status?: { statusCategory?: { key?: string | null } | null } | null } | null;
}

/** O dia em que o trabalho na issue começou, pelo histórico. O status de
 *  destino é julgado pela categoria, não pelo nome: "Em andamento" e "Code
 *  Review PR" são o mesmo começo de trabalho.
 *
 *  Muita história vai de Backlog direto para Concluído, sem passar por
 *  andamento. Nesse caso o melhor que o histórico diz é o dia em que ela saiu
 *  do Backlog. E a issue criada já fora do Backlog não tem transição nenhuma:
 *  o começo é o dia da criação. Nulo só quando nada disso existe.
 *
 *  O dia é o do horário gravado pelo Jira, que já vem no fuso do perfil. */
export async function suggestStartDate(conn: Connection, key: string): Promise<StartDateSuggestion | null> {
  if (!isJiraKey(key)) throw new Error('chave inválida');
  const auth = jiraAuth(conn);
  const issuePath = `/rest/api/3/issue/${encodeURIComponent(key)}`;

  const [statuses, issue] = await Promise.all([
    request(auth, '/rest/api/3/status', undefined) as Promise<JiraStatusEntry[]>,
    request(auth, `${issuePath}?fields=created,status`, undefined) as Promise<IssueCreated>,
  ]);
  const categoryOf = new Map(
    (Array.isArray(statuses) ? statuses : []).flatMap((st) =>
      st.id ? [[st.id, toCategory(st.statusCategory?.key)] as [string, JiraStatusCategory]] : [],
    ),
  );

  const entered: Record<'indeterminate' | 'done', string[]> = { indeterminate: [], done: [] };
  let statusChanges = 0;
  for (let page = 0; page < CHANGELOG_PAGES; page++) {
    const path = `${issuePath}/changelog?startAt=${page * PAGE_SIZE}&maxResults=${PAGE_SIZE}`;
    const data = (await request(auth, path, undefined)) as ChangelogPage;
    for (const entry of data.values ?? []) {
      for (const item of entry.items ?? []) {
        if ((item.fieldId ?? item.field) !== 'status' || !entry.created) continue;
        statusChanges += 1;
        const category = item.to ? categoryOf.get(item.to) : undefined;
        if (category === 'indeterminate' || category === 'done') entered[category].push(entry.created);
      }
    }
    if (data.isLast !== false) break;
  }

  const earliest = (moments: string[]) =>
    moments.sort((a, b) => Date.parse(a) - Date.parse(b))[0]?.slice(0, 10) ?? null;

  const started = earliest(entered.indeterminate);
  if (started) return { date: started, basis: 'started' };
  const finished = earliest(entered.done);
  if (finished) return { date: finished, basis: 'finished' };

  const created = issue.fields?.created;
  const leftBacklog = toCategory(issue.fields?.status?.statusCategory?.key) !== 'new';
  if (statusChanges === 0 && leftBacklog && created) return { date: created.slice(0, 10), basis: 'created' };
  return null;
}

/** Grava a data de início. A data chega da tela, então é conferida aqui: só
 *  um dia que existe no calendário vai para o Jira. */
export async function setStartDate(conn: Connection, key: string, date: string): Promise<void> {
  if (!isJiraKey(key)) throw new Error('chave inválida');
  if (!isCalendarDate(date)) throw new Error('data inválida — use AAAA-MM-DD');
  const auth = jiraAuth(conn);
  const { startField } = await startDateField(auth);
  await request(auth, `/rest/api/3/issue/${encodeURIComponent(key)}`, { fields: { [startField]: date } }, 'PUT');
}

export function isCalendarDate(value: unknown): value is string {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const parsed = new Date(`${value}T00:00:00Z`);
  return !Number.isNaN(parsed.getTime()) && parsed.toISOString().slice(0, 10) === value;
}

const EPIC_LEVEL = 1;

/** Os épicos abertos de um projeto, para escolher o pai da história. O tipo
 *  vai pelo nome na JQL, que é o nome de sistema nesta instância; o degrau da
 *  hierarquia confere o resultado, para não oferecer como épico o que não é. */
export async function fetchOpenEpics(conn: Connection, project: string): Promise<JiraItem[]> {
  if (!isJiraProjectKey(project)) throw new Error('projeto inválido');
  const auth = jiraAuth(conn);
  const raw = await search(
    auth,
    `project = "${project}" AND issuetype = Epic AND statusCategory != Done ORDER BY updated DESC`,
  );
  return raw
    .map((issue) => toJiraItem(issue, auth.baseUrl, 'assignee'))
    .filter((issue) => issue.hierarchyLevel === EPIC_LEVEL);
}

export function isJiraProjectKey(value: unknown): value is string {
  return typeof value === 'string' && /^[A-Z][A-Z0-9_]{1,9}$/.test(value);
}

/** Põe a história sob o épico. O épico é lido antes de gravar: o pai precisa
 *  existir, ser um épico e ser do mesmo projeto — o Jira aceitaria um épico
 *  de outro projeto, e a história sumiria do quadro do time. */
export async function setEpic(conn: Connection, key: string, epicKey: string): Promise<void> {
  if (!isJiraKey(key) || !isJiraKey(epicKey)) throw new Error('chave inválida');
  const auth = jiraAuth(conn);
  const [epic] = await search(auth, `key = "${epicKey}"`);
  const item = epic ? toJiraItem(epic, auth.baseUrl, 'assignee') : null;
  if (!item || item.hierarchyLevel !== EPIC_LEVEL) throw new Error(`${epicKey} não é um épico`);
  if (item.project !== key.split('-')[0]) throw new Error(`${epicKey} é de outro projeto`);
  await request(auth, `/rest/api/3/issue/${encodeURIComponent(key)}`, { fields: { parent: { key: epicKey } } }, 'PUT');
}

export async function testConnection(conn: Connection): Promise<void> {
  await request(jiraAuth(conn), '/rest/api/3/myself', undefined);
}

interface JiraUserResponse {
  accountId?: string;
  accountType?: string;
  active?: boolean;
  displayName?: string;
}

export async function searchPeople(conn: Connection, query: string): Promise<JiraPerson[]> {
  const auth = jiraAuth(conn);
  const rawData = (await request(
    auth,
    `/rest/api/3/user/search?query=${encodeURIComponent(query)}&maxResults=10`,
    undefined
  ));
  const data = Array.isArray(rawData) ? (rawData as JiraUserResponse[]) : [];

  return data
    .filter(
      (u) =>
        u.accountType === 'atlassian' &&
        u.active !== false &&
        u.accountId &&
        isJiraAccountId(u.accountId)
    )
    .map((u) => ({
      accountId: u.accountId!,
      displayName: u.displayName ?? '',
    }));
}

export async function fetchPerson(conn: Connection, accountId: string): Promise<JiraPerson | null> {
  const auth = jiraAuth(conn);
  
  const response = await fetch(`${auth.baseUrl}/rest/api/3/user?accountId=${encodeURIComponent(accountId)}`, {
    method: 'GET',
    headers: {
      authorization: auth.header,
      accept: 'application/json',
    },
    signal: AbortSignal.timeout(TIMEOUT_MS),
  });

  if (response.status === 404) return null;
  if (response.status === 401) throw new Error('Jira recusou o e-mail ou o API token');
  if (response.status === 403) throw new Error('o API token do Jira não tem permissão para isso');
  if (!response.ok) {
    const text = await response.text().catch(() => '');
    throw new Error(`Jira respondeu ${response.status}${text ? `: ${text.slice(0, 200)}` : ''}`);
  }

  const data = (await response.json()) as JiraUserResponse;

  if (data.accountType !== 'atlassian' || !data.accountId) return null;
  
  return {
    accountId: data.accountId,
    displayName: data.displayName ?? '',
  };
}
