// Uma conta era 'work' ou 'personal' — dois valores fixos, os do dono da
// máquina. Agora é o id de uma conexão cadastrada, então o tipo é o rótulo que
// acompanha o dado, não uma enumeração no código.
export type Account = string;

export interface EmailEnvelope {
  id: string;
  account: Account;
  accountLabel: string;
  from: string;
  subject: string;
  unread: boolean;
  date: string;
  messageId: string;
  /** Message-Ids que esta mensagem responde, do mais antigo ao mais recente:
   *  o header References acrescido do In-Reply-To. É o que liga a conversa. */
  references: string[];
  /** Etiquetas aplicadas à mensagem, como o servidor as reporta. Fica vazio
   *  para as contas cujo servidor não reporta etiqueta nenhuma — a lista trata
   *  isso como "sem etiqueta", não como erro. */
  labels: string[];
  /** De qual caixa a mensagem veio. O uid do IMAP é por caixa: o mesmo número
   *  aponta para mensagens diferentes na entrada e nos enviados, então nenhuma
   *  operação pode usar o id sem saber de onde ele é. */
  mailbox: MailboxKind;
  /** Caminho real da pasta no servidor ("INBOX", "[Gmail]/Importante"). O uid
   *  só identifica dentro dela. */
  folder: string;
  /** Erro da última ação pedida para esta mensagem, quando ela falhou em
   *  definitivo. A mensagem continua na caixa: o erro é o que explica por quê. */
  actionError?: string;
}

/** As duas caixas que a conversa precisa: o que chegou e o que você mandou. */
export type MailboxKind = 'inbox' | 'sent';

/** Uma pasta do servidor, como a árvore a mostra. */
export interface MailboxNode {
  path: string;
  name: string;
  /** Separador de níveis do servidor ("/" ou "."), que monta a hierarquia. */
  delimiter: string;
  parent: string | null;
  /** Uso especial declarado pelo servidor (`\\Sent`, `\\Trash`). O nome muda
   *  por provedor e idioma; a flag não. */
  specialUse: string | null;
  total: number;
  unread: number;
}

/** Uma conversa: as mensagens que se referenciam entre si, da mais antiga
 *  para a mais recente. */
export interface EmailThread {
  /** Chave estável da conversa — a mensagem raiz identifica o conjunto. */
  id: string;
  /** Assunto sem os prefixos de resposta e encaminhamento. */
  subject: string;
  messages: EmailEnvelope[];
  /** Quem escreveu, na ordem em que apareceu, sem repetir. */
  participants: string[];
  unreadCount: number;
  /** Data da mensagem mais recente: é por ela que a conversa se ordena. */
  lastDate: string;
}

export interface AgendaItem {
  account: Account;
  accountLabel: string;
  date: string;
  time: string;
  title: string;
}

export interface AgendaCalendarRef {
  id: string;
  label: string;
  account: string;
  canWrite: boolean;
}

/** Last-commit check rollup. `none`: the commit has no checks at all. */
export type PullCi = 'passing' | 'failing' | 'running' | 'none' | 'unknown';

/** From GitHub's reviewDecision. `none`: the repo requires no review. */
export type PullReview = 'approved' | 'changes-requested' | 'pending' | 'none' | 'unknown';

/** `unknown` is GitHub's "not computed yet" (mergeability is computed
 *  lazily), never a conflict. `none` is only used for issues. */
export type PullMerge = 'clean' | 'conflict' | 'blocked' | 'unknown' | 'none';

/** A reviewer's latest review. `unknown`: a state GitHub added later. */
export type PullReviewerState = 'approved' | 'changes-requested' | 'commented' | 'dismissed' | 'pending' | 'unknown';

export interface PullReviewer {
  login: string;
  state: PullReviewerState;
}

export interface PullFailedCheck {
  name: string;
  url: string | null;
}

export interface PullSize {
  additions: number;
  deletions: number;
  files: number;
}

/** An open pull request or issue. Issues share the list, so every PR-only
 *  field has a fixed "not applicable" value on them: `ci: 'none'`,
 *  `review: 'none'`, `merge: 'none'`, empty `failedChecks` and
 *  `pendingReviewers`, and `null` size/headRef/baseRef/headSha. */
export interface PullRequestItem {
  /** GraphQL node id, used by writes. */
  id: string;
  repo: string;
  number: number;
  title: string;
  url: string;
  /** Empty when the author account was deleted. */
  author: string;
  draft: boolean;
  /** Pediram a sua revisão. */
  awaitingYou: boolean;
  /** Você abriu este PR. */
  mine: boolean;
  /** Separa pull request de issue: o GitHub devolve os dois na mesma lista. */
  isPullRequest: boolean;
  updatedAt: string;
  createdAt: string;
  ci: PullCi;
  /** At most five. */
  failedChecks: PullFailedCheck[];
  review: PullReview;
  /** User logins, and teams as `team:<slug>`. */
  pendingReviewers: string[];
  /** Latest review of each reviewer who already reviewed, as GitHub lists them. */
  reviewers: PullReviewer[];
  /** When the latest review request was made. Only the review-requests search
   *  asks for it; `null` everywhere else. */
  reviewRequestedAt: string | null;
  merge: PullMerge;
  size: PullSize | null;
  headRef: string | null;
  baseRef: string | null;
  headSha: string | null;
  /** Os cards do Jira citados no título, com o status de agora. Vazio quando
   *  o título não cita nenhum ou o Jira não está conectado. */
  jira?: PullJiraRef[];
}

export interface PullJiraRef {
  key: string;
  url: string;
  status: string;
  statusCategory: JiraStatusCategory;
}

/** As revisões pedidas a você, de qualquer repositório que o token enxergue.
 *  Vem da busca do GitHub, não da lista de repositórios acompanhados. */
export interface ReviewRequestsDigest {
  items: PullRequestItem[];
  /** A busca achou mais do que coube numa página. */
  truncated: boolean;
  /** Quantos o GitHub diz que existem, para a mensagem do corte. */
  total: number;
  /** Aviso de alcance do token, só quando a lista veio vazia. */
  scopeNote: string | null;
  /** Parts of the answer GitHub left out (a field it refused), not a failed search. */
  errors?: string[];
}

/** Open PRs authored by the user, in any repository the token sees. */
export interface MyPullsDigest {
  items: PullRequestItem[];
  truncated: boolean;
  total: number;
  /** Parts of the answer GitHub left out (a field it refused), not a failed search. */
  errors?: string[];
}

export interface DefaultBranchStatus {
  repo: string;
  branch: string;
  ci: PullCi;
}

/** A tracked repo with more open PRs or issues than one page holds. */
export interface PullsTruncation {
  repo: string;
  kind: 'pulls' | 'issues';
  shown: number;
  total: number;
}

export interface PullsDigest {
  items: PullRequestItem[];
  /** Repositórios que falharam sozinhos, sem derrubar os outros. */
  errors: string[];
  /** One per tracked repo that has a default branch. */
  defaultBranches: DefaultBranchStatus[];
  truncated: PullsTruncation[];
}

export type JiraRole = 'assignee' | 'reporter' | 'both';

export interface JiraParent {
  key: string;
  summary: string;
}

/** As três situações do Jira, normalizadas. O nome do status é livre e varia
 *  por projeto e por idioma; a categoria não. */
export type JiraStatusCategory = 'new' | 'indeterminate' | 'done';

/** A bandeira de impedimento do Jira, o campo "Flagged". */
export type JiraFlag = 'impediment' | 'none';

export interface JiraPriority {
  name: string;
  /** Posição na ordem da instância, 0 é a mais alta. Nula quando o Jira não
   *  informa a ordem: a prioridade aparece, mas não ordena. */
  rank: number | null;
}

export interface JiraItem {
  key: string;
  summary: string;
  status: string;
  statusCategory: JiraStatusCategory;
  project: string;
  url: string;
  parent: JiraParent | null;
  role: JiraRole;
  /** Aprovação é ortogonal ao papel: você pode ser o responsável pela issue e
   *  o aprovador dela ao mesmo tempo, então isto não cabe em `role`. */
  awaitingApproval: boolean;
  kind: string;
  subtask: boolean;
  /** O degrau do tipo na hierarquia do Jira: -1 subtarefa, 0 história, 1
   *  épico, e acima disso os níveis da instância (aqui 2 é iniciativa e 3 é
   *  objetivo). Nulo quando o Jira não informa. Diferente do nome do tipo,
   *  ele não muda por idioma nem por esquema de tipos do projeto. */
  hierarchyLevel: number | null;
  /** ISO da última alteração. É daqui que sai "parado há X dias". */
  updatedAt: string;
  /** AAAA-MM-DD, ou vazio quando a issue não tem prazo. */
  dueDate: string;
  priority: JiraPriority | null;
  flag: JiraFlag;
}

/** Uma issue com a marca do recorte de tempo. As listas de entregues e de
 *  aprovados cobrem sete dias; `today` diz quais delas caem no dia de hoje,
 *  que é o recorte padrão do painel. A marca vem do Jira, não de uma conta de
 *  data feita aqui. */
export interface JiraDatedItem extends JiraItem {
  today: boolean;
}

/** Os defeitos de preenchimento que a aba de problemas aponta. Uma issue pode
 *  ter mais de um ao mesmo tempo. */
export type JiraProblem =
  | 'story-in-progress-without-start'
  | 'story-done-without-start'
  | 'story-without-epic'
  | 'epic-without-stories'
  | 'epic-in-progress-without-active-story';

export interface JiraProblemItem extends JiraItem {
  /** Nunca vazia: a issue sem problema não entra na lista. */
  problems: JiraProblem[];
}

export interface SubTask {
  id: string;
  title: string;
  completed: boolean;
}

export type TaskPriority = 'low' | 'normal' | 'high';

/** The paper colours a board note can have. A fixed palette rather than any
 *  colour: every one is a token per theme, so its contrast with the note's ink
 *  is checked once, in tests, instead of left to chance. */
export type NotePaper = 'yellow' | 'pink' | 'blue' | 'green' | 'white' | 'grey';

export type PinColor = 'red' | 'blue' | 'yellow' | 'green';

export interface TodoTask {
  id: string;
  title: string;
  completed: boolean;
  due: string;
  priority: TaskPriority;
  time: string;
  recur: string;
  notes: string;
  subtasks: SubTask[];
  /** Marked "Fazendo" on the board. Not a provider field — Microsoft To Do
   *  has no "in progress" — so it is overlaid from this app's own database
   *  and is always false for a completed task. */
  doing: boolean;
  /** The paper and pin colour chosen for the task's note, or null for the
   *  automatic one (paper from priority and completion, pin varied without
   *  clashing). Overlaid from this app's database like `doing`. */
  paper: NotePaper | null;
  pin: PinColor | null;
}

/** A task as a provider returns it, before the board overlay is applied. */
export type ProviderTask = Omit<TodoTask, 'doing' | 'paper' | 'pin'>;

/** How the tasks panel is laid out: the grouped list, or the kanban board. */
export type TasksView = 'list' | 'board';

/** Uma aba do bloco de notas. Vive no servidor, então acompanha o usuário
 *  entre máquinas. */
export interface Note {
  id: string;
  title: string;
  body: string;
  position: number;
  updatedAt: string;
  /** A pasta onde a nota está, ou null quando está solta ("Sem pasta"). */
  folderId: string | null;
}

/** Uma pasta de notas. `parentId` null é uma pasta da raiz. */
export interface NoteFolder {
  id: string;
  name: string;
  parentId: string | null;
  position: number;
  updatedAt: string;
}

/** A mesma pasta já na hierarquia, como a barra lateral desenha. */
export interface NoteFolderNode extends NoteFolder {
  depth: number;
  children: NoteFolderNode[];
}

export interface SlackMessage {
  id: string;
  channel: string;
  author: string;
  text: string;
  date: string;
  url: string;
}

export interface SlackDigest {
  mentions: SlackMessage[];
  directs: SlackMessage[];
  team: string;
}

export type NotificationSource = 'jira_mention' | 'pull_request' | 'email' | 'slack';

export interface NotificationItem {
  id: string;
  source: NotificationSource;
  title: string;
  url: string;
  read: boolean;
  /** ISO do acontecimento que gerou o aviso. É por ela que o sino ordena:
   *  sem uma data comum, a lista sairia agrupada por fonte e o que acabou de
   *  chegar ficaria atrás do que é antigo. */
  date: string;
}

export type PomodoroPhase = 'focus' | 'rest';

export interface PomodoroState {
  enabled: boolean;
  phase: PomodoroPhase;
  running: boolean;
  remainingSeconds: number;
  focusMinutes: number;
  restMinutes: number;
  completedFocusCount: number;
}

export interface PanelResult<T> {
  data: T | null;
  error: string | null;
}

export interface MailboxRef {
  id: string;
  label: string;
}

export interface JiraPerson {
  accountId: string;
  displayName: string;
}

export interface JiraPersonView {
  jira: PanelResult<JiraItem[]>;
  delivered: PanelResult<JiraDatedItem[]>;
  approved: PanelResult<JiraDatedItem[]>;
  problems: PanelResult<JiraProblemItem[]>;
  /** O caminho até o objetivo das issues acima. Mesmo papel de
   *  `jiraAncestors` no estado do painel. */
  ancestors: JiraItem[];
}

export interface DashboardState {
  updatedAt: string;
  /** Módulos que este usuário ligou. O painel só desenha o que está aqui. */
  modules: string[];
  /** Caixas de e-mail do usuário, para os filtros e o envio de resposta. */
  mailboxes: MailboxRef[];
  /** Quantos dias a agenda cobre, contando hoje. Escolha de cada usuário. */
  agendaDays: number;
  agendaCalendars: AgendaCalendarRef[];
  /** Whether the tasks panel shows the list or the board. Each user's choice. */
  tasksView: TasksView;
  /** Disposição única, de antes de existir gravação por tamanho de tela.
   *  Vale enquanto `layouts` estiver vazio. */
  layout: { i: string; x: number; y: number; w: number; h: number }[];
  /** Disposições gravadas por tamanho de janela. O cliente escolhe a mais
   *  próxima da janela dele — o servidor não sabe o tamanho da tela de quem
   *  pediu o estado. */
  layouts: {
    width: number;
    height: number;
    layout: { i: string; x: number; y: number; w: number; h: number }[];
  }[];
  email: PanelResult<EmailEnvelope[]>;
  agenda: PanelResult<AgendaItem[]>;
  pulls: PanelResult<PullsDigest>;
  /** PRs esperando a revisão do usuário, inclusive fora dos repositórios
   *  acompanhados. */
  reviewRequests: PanelResult<ReviewRequestsDigest>;
  myPulls: PanelResult<MyPullsDigest>;
  jira: PanelResult<JiraItem[]>;
  /** Issues que o usuário escolheu acompanhar, mesmo não sendo dele. */
  jiraWatched: PanelResult<JiraItem[]>;
  /** Pessoas que o usuário escolheu acompanhar no Jira. */
  jiraFollowedPeople: JiraPerson[];
  /** Issues que o usuário encerrou nos últimos sete dias. Ficam de fora de
   *  `jira`, que só lista o que ainda está aberto. */
  jiraDelivered: PanelResult<JiraDatedItem[]>;
  /** Issues que o usuário aprovou nos últimos sete dias. */
  jiraApproved: PanelResult<JiraDatedItem[]>;
  /** Histórias e épicos seus com defeito de preenchimento. */
  jiraProblems: PanelResult<JiraProblemItem[]>;
  /** Os pais das issues acima, subindo até o objetivo. Não são do usuário:
   *  existem para a árvore do painel começar no topo da hierarquia, e não na
   *  história. Lista vazia quando a subida falha — o painel desenha sem ela. */
  jiraAncestors: JiraItem[];
  tasks: PanelResult<TodoTask[]>;
  slack: PanelResult<SlackDigest>;
  notifications: PanelResult<NotificationItem[]>;
  pomodoro: PomodoroState;
  /** Quando o ciclo de fundo roda de novo, em ISO. Nulo se ele não está
   *  agendado. */
  nextRefreshAt: string | null;
}
