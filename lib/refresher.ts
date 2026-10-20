import type { AgendaCalendarRef, DashboardState, EmailEnvelope, MailboxRef, PanelResult } from '@/lib/types';
import * as imap from './integrations/imap';
import * as agendaSource from './integrations/agenda';
import * as jiraApi from './integrations/jiraApi';
import * as githubApi from './integrations/githubApi';
import { fetchTasks } from './tasks';
import { combineNotifications, getNotifications } from './notifications';
import { getPomodoroState } from './pomodoro';
import { warmBodyCache, pruneOldBodies } from './emailCache';
import { listPendingActions } from './email/pendingActions';
import { reconcileEnvelopes, confirmAgainstSnapshot } from './email/reconcile';
import { replayPendingActions } from './email/replay';
import { loadInbox } from './email/inbox';
import { listUsers } from './auth/users';
import { enabledModules, listConnections } from './vault/connections';
import { agendaDays, dashboardLayout, dashboardLayouts, jiraWatchedKeys, jiraFollowedPeople } from './preferences';
import type { Connection } from './vault/connections';
import { fetchSlack, SlackDigestError } from './integrations/slack/digest';
import type { JiraProblem, JiraProblemItem, SlackDigest } from '@/lib/types';
import { jiraKeysInPulls, withJira } from './pullJira';

const EMAIL_LIMIT = 30;

// Com o punhado de usuários da app, um ciclo leva segundos por usuário. Cinco
// minutos deixam folga larga para ele terminar antes do próximo tique, e são
// frequentes o bastante para a caixa não parecer parada.
const DEFAULT_REFRESH_SECONDS = 300;

/** O intervalo vem do ambiente, que é entrada não confiável: Number('lixo') é
 *  NaN, e setInterval com NaN dispara a cada milissegundo. */
export function refreshIntervalSeconds(raw: string | undefined): number {
  const seconds = Number(raw);
  return Number.isFinite(seconds) && seconds > 0 ? seconds : DEFAULT_REFRESH_SECONDS;
}
const JIRA_FILTER = 'both' as const;

/** Quem pediu o ciclo. O botão de atualizar quer tudo de agora; o relógio
 *  pode reaproveitar o que muda devagar. */
export type RefreshTrigger = 'user' | 'timer';

// A aba de problemas é a busca mais cara do ciclo — pagina o escopo inteiro e
// as filhas de todos os épicos — e o que ela aponta é defeito de
// preenchimento, que não surge a cada cinco minutos.
const PROBLEMS_TTL_MS = 30 * 60 * 1000;

/** Módulo desligado não é erro nem lista vazia: é ausência. O painel some da
 *  tela em vez de mostrar "nada por aqui" para quem nunca quis aquilo. */
const OFF: PanelResult<never> = { data: null, error: null };

export async function panel<T>(fn: () => Promise<T>): Promise<PanelResult<T>> {
  try {
    return { data: await fn(), error: null };
  } catch (err) {
    return { data: null, error: err instanceof Error ? err.message : String(err) };
  }
}

/** Junta o resultado de várias conexões do mesmo módulo. Uma caixa fora do ar
 *  não pode apagar as outras da tela, então o sucesso parcial devolve dados e
 *  erro ao mesmo tempo. */
async function mergeConnections<T>(
  connections: Connection[],
  fn: (conn: Connection) => Promise<T[]>,
): Promise<PanelResult<T[]>> {
  if (connections.length === 0) return { data: [], error: null };

  const settled = await Promise.allSettled(connections.map((conn) => fn(conn)));
  const data = settled.flatMap((r) => (r.status === 'fulfilled' ? r.value : []));
  const errors = settled
    .filter((r): r is PromiseRejectedResult => r.status === 'rejected')
    .map((r) => (r.reason instanceof Error ? r.reason.message : String(r.reason)));

  if (errors.length === 0) return { data, error: null };
  if (data.length === 0) return { data: null, error: errors.join('; ') };
  return { data, error: errors.join('; ') };
}

async function slackPanel(connection: Connection): Promise<PanelResult<SlackDigest>> {
  try {
    return { data: await fetchSlack(connection), error: null };
  } catch (error) {
    if (error instanceof SlackDigestError) return { data: error.digest, error: error.message };
    return { data: null, error: error instanceof Error ? error.message : String(error) };
  }
}

type Patch = (state: DashboardState) => DashboardState;

interface RefresherState {
  caches: Map<string, DashboardState>;
  emVoo: Map<symbol, { userId: string; patches: Patch[] }>;
  refreshesEmCurso: Map<string, Promise<DashboardState>>;
  timer: ReturnType<typeof setInterval> | null;
  /** A última aba de problemas buscada, por usuário e conexão. */
  problems: Map<string, { at: number; result: PanelResult<JiraProblemItem[]> }>;
  cicloEmCurso: boolean;
  proximoTique: number | null;
}

// O build de produção empacota este módulo mais de uma vez: o instrumentation,
// que roda o ciclo de fundo, carrega uma cópia e as rotas carregam outra.
// Estado guardado só no módulo ficava preso na cópia do ciclo — a tela nunca
// recebia o que o ciclo buscava nem o horário do próximo tique. Guardado no
// processo, todas as cópias leem e escrevem o mesmo estado.
const STATE_KEY = Symbol.for('daily-web.refresher');
const shared: RefresherState = ((globalThis as Record<symbol, unknown>)[STATE_KEY] ??= {
  caches: new Map(),
  emVoo: new Map(),
  refreshesEmCurso: new Map(),
  timer: null,
  problems: new Map(),
  cicloEmCurso: false,
  proximoTique: null,
} satisfies RefresherState) as RefresherState;
// Um processo que já tinha o estado de antes deste campo continua de pé até o
// próximo reinício.
shared.problems ??= new Map();

// Um cache por usuário. Era uma variável só de módulo, o que fazia todo mundo
// que abrisse o painel ver os dados de quem tivesse atualizado por último.
const caches = shared.caches;

// Cada refresh em andamento tem a sua lista. O snapshot é montado a partir de
// leituras feitas no começo do ciclo, então uma ação do usuário no meio dele
// não aparece no resultado: gravar o snapshot cru desfazia a ação — o e-mail
// apagado voltava para a tela até o ciclo seguinte. As ações do intervalo são
// reaplicadas sobre o snapshot antes de ele virar cache.
const emVoo = shared.emVoo;

// Um ciclo comporta poucas ações. Se passar disto, o snapshot é velho demais
// para ser reconciliado e o cache atual — que já reflete tudo — fica de pé.
const MAX_PATCHES_EM_VOO = 500;

// Um refresh por usuário de cada vez. O botão "atualizar" e o ciclo do timer
// disputavam as mesmas caixas: cada rodada extra abre um login novo em cada
// conta e o servidor recusa os seguintes, o que fazia o painel voltar com
// erro — e o clique repetido, que é a reação natural, só piorava a disputa.
// Quem chega no meio de um refresh recebe o resultado do que já está em curso.
const refreshesEmCurso = shared.refreshesEmCurso;

export function refreshAll(userId: string, trigger: RefreshTrigger = 'timer'): Promise<DashboardState> {
  const emCurso = refreshesEmCurso.get(userId);
  if (emCurso) return emCurso;

  const promessa = buildFresh(userId, trigger).finally(() => refreshesEmCurso.delete(userId));
  refreshesEmCurso.set(userId, promessa);
  return promessa;
}

async function buildFresh(userId: string, trigger: RefreshTrigger): Promise<DashboardState> {
  const ciclo = Symbol('refresh');
  emVoo.set(ciclo, { userId, patches: [] });
  const inicio = Date.now();
  try {
    const state = await buildState(userId, ciclo, trigger);
    logCycle(userId, inicio, state);
    return state;
  } finally {
    emVoo.delete(ciclo);
  }
}

/** O painel só mostra o resultado; sem isto, um ciclo que degrada — lento ou
 *  com uma fonte fora do ar — só aparece como tela parada. Uma linha por
 *  ciclo, nunca por item. */
function logCycle(userId: string, inicio: number, state: DashboardState): void {
  const panels: Record<string, PanelResult<unknown>> = {
    email: state.email,
    agenda: state.agenda,
    pulls: state.pulls,
    jira: state.jira,
    tasks: state.tasks,
    slack: state.slack,
  };
  const errors = Object.entries(panels)
    .filter(([, panel]) => panel.error)
    .map(([name, panel]) => `${name}: ${panel.error}`);

  console.info(
    'refresh.cycle',
    JSON.stringify({ userId, ms: Date.now() - inicio, errors }),
  );
}

const problemsKey = (userId: string, connection: Connection) => `${userId}:${connection.id}`;

/** A aba de problemas do cache enquanto vale. Resultado com erro não é
 *  guardado: a falha é tentada de novo no ciclo seguinte. */
async function jiraProblemsOf(
  userId: string,
  connection: Connection,
  trigger: RefreshTrigger,
): Promise<PanelResult<JiraProblemItem[]>> {
  const key = problemsKey(userId, connection);
  const cached = shared.problems.get(key);
  if (trigger === 'timer' && cached && Date.now() - cached.at < PROBLEMS_TTL_MS) return cached.result;

  const result = await panel(() => jiraApi.fetchProblems(connection));
  if (result.error) shared.problems.delete(key);
  else shared.problems.set(key, { at: Date.now(), result });
  return result;
}

/** Tira um problema corrigido da aba, no estado da tela e no cache da busca.
 *  Sem o segundo, a correção voltaria a aparecer no próximo ciclo, que
 *  reaproveita a busca por até meia hora. */
export function resolveJiraProblem(userId: string, key: string, problems: JiraProblem[]): void {
  const semEste = (result: PanelResult<JiraProblemItem[]>): PanelResult<JiraProblemItem[]> =>
    result.data === null
      ? result
      : {
          ...result,
          data: result.data
            .map((item) =>
              item.key === key
                ? { ...item, problems: item.problems.filter((p) => !problems.includes(p)) }
                : item,
            )
            .filter((item) => item.problems.length > 0),
        };

  for (const [cacheKey, entry] of shared.problems) {
    if (cacheKey.startsWith(`${userId}:`)) shared.problems.set(cacheKey, { ...entry, result: semEste(entry.result) });
  }
  patchCachedState(userId, (state) => ({ ...state, jiraProblems: semEste(state.jiraProblems) }));
}

async function buildState(userId: string, ciclo: symbol, trigger: RefreshTrigger): Promise<DashboardState> {
  const modules = enabledModules(userId);
  const has = (id: string) => modules.includes(id as never);

  const mailConnections = has('email') ? listConnections(userId, 'email') : [];
  const calendars = has('agenda') ? listConnections(userId, 'agenda') : [];
  const days = agendaDays(userId);
  const jiraConnection = has('jira') ? (listConnections(userId, 'jira')[0] ?? null) : null;
  const pullsConnection = has('pulls') ? (listConnections(userId, 'pulls')[0] ?? null) : null;
  const slackConnection = has('slack') ? (listConnections(userId, 'slack')[0] ?? null) : null;

  const watched = jiraConnection ? jiraWatchedKeys(userId) : [];

  // O retrato do e-mail vale para este instante. Uma ação escrita depois
  // daqui não pode ser confirmada por ele: ele é anterior à escrita.
  const retratoIniciadoEm = new Date();

  const [
    email,
    agenda,
    pulls,
    reviewRequests,
    jira,
    tasks,
    mentions,
    jiraWatched,
    jiraDelivered,
    jiraApproved,
    jiraProblems,
    slack,
  ] =
    await Promise.all([
      has('email')
        ? mergeConnections(mailConnections, (c) => loadInbox(userId, c, EMAIL_LIMIT))
        : OFF,
      has('agenda')
        ? mergeConnections(calendars, (c) => agendaSource.fetchAgenda(c, undefined, days))
        : OFF,
      pullsConnection ? panel(() => githubApi.fetchPulls(pullsConnection)) : OFF,
      // Uma busca por ciclo, independente de quantos repositórios são
      // acompanhados — ela varre tudo o que o token enxerga.
      pullsConnection ? panel(() => githubApi.fetchReviewRequests(pullsConnection)) : OFF,
      jiraConnection ? panel(() => jiraApi.fetchIssues(jiraConnection, JIRA_FILTER)) : OFF,
      has('tasks') ? panel(() => fetchTasks(userId)) : OFF,
      jiraConnection ? panel(() => getNotifications(userId, jiraConnection)) : OFF,
      jiraConnection && watched.length > 0
        ? panel(() => jiraApi.fetchByKeys(jiraConnection, watched))
        : ({ data: [], error: null } as PanelResult<never[]>),
      jiraConnection ? panel(() => jiraApi.fetchDelivered(jiraConnection)) : OFF,
      jiraConnection ? panel(() => jiraApi.fetchApproved(jiraConnection)) : OFF,
      jiraConnection ? jiraProblemsOf(userId, jiraConnection, trigger) : OFF,
      slackConnection ? slackPanel(slackConnection) : OFF,
    ]);

  // A subida da hierarquia depende do que as buscas acima trouxeram, então é
  // uma segunda rodada. É uma ida por nível para as quatro listas juntas, e
  // não uma por lista. Falhar aqui não derruba o painel: sem os ancestrais a
  // árvore só começa mais embaixo.
  const jiraAncestors = jiraConnection
    ? await jiraApi
        .fetchAncestors(jiraConnection, [
          ...(jira.data ?? []),
          ...(jiraWatched.data ?? []),
          ...(jiraDelivered.data ?? []),
          ...(jiraApproved.data ?? []),
        ])
        .catch(() => [])
    : [];

  // Os cards citados nos títulos dos PRs, numa busca só para as duas listas.
  // Como os ancestrais, é uma segunda rodada que não derruba nada: sem ela o
  // PR só não mostra o status do card.
  const pullsJira = jiraConnection
    ? await jiraApi
        .fetchByKeys(
          jiraConnection,
          jiraKeysInPulls([...(pulls.data?.items ?? []), ...(reviewRequests.data?.items ?? [])]),
        )
        .catch(() => [])
    : [];
  const pullsComJira = pulls.data
    ? { ...pulls, data: { ...pulls.data, items: withJira(pulls.data.items, pullsJira) } }
    : pulls;
  const reviewsComJira = reviewRequests.data
    ? { ...reviewRequests, data: { ...reviewRequests.data, items: withJira(reviewRequests.data.items, pullsJira) } }
    : reviewRequests;

  // O que o usuário pediu vence o retrato do servidor. As ações que o retrato
  // já reflete saem do caminho aqui; as demais são sobrepostas a ele.
  const emailReconciliado = reconcileEmail(userId, email, retratoIniciadoEm);

  // O sino soma menção do Jira, pull request aberto e e-mail não lido. As
  // três já foram buscadas acima: o aviso é derivado, não é uma quarta ida.
  const notifications = combineNotifications(userId, mentions, pulls, emailReconciliado, slack);

  const mailboxes: MailboxRef[] = mailConnections.map((c) => ({ id: c.id, label: c.label }));
  const agendaCalendars: AgendaCalendarRef[] = calendars
    .filter(agendaSource.isGoogle)
    .map((c) => ({
      id: c.id,
      label: c.label,
      account: c.values.account ?? '',
      canWrite: agendaSource.canWriteEvents(c),
    }));

  const state: DashboardState = {
    updatedAt: new Date().toISOString(),
    modules,
    mailboxes,
    agendaDays: days,
    agendaCalendars,
    layout: dashboardLayout(userId),
    layouts: dashboardLayouts(userId),
    email: emailReconciliado,
    agenda,
    pulls: pullsComJira,
    reviewRequests: reviewsComJira,
    jira,
    jiraWatched,
    jiraFollowedPeople: jiraConnection ? jiraFollowedPeople(userId) : [],
    jiraDelivered,
    jiraApproved,
    jiraProblems,
    jiraAncestors,
    tasks,
    slack,
    notifications,
    pomodoro: getPomodoroState(userId),
    nextRefreshAt: nextRefreshAt(),
  };
  const pendentes = emVoo.get(ciclo)?.patches ?? [];
  const atual = caches.get(userId);
  const reconciliado =
    pendentes.length > MAX_PATCHES_EM_VOO && atual
      ? atual
      : pendentes.reduce((acc, patch) => patch(acc), state);
  caches.set(userId, reconciliado);

  // Leva ao servidor o que ainda não chegou. Em segundo plano e pela fila da
  // conta: uma escrita que falhou volta a ser tentada, sem segurar a resposta.
  if (mailConnections.length > 0) {
    void replayPendingActions(userId, mailConnections).catch(() => {
      // Cada ação já guarda o próprio erro e a própria contagem de tentativas.
    });
  }

  // Baixa os corpos que ainda faltam em segundo plano, sem segurar a
  // resposta: quando o usuário clicar, o e-mail já estará no banco.
  if (email.data && email.data.length > 0) {
    void warmBodyCache(userId, mailConnections, email.data).catch(() => {
      // Aquecimento é oportunista: uma falha aqui não afeta o painel.
    });
  }

  return reconciliado;
}

/**
 * Sobrepõe as ações pendentes ao que veio do servidor e confirma as que ele já
 * reflete. `snapshotStartedAt` nulo é uma releitura do cache, não um retrato
 * novo: aí não há o que confirmar, só o que sobrepor.
 */
function reconcileEmail(
  userId: string,
  email: PanelResult<EmailEnvelope[]>,
  snapshotStartedAt: Date | null,
): PanelResult<EmailEnvelope[]> {
  if (!email.data) return email;
  const pendentes = listPendingActions(userId);
  if (pendentes.length === 0) return email;

  if (snapshotStartedAt) {
    confirmAgainstSnapshot(userId, email.data, pendentes, snapshotStartedAt);
    return { ...email, data: reconcileEnvelopes(email.data, listPendingActions(userId)) };
  }
  return { ...email, data: reconcileEnvelopes(email.data, pendentes) };
}

export function getCachedState(userId: string): DashboardState | null {
  const cache = caches.get(userId);
  if (!cache) return null;
  return {
    ...cache,
    // Reconciliar na leitura, e não só na gravação, é o que faz a ação valer
    // mesmo quando ela foi pedida antes de existir cache para este usuário.
    email: reconcileEmail(userId, cache.email, null),
    pomodoro: getPomodoroState(userId),
    nextRefreshAt: nextRefreshAt(),
  };
}

export function dropCache(userId: string): void {
  caches.delete(userId);
}

/**
 * Corrige o cache logo depois de uma ação. Sem isto, o painel recarrega e
 * recebe de volta o estado anterior — a ação parece não ter acontecido até o
 * próximo ciclo do refresher, que pode estar a minutos de distância.
 */
export function patchCachedState(
  userId: string,
  patch: (state: DashboardState) => DashboardState,
): void {
  // Registrado antes de aplicar: o refresh que já está lendo o servidor
  // terminará com um retrato anterior a esta ação e precisa reaplicá-la.
  for (const ciclo of emVoo.values()) {
    if (ciclo.userId === userId) ciclo.patches.push(patch);
  }
  const cache = caches.get(userId);
  if (!cache) return;
  caches.set(userId, patch(cache));
}

/** Recarrega só as tarefas. É barato no provedor local (SQLite) e, no
 *  mstodo, custa a mesma CLI que a ação já pagou — muito menos do que refazer
 *  e-mail, agenda, Jira e GitHub por causa de um checkbox. */
export async function refreshTasks(userId: string): Promise<void> {
  const cache = caches.get(userId);
  if (!cache) return;
  const tasks = await panel(() => fetchTasks(userId));
  caches.set(userId, { ...cache, tasks });
}

// Atualiza todo mundo que está cadastrado. Com o punhado de usuários que esta
// app comporta isso é mais simples — e mais previsível — do que rastrear quem
// tem sessão aberta.
async function refreshEveryone(): Promise<void> {
  for (const user of listUsers()) {
    try {
      await refreshAll(user.id);
    } catch {
      // A falha de um usuário não pode interromper o ciclo dos outros.
    }
  }
  pruneOldBodies();
}

// Horário do próximo tique, para a tela mostrar quanto falta. Nulo enquanto o
// ciclo não foi iniciado — nos testes e antes do boot terminar.
function nextRefreshAt(): string | null {
  return shared.proximoTique === null ? null : new Date(shared.proximoTique).toISOString();
}

export function startRefreshLoop(intervalSeconds: number): void {
  if (shared.timer) return;
  const intervalMs = intervalSeconds * 1000;

  // Um ciclo que passa do intervalo faria o próximo começar por cima dele,
  // dobrando as conexões abertas em cada caixa a cada tique. Enquanto o anterior
  // não termina, o tique é descartado — não enfileirado, que só adiaria a mesma
  // sobreposição.
  const tick = async () => {
    if (shared.cicloEmCurso) return;
    shared.cicloEmCurso = true;
    try {
      await refreshEveryone();
    } finally {
      shared.cicloEmCurso = false;
    }
  };

  shared.proximoTique = Date.now() + intervalMs;
  void tick();
  shared.timer = setInterval(() => {
    shared.proximoTique = Date.now() + intervalMs;
    void tick();
  }, intervalMs);
}

export function resetCachesForTests(): void {
  caches.clear();
  emVoo.clear();
  refreshesEmCurso.clear();
  shared.problems.clear();
  shared.cicloEmCurso = false;
  shared.proximoTique = null;
  if (shared.timer) clearInterval(shared.timer);
  shared.timer = null;
}
