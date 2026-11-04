# Contrato da API consumida pelo app

Levantado do código em 2026-11-04 (`app/api/**/route.ts`, `lib/`). **A fonte da
verdade é o código do servidor.** Se este documento divergir, vale o código, e
este arquivo deve ser corrigido. Os tipos ficam em `lib/types.ts`, e as linhas
citadas são dessa data.

## Regras gerais

- **Autenticação**: cookie `daily_web_session`, com valor
  `base64url(JSON{userId,user,issuedAt}).HMAC` (`lib/auth/session.ts`). Ele tem
  `httpOnly`, `secure` e `SameSite=Lax`, dura 30 dias, não é renovado e o
  servidor não tem revogação. O app guarda o valor e envia `Cookie:` à mão.
- **Sem sessão**: toda rota `/api/*`, exceto `/api/login`, responde
  `401 {"error":"não autenticado"}` (`middleware.ts:37-40`).
- **Formato de erro**:
  - Quase todas as rotas devolvem `{ "error": string }`.
  - Push, agentes (`lib/agents/http.ts`) e as v1 devolvem
    `{ "error": { "code", "message", "retry": "later"|"reconcile"|"never" } }`.
  - O 429 desse formato traz `Retry-After: 60`.
  - Falha de provedor externo devolve 502 `{error}`.
- **Origin**: as rotas que usam `browser(request,'write')` exigem `Origin` igual a
  `PUBLIC_ORIGIN` e recusam o header `Authorization` (400 `ambiguous_auth`). São
  as escritas de pulls, de agentes por sessão, de agent-access e de push. **O app
  envia `Origin` em toda escrita.**
- **Idempotência**: as escritas de pulls e **todas** as escritas de agentes por
  sessão (PATCH/DELETE de tarefa, transições e mensagens) exigem
  `Idempotency-Key` (8–160 caracteres) e `X-Request-Timestamp`; sem eles o
  servidor responde 400 (`validateMutation` em `lib/access/receipts.ts`). Uma
  nova tentativa da mesma ação deve reusar a chave (`Endpoint.idempotencyKey`).
- **Paginação** (agentes e v1): `{items, nextCursor, complete}`, cursor opaco.
- **JSON malformado** em `/api/tasks*` causa 500 (falta `catch` no servidor). O
  app nunca deve mandar corpo inválido.

## Sessão e conta

| Método e caminho | Corpo / query | Resposta 2xx | Erros relevantes |
|---|---|---|---|
| POST `/api/login` | `{username, password}` | `{ok:true}` + `Set-Cookie` | 401 credenciais; 429 (5 falhas/15 min por IP); 500 sem `SESSION_SECRET` |
| POST `/api/logout` | — | `{ok:true}` | — |
| GET `/api/me` | — | `{username, isAdmin, avatarUrl, fullName, email}` | — |
| PATCH `/api/me` | `{fullName, email}`. **Mandar os dois**: chave ausente limpa o campo | `{fullName, email}` | 400 `e-mail inválido` |
| POST `/api/me/password` | `{currentPassword, newPassword}` (≥ 8) | `{ok:true}` | 401 senha atual; 400 senha curta |
| POST `/api/me/avatar` | `{dataUrl}` png/jpeg/webp/gif em base64, ≤ 2 MB | `{avatarUrl}` | 400 |
| DELETE `/api/me/avatar` | — | `{avatarUrl:null}` | — |
| GET `/api/users` (admin) | — | `{users:[{id, username, isAdmin, createdAt}]}` | 403 `apenas admin` |
| POST `/api/users` (admin) | `{username, password, isAdmin?}` | 201 `{user}` | 400 duplicado ou senha curta |
| PATCH `/api/users/{username}` | `{password}` (o próprio usuário ou admin) | `{ok:true}` | 403, 404 |
| DELETE `/api/users/{username}` (admin) | — | `{ok:true}` | 400 a si mesmo ou último admin; 404 |

## Estado e preferências

| Método e caminho | Corpo / query | Resposta 2xx |
|---|---|---|
| GET `/api/state` | — | `DashboardState` (veja abaixo) |
| POST `/api/refresh` | — | `DashboardState`, após buscar em todas as integrações |
| GET `/api/preferences/layout-default` | — | `{layout}` (o app não usa) |
| PATCH `/api/preferences` | **uma** das chaves abaixo | depende da chave |

Chaves de `PATCH /api/preferences`, avaliadas nesta ordem (só a primeira presente vale):

| Chave | Valores | Resposta |
|---|---|---|
| `layout` (+ `viewport`) | o app não usa | `{layout, layouts}` |
| `agendaDays` | `1, 2, 3, 7, 14` | `DashboardState` completo |
| `tasksView` | `list`, `board` | `{tasksView}` |
| `homeView` | o app não usa | `{homeView}` |
| `appearance` | `{theme?: system\|light\|dark, density?: comfortable\|compact, backdrop?: mesh\|catppuccin\|dracula\|wezterm, width?: full\|limited}` | `{appearance}` |

### `DashboardState` (`lib/types.ts:418-472`)

`PanelResult<T> = { data: T | null, error: string | null }`. Um módulo desligado
vem como `{data:null, error:null}`.

| Chave | Tipo |
|---|---|
| `updatedAt` | ISO string |
| `modules` | `string[]` dos módulos ligados (`email, agenda, jira, pulls, tasks, notes, slack`) |
| `mailboxes` | `{id, label}[]` |
| `agendaDays` | number |
| `agendaCalendars` | `{id, label, account, canWrite}[]` |
| `tasksView` | `list \| board` |
| `homeView`, `layout`, `layouts` | ignorados pelo app |
| `email` | `PanelResult<EmailEnvelope[]>` |
| `agenda` | `PanelResult<AgendaItem[]>` |
| `pulls` | `PanelResult<PullsDigest>` |
| `reviewRequests` | `PanelResult<ReviewRequestsDigest>` |
| `myPulls` | `PanelResult<MyPullsDigest>` |
| `jira`, `jiraWatched` | `PanelResult<JiraItem[]>` |
| `jiraFollowedPeople` | `{accountId, displayName}[]` |
| `jiraDelivered`, `jiraApproved` | `PanelResult<JiraDatedItem[]>` |
| `jiraProblems` | `PanelResult<JiraProblemItem[]>` |
| `jiraAncestors` | `JiraItem[]` |
| `tasks` | `PanelResult<TodoTask[]>` |
| `slack` | `PanelResult<SlackDigest>` |
| `notifications` | `PanelResult<NotificationItem[]>` |
| `pomodoro` | `PomodoroState` |
| `nextRefreshAt` | ISO string ou `null` |

Tipos dos itens:

- **EmailEnvelope** (`types.ts:6-36`): `id, account, accountLabel, from, subject,
  unread, date, messageId, references[], labels[], mailbox: inbox|sent, folder, actionError?`
- **AgendaItem** (`:66-72`): `account, accountLabel, date, time, title`
- **PullsDigest** (`:197-204`): `items: PullRequestItem[], errors[], defaultBranches:{repo,branch,ci}[], truncated:{repo,kind,shown,total}[]`
- **PullRequestItem** (`:114-151`):
  - identificação: `id, repo, number, title, url, author, headRef, baseRef, headSha?`
  - situação: `draft, awaitingYou, mine, isPullRequest, updatedAt, createdAt, merge, size?{additions,deletions,files}`
  - CI: `ci: passing|failing|running|none|unknown, failedChecks[{name,url?}]`
  - revisão: `review, pendingReviewers[], reviewers[{login,state}], reviewRequestedAt?`
  - Jira: `jira?[{key,url,status,statusCategory}]`
- **ReviewRequestsDigest** (`:162-172`): `items, truncated, total, scopeNote?, errors?`. **MyPullsDigest** (`:175-181`): `items, truncated, total, errors?`
- **JiraItem** (`:227-252`):
  - identificação: `key, summary, project, url, kind, subtask, hierarchyLevel?, parent?{key,summary}`
  - situação: `status, statusCategory: new|indeterminate|done, role: assignee|reporter|both, awaitingApproval, flag: impediment|none`
  - datas e prioridade: `updatedAt, dueDate` (`AAAA-MM-DD` ou `""`), `priority?{name,rank?}`
- **JiraDatedItem** = `JiraItem + today`. **JiraProblemItem** = `JiraItem + problems[]`. Os problemas possíveis são:
  - `story-in-progress-without-start`
  - `story-done-without-start`
  - `story-without-epic`
  - `epic-without-stories`
  - `epic-in-progress-without-active-story`
- **TodoTask** (`:294-315`):
  - conteúdo: `id, title, completed, notes, subtasks[{id,title,completed}]`
  - agenda: `due, time, priority: low|normal|high, recur`
  - quadro: `doing`, `paper?` (`yellow|pink|blue|green|white|grey`), `pin?` (`red|blue|yellow|green`), `pinShape?` (`classic|ball|heart`)
- **SlackDigest** (`:361-365`): `mentions[], directs[], team`. A mensagem tem `id, channel, author, text, date, url`
- **NotificationItem** (`:369-379`): `id, source: jira_mention|pull_request|email|slack, title, url, read, date`
- **PomodoroState** (`:383-391`): `enabled, phase: focus|rest, running, remainingSeconds, focusMinutes, restMinutes, completedFocusCount`

## Tarefas

Formato do id de tarefa: 1–512 caracteres em `[A-Za-z0-9_\-=+/]`, sem começar por `-`.

| Método e caminho | Corpo | Resposta 2xx |
|---|---|---|
| POST `/api/tasks` | `{title, priority?, recur?: none\|daily\|weekly\|monthly, status?: todo\|doing, due?: texto livre ("amanhã 14:30")}`. Com repetição, `due` é obrigatório | `{id}` |
| PATCH `/api/tasks/{id}` | `{completed}` **ou** `{title?, priority?, recur?, due?}` | `{ok:true}` |
| DELETE `/api/tasks/{id}` | — | `{ok:true}` |
| PATCH `/api/tasks/{id}/board` | `{status?: todo\|doing, paper?, pin?, pinShape?}`. Concluir é pelo `PATCH completed` | `{ok:true[, paper, pin, pinShape]}` |
| POST `/api/tasks/{id}/subtasks` | `{title}` | `{ok:true}` |
| PATCH `/api/tasks/{id}/subtasks/{itemId}` | `{completed?, title?}` | `{ok:true}` |
| DELETE `/api/tasks/{id}/subtasks/{itemId}` | — | `{ok:true}` |

Erros de data de `due` vêm como texto pronto para exibir (`lib/dateParsing.ts`).

## Notas

| Método e caminho | Corpo | Resposta 2xx |
|---|---|---|
| GET `/api/notes` | — | `{notes: Note[], folders: NoteFolder[], sync: NotesSyncStatus}` |
| POST `/api/notes` | `{title?, folderId?}` | `{note}` (limite de 100 notas) |
| PUT `/api/notes` | `{ids: string[]}` (reordenar) | `{notes}` |
| PATCH `/api/notes/{id}` (ou POST, mesmo efeito) | `{title? ≤120, body? ≤100000, folderId?: string\|null}` | `{note}` |
| DELETE `/api/notes/{id}` | — | `{ok:true}` |
| GET `/api/notes/sync` | — | `{sync}` |
| GET/POST `/api/notes/folders` | POST `{name ≤60, parentId?}`; profundidade ≤ 5, até 100 pastas | `{folders}` / `{folder}` |
| PATCH `/api/notes/folders/{id}` | `{name?, parentId?}` | `{folder}` |
| DELETE `/api/notes/folders/{id}` | — (as notas vão para "Sem pasta") | `{ok:true}` |

- `Note`: `id, title, body, position, updatedAt, folderId?`
- `NoteFolder`: `id, name, parentId?, position, updatedAt`
- `NotesSyncStatus`: `connected, account, pending, lastError?, lastSyncedAt?`

## Pomodoro, agenda, notificações

| Método e caminho | Corpo | Resposta 2xx |
|---|---|---|
| POST `/api/pomodoro/start` · `/pause` · `/reset` | — | `PomodoroState`. O estado fica na memória do servidor |
| POST `/api/agenda/focus-blocks` | `{connectionId, item:{kind: task\|jira\|pull, title ≤200, ref ≤64, url? https}, start: ISO (de 5 min atrás a +60 d), minutes: 25\|50\|90\|120}` | 201 `{item: AgendaItem}`; 409 `{reconnect:true}` se faltar permissão de escrita |
| POST `/api/notifications/read` | `{id}` ou `{ids ≤200}`, no formato `source:externalId` | `{ok, marked}` |

## E-mail

| Método e caminho | Corpo / query | Resposta 2xx |
|---|---|---|
| GET `/api/email/mailboxes` | `account`, `sync=1` opcional | `{mailboxes, syncedAt, cached, added?, removed?}` |
| GET `/api/email/folders` | `account` | `{folders: string[]}` |
| GET `/api/email/messages` | `account`, `folder`, `limit` ≤ 100 | `{messages: EmailEnvelope[], uidvalidity, reindexed}` |
| GET `/api/email/{account}/{id}/body` | `box=inbox\|sent` | corpo dividido entre o texto novo e o citado, mais `cached` |
| POST `/api/email/batch` | `{targets:[{account,id}], action: read\|unread\|move\|tag\|delete, folder?, folderPath?}` | `{results:[{account,id,ok,error?}]}` |
| POST `/api/email/mark` | `{account, id, folder?, seen}` | `{ok:true}` |
| POST `/api/email/tag` | `{account, id, tag, folder?}` | `{ok:true}` |
| POST `/api/email/folder/read` | `{account, folder}` | `{ok:true}` |
| POST `/api/email/reply/draft` | `{account, id, from?, subject?, instruction?}` | `{text}`; 503 sem chave da IA |
| POST `/api/email/reply` | `{account, id, body}` | `{ok:true}` (envia por SMTP) |
| POST `/api/email/to-note` | `{account, id, folder?, folderId?}` | `{noteId, note?, repeated?}` |
| POST `/api/email/to-task` | `{account, id, folder?}` | `{taskId, repeated?}` |

As escritas entram numa fila de ações pendentes antes de ir ao IMAP. A falha
definitiva volta em `EmailEnvelope.actionError`.

## Jira

Todas as rotas exigem a conexão Jira, exceto `DELETE /api/jira/people`.

| Método e caminho | Corpo / query | Resposta 2xx |
|---|---|---|
| GET `/api/jira/epics` | `project` | `{epics:[{key,summary}]}` |
| GET / POST `/api/jira/issues/{key}/approvals` | POST `{approvalId, decision: approve\|decline}` | `{approvals:[{id,name}]}` / `{ok}` |
| POST `/api/jira/issues/{key}/comments` | `{body 1..5000}` | `{ok, comment:{id}}` |
| GET `/api/jira/issues/{key}/fields?options=priority` | — | `{priorities:[{id,name}], current}` |
| PUT `/api/jira/issues/{key}/fields` | `{change:"due", dueDate}` \| `{change:"priority", priorityId}` \| `{change:"assign-self"}` | `{ok}` |
| POST `/api/jira/issues/{key}/flag` | `{action:"flag", reason}` \| `{action:"unflag", note?}` | `{ok, warning?}` |
| PUT `/api/jira/issues/{key}/parent` | `{epic}` | `{ok}` |
| GET / PUT `/api/jira/issues/{key}/start-date` | PUT `{date}` | `{date, basis}` (ambos `null` sem sugestão) / `{ok}` |
| POST `/api/jira/issues/{key}/stories` | `{summary ≤255, description? ≤10000}` | `{ok, key, url}` |
| GET / POST `/api/jira/issues/{key}/transitions` | POST `{transitionId}` | `{transitions:[{id,name,to:{name,category},requires}]}` / `{ok}` |
| GET `/api/jira/people/search` | `q` (≥ 2) | `{people}` |
| POST / DELETE `/api/jira/people` | `{accountId}` | `{people}` |
| GET `/api/jira/people/{accountId}` | — | `{jira, delivered, approved, problems, ancestors}`, cada um `{data, error}` |
| GET / POST `/api/jira/problems/start-dates` | GET `keys=A-1,B-2` (≤ 50); POST `{items:[{key,date}]}` | `{suggestions}` / `{results, ok?}` (`ok` só quando alguma data foi gravada) |
| POST / DELETE `/api/jira/watch` | `{key}` | `DashboardState` |

## Pull requests

As escritas exigem `Origin`, `Idempotency-Key` e `X-Request-Timestamp`, e recusam `Authorization`.

| Método e caminho | Corpo / query | Resposta 2xx |
|---|---|---|
| GET / POST / DELETE `/api/pulls/repos` | POST/DELETE `{repo:"owner/name"}` | `{repos, authors}` |
| PUT `/api/pulls/repos/authors` | `{repo, authors[]}` | `{repos, authors}` |
| GET `/api/pulls/jira-sync` | `key`, `intent=review\|in-progress` | `{transition}` |
| POST `/api/pulls/{owner}/{repo}/{n}/comments` | `{body}` | `{ok, comment:{id,url}}` |
| POST `…/merge` | `{method: merge\|squash\|rebase, headSha}` | `{ok, sha}` |
| POST `…/rerun` | `{headSha}` | `{ok, rerun, failed}` |
| POST `…/reviewers` | `{reviewers:[login \| "team:slug"]}` | `{ok, requested}` |
| POST `…/reviews` | `{event: APPROVE\|REQUEST_CHANGES, body?}`. `REQUEST_CHANGES` exige `body` | `{ok, review:{id,state}}` |

## Agentes e acesso

| Método e caminho | Corpo / query | Resposta 2xx |
|---|---|---|
| GET `/api/agents` | `tab=sessions`, `days`, `sort`, `status`, `q`, `cursor`… | `{tasks: Page, sessions: Page, subtaskProgress, statusCounts}` |
| GET `/api/agents/tasks/{id}` | `subtaskCursor` | `{task, activity, subtasks}` |
| PATCH `/api/agents/tasks/{id}` | `{expectedVersion, title?, description?, assignment?, source?}` | `AgentTask`; 409 `version_conflict` |
| DELETE `/api/agents/tasks/{id}` | — | 204; 409 `task_has_subtasks` |
| POST `/api/agents/tasks/{id}/transitions` | `{status, expectedVersion, hold?}` | `AgentTask` |
| GET `/api/agents/sessions/{id}/live` | — | terminal, ou `{available:false, reason}` |
| POST `/api/agents/sessions/{id}/messages` | `{text ≤4000}` + `Idempotency-Key` | 202 `{ok, id, state}` |
| GET / POST `/api/agent-access/tokens` | POST `{label ≤80, scopes:["agents:read"\|"agents:write"]}` | `{items}` / 201 `{credential, secret}` (o segredo aparece uma vez só) |
| DELETE `/api/agent-access/tokens/{id}` | — | 204 |
| GET `/api/agent-access/prompt` | — | `{prompt}` |
| GET `/api/agent-access/config` | — | `{mcpUrl}`; 503 sem OAuth |
| GET `/api/agent-access/grants` | — | `{grants:[{id, clientId, clientName, scopes, expiresAt}]}` |
| DELETE `/api/agent-access/grants/{id}` | — | `{ok}` |

Os tipos `AgentTask`, `AgentSession`, `Activity`, `Page` e o enum de status estão
em `lib/agents/model.ts` e `lib/agents/schemas.ts`. A tarefa T101 os transcreve.

## Integrações

| Método e caminho | Corpo / query | Resposta 2xx |
|---|---|---|
| GET `/api/integrations` | — | `{vaultReady, mstodoAvailable, googleConfigured, googleRedirectUri, slackConfigured, slackRedirectUri, catalog, modules}` |
| PATCH `/api/integrations/{module}` | `{enabled}` | `{modules}` |
| POST `/api/integrations/{module}/connections` | `{values, label?}` | `{modules}`; 409 em módulo de conexão única |
| PUT / DELETE `/api/integrations/{module}/connections/{id}` | PUT `{values, label?}`. Segredo vazio mantém o salvo | `{modules}` / `{modules, label}` |
| POST `/api/integrations/{module}/test` | `{id}` | **sempre 200** `{ok, message}` |
| GET / PATCH `/api/integrations/agenda/google/calendars` | GET `id`; PATCH `{id, calendarIds[]}` | `{calendars, selected}` / `{modules}` |
| GET `/api/integrations/agenda/google/start` · `/api/integrations/slack/start` | `purpose=agenda\|notes` | redirect. **Abrir no navegador**: o retorno cai em `/tools` com o cookie do navegador |

## O que o app não usa

- `/api/push*`: Web Push, que só aceita endpoints de navegador.
- `/api/v1/agents/**`: API dos agentes com token `dwp_`.
- `/mcp`, `/oauth/*`, `/.well-known/*`.
- As preferências `layout` e `homeView`.
