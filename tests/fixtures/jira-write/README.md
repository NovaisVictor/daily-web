# Jira write-feature fixtures

Read-only responses captured from the real Jira Cloud instance on **2026-10-20**, using the
admin user's connection. Only GET requests were made (plus `POST /rest/api/3/search/jql`, a read).

Sanitized before writing: account ids → `557058:00000000-0000-0000-0000-00000000000N`,
display names → `Pessoa N`, emails → `pessoa-n@example.com`, `avatarUrls` removed, instance
host → `example.atlassian.net`. Issue keys, status/transition/field/priority ids and names are real.

| File | Endpoint | Notes |
| --- | --- | --- |
| `transitions-story.json` | `GET /rest/api/3/issue/TT-5019/transitions?expand=transitions.fields` | História |
| `transitions-epic.json` | `GET /rest/api/3/issue/TT-2376/transitions?expand=transitions.fields` | Epic (identical to the story's) |
| `transitions-bug.json` | `GET /rest/api/3/issue/TT-4400/transitions?expand=transitions.fields` | Bug (identical); no open Tarefa exists in TT |
| `approvals-pending.json` | composite, see `_capture` | `approvals = myPending()` returned 0 issues; holds that search result, `GET /rest/servicedeskapi/request/PDS-2763/approval` (already decided) and `GET /rest/servicedeskapi/request/TT-5019/approval` (non-service-desk issue) |
| `approval-single.json` | `GET /rest/servicedeskapi/request/PDS-2763/approval/3516` | |
| `fields-flag-start.json` | `GET /rest/api/3/field` | filtered to names matching `/flag\|start date\|data de in[ií]cio\|impedi/i` |
| `editmeta-story.json` | `GET /rest/api/3/issue/TT-5019/editmeta` | filtered to `duedate`, `priority`, `assignee`, `customfield_10021`, `customfield_10015` |
| `priorities.json` | `GET /rest/api/3/priority` | |
| `priorities-search.json` | `GET /rest/api/3/priority/search` | paginated, has `isDefault` |
| `createmeta-issuetypes.json` | `GET /rest/api/3/issue/createmeta/TT/issuetypes` | |
| `createmeta-story.json` | `GET /rest/api/3/issue/createmeta/TT/issuetypes/10005?maxResults=200` | `fields` filtered to required + `summary`/`parent`; `total` (20) is the unfiltered count |
| `changelog-status.json` | `GET /rest/api/3/issue/TT-5019/changelog?maxResults=100` | História; only histories with `status` items kept; `total` is unfiltered |
| `changelog-status-no-start-date.json` | `GET /rest/api/3/issue/TT-4404/changelog?maxResults=100` | Bug in progress with no start date (no such História existed) |
| `issue-flagged.json` | `GET /rest/api/3/issue/TT-5007?fields=customfield_10021,priority,duedate,assignee` | flagged issue |
| `myself.json` | `GET /rest/api/3/myself` | reduced to `self`, `accountId`, `accountType`, `active` |

## KEY FINDINGS

- **Flagged**: `customfield_10021`, name `Flagged`, schema `{"type":"array","items":"option","custom":"com.atlassian.jira.plugin.system.customfieldtypes:multicheckboxes","customId":10021}`.
  Editmeta operations `["add","set","remove"]`, single allowed value `{"id":"10019","value":"Impediment"}`.
  Set (not called, standard option-array shape): `PUT /rest/api/3/issue/{key}` `{"fields":{"customfield_10021":[{"id":"10019"}]}}`.
  Clear (not called): `{"fields":{"customfield_10021":[]}}`, or `{"update":{"customfield_10021":[{"remove":{"id":"10019"}}]}}`. Read value when flagged: `[{"self":…,"value":"Impediment","id":"10019"}]`; unflagged: `null`.
  JQL `Flagged is not EMPTY` works.
- **Start date**: `customfield_10015`, name `Data de início` (no field named "Start date" exists), schema `{"type":"date","custom":"com.atlassian.jira.plugin.system.customfieldtypes:datepicker","customId":10015}`, operations `["set"]`. Value is `"YYYY-MM-DD"` or `null`. JQL `cf[10015] is EMPTY` works.
- **Due date** `duedate` (`{"type":"date","system":"duedate"}`), **priority** (`{"type":"priority"}`, allowedValues = the 5 priorities) and **assignee** (`{"type":"user"}`, `autoCompleteUrl` = `/rest/api/3/user/assignable/search?issueKey=…&query=`) are all optional, operation `["set"]`.
- **Transitions**: no transition declares required fields. With `expand=transitions.fields`, `fields` is `{}` on every transition, `hasScreen: false`, `isConditional: false`, `isGlobal: true`, `isAvailable: true`. Story, Epic and Bug in TT share the same workflow (11 transitions):
  `2 Em Discovery→Discovery(new)`, `3 Cancelado→Arquivado(done)`, `4 Freezing→Freezing(new)`, `5 Canceled→Cancelado(done)`, `6 Resolved→Resolvido(done)`, `7 Code Review PR→Code Review PR(indeterminate)`, `9 Aguardando Dependência→Aguardando Dependência(indeterminate)`, `11 Lista de pendências→Backlog(new)`, `21 Selected for Development→Selected for Development(new)`, `31 Em andamento→Em Andamento(indeterminate)`, `41 Itens concluídos→Concluído(done)`.
  Each item: `{id, name, to:{id,name,statusCategory:{id,key,name,colorName}}, hasScreen, isGlobal, isInitial, isAvailable, isConditional, isLooped, fields}`. Transition name ≠ target status name (e.g. `31 "Em andamento"` → status `"Em Andamento"`); key off `to.statusCategory.key`, not names.
- **Approvals**: list is paginated `{size,start,limit,isLastPage,_links,values:[…]}`. Each approval: `id` (string, e.g. `"3516"`), `name`, `finalDecision` (`"approved"` seen; `"declined"`/`"pending"` per docs), `canAnswerApproval` (boolean; `false` once decided), `approvers:[{approver:{accountId,emailAddress,displayName,active,timeZone,_links}, approverDecision}]`, `createdDate`/`completedDate` (`{iso8601,jira,friendly,epochMillis}`), `_links.self` (uses the numeric request id). A non-service-desk issue (TT-5019) returns **200 with `values: []`**, not 404.
  Decide (documented, NOT called): `POST /rest/servicedeskapi/request/{key}/approval/{approvalId}` with body `{"decision":"approve"}` or `{"decision":"decline"}`.
  No pending approval existed at capture time, so the `canAnswerApproval: true` / `finalDecision: "pending"` shape is not captured.
- **Priorities** (id/name): `1 Crítica`, `2 Alta`, `3 Média`, `4 Baixa`, `5 Trivial`. `/priority/search` reports `isDefault: false` on all five.
- **Create in TT**: story-level type is `10005 História` (`hierarchyLevel 0`, `subtask false`). Other types: `10000 Epic` (1), `10099 Subtarefa` (-1, subtask), `10108 Bug` (0), `10177 Iniciativa` (2), `10850 Objective` (3). Required create fields for História: `issuetype`, `project`, `summary`. `parent` is optional (`{"type":"issuelink","system":"parent"}`, operation `set`).
- **Changelog status changes**: `values[]` = `{id, author, created, items[]}` with `created` like `"2026-10-20T16:10:02.227-0300"`; status item `{field:"status", fieldtype:"jira", fieldId:"status", from, fromString, to, toString}` (`from`/`to` are status ids, e.g. `11540` = `Em Andamento`). To suggest a start date, take the earliest history whose status item has `to` in an `indeterminate` category status (map ids via the transitions' `to.statusCategory`). TT-4404 shows a status can enter `Em Andamento`, go back to `Backlog` and enter again — the first entry (2026-10-09) is the earliest.
