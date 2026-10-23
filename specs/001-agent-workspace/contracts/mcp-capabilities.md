# MCP Capability Contract and Parity Inventory

**Implementation snapshot**: current feature checkout reviewed 2026-10-23.
The group tables define required behavior; the concrete inventory below records
58 registered tools, their actual scopes and current evidence. A registered name
is not proof of behavioral parity. Open evidence gaps remain release gates.
Existing routes are source evidence, not commands for clients to call directly.

## Transport, identity, and output

Streamable HTTP endpoint `/mcp`; Node runtime; verified OAuth principal and grant
on every request. Separate scopes `agents:read/write`, `tasks:read/write`,
`jira:read/write`, `github:read/write`, `connections:read/write`, `agenda:focus`.
Only consented module capabilities are advertised; disabled/unconnected modules
return a safe actionable state. Discovery does not expose another user's tools/data.
Every tool validates inputs and outputs and declares mutability accurately.
Return normalized result or structured error with retry classification; MCP tool
errors use isError and safe codes, without exposing secrets. List results explicitly
include completeness and cursor. Mutation inputs carry operationId, request time,
and applicable expected version or SHA. Operations never use a token's subject as
an unrestricted user override.

## Connection selection

Every provider-scoped tool accepts a required `connectionId`, validated against
both the principal owner and the declared module. No MCP tool silently selects
the first configured connection. A missing selector returns invalid input with
safe guidance to list the caller's connection metadata; a foreign or wrong-module
selector returns not found. Local personal tasks use explicit `provider: local`;
external personal tasks use `provider: mstodo` plus an owned connectionId.
Multi-source reads require an explicit list of connectionIds or `scope: all_owned`;
each item then identifies its connection and per-connection completeness/error.
The shared operation layer receives resolved connections, not implicit globals.
Legacy browser routes may resolve their current selected connection at the edge,
without imposing that implicit selection on new API/MCP contracts.

## Agents and personal tasks

| Tool group | Required actions | Existing source |
| --- | --- | --- |
| agents | register; sessions create/list/get/heartbeat; tasks create/list/get/update/transition/activity/list_activity/delete | New reporting contract, `contracts/reporting-api.md` |
| tasks | list/get/create (including scheduling, priority, recurrence, initial todo/doing and boardStyle)/update/complete/reopen/delete | `lib/tasks/index.ts`, `app/api/tasks/route.ts`, `app/api/tasks/[id]/route.ts`, state snapshot |
| tasks.board | set todo/doing; completion via provider; read effective column | `app/api/tasks/[id]/board/route.ts`, `lib/taskBoard.ts` |
| tasks.subtasks | create/update/complete/reopen/delete | `app/api/tasks/[id]/subtasks/` |
| tasks.query | text/priority/due/status filters and grouping matching UI | `components/TasksPanel.tsx`, `lib/taskGrouping.ts` |

Agent tracking tasks and existing personal tasks are distinct resource namespaces.
Deleting an agent tracking item never deletes its linked external/personal task.
MCP offers every lifecycle operation in the respective namespace. No unsupported
provider feature is silently emulated or reported as successful.

## Jira

| Tool group | Required actions | Existing route or source |
| --- | --- | --- |
| jira.work | list open/delivered/approved/problems/hierarchy/watched; same filters, ordering, current-person view; return related PR URLs | `components/JiraPanel.tsx`, `/api/state`, `lib/jiraFilters.ts` |
| jira.people | search; list followed; follow; unfollow; read followed person's work | `/api/jira/people`, `/api/jira/people/search`, `/api/jira/people/[accountId]` |
| jira.watch | list; watch; unwatch issue | `/api/jira/watch`, state snapshot |
| jira.transitions | list permitted; apply transition | `/api/jira/issues/[key]/transitions` |
| jira.approvals | read pending; approve; decline | `/api/jira/issues/[key]/approvals` |
| jira.comments | add comment | `/api/jira/issues/[key]/comments` |
| jira.flag | flag with reason; unflag with optional note | `/api/jira/issues/[key]/flag` |
| jira.fields | read priority options; set priority; set/clear due date; assign to self | `/api/jira/issues/[key]/fields` |
| jira.stories | create story under epic | `/api/jira/issues/[key]/stories` |
| jira.epics | search eligible epic; assign story parent | `/api/jira/epics`, `/api/jira/issues/[key]/parent` |
| jira.start_dates | suggest from history; set; bulk suggest; bulk apply | `/api/jira/issues/[key]/start-date`, `/api/jira/problems/start-dates` |
| jira.summary | generate daily/weekly copyable summary using same selection context | `lib/standup.ts` |

Keep existing restrictions: followed-person detail is not arbitrary people access;
assign-to-self is not arbitrary assignment. Read all necessary pages; partial
results are explicitly partial. Invalid transition is conflict, never default.

Browser Jira routes call `jiraActions` from `lib/operations/jira.ts`. Session guards
and legacy connection selection remain transport responsibilities; MCP requires
explicit owned connections and granted scopes. Approval eligibility, transition
revalidation, writes, preference transactions and cache changes use shared actions.
Browser response shapes remain unchanged, including flag-comment warnings and
per-item start-date outcomes. MCP start-date results contain either confirmed
`{ok:true,id}` or `{id,status:"refused"|"uncertain",code:"state_changed"|"uncertain_outcome"}`.
Each item owns its receipt, so uncertain items are never automatically resubmitted.
Flag writes followed by an unconfirmed comment persist an uncertain receipt with
only issue identity and a safe code; they never claim complete success.

## GitHub

| Tool group | Required actions | Existing route or source |
| --- | --- | --- |
| github.work | list watched PRs/issues, requested reviews, own PRs, default-branch state; same filters and external URLs | `components/PullsPanel.tsx`, `/api/state` |
| github.repos | list/add/remove watched repositories | `/api/pulls/repos` |
| github.reviews | approve; request changes | `/api/pulls/[owner]/[repo]/[number]/reviews` |
| github.comments | comment on PR/issue | same prefix, `/comments` |
| github.reviewers | request review again from users/teams | same prefix, `/reviewers` |
| github.merge | merge/squash/rebase with current headSha | same prefix, `/merge` |
| github.rerun | rerun failed checks with headSha and bounded runs | same prefix, `/rerun` |
| github.jira_sync | suggest eligible transition; apply through Jira operation with both scopes | `/api/pulls/jira-sync`, Jira transitions |

Preserve self-review prohibition, draft/mergeability checks, provider permissions,
head SHA matching, and current-state revalidation in `lib/integrations/github/actions.ts`.
A stale SHA produces a conflict. Never retry an uncertain merge/review/comment blindly.

## Shared actions required by supported panels

| Tool group | Required actions | Existing source |
| --- | --- | --- |
| connections | inspect configuration metadata; generate setup URL; edit non-secret labels; remove/test Jira/GitHub/task connection; enable/disable supported module for the authenticated user only | `/api/integrations`, `/api/integrations/[module]`, `/connections`, `/connections/[id]`, `/test` |
| focus | list eligible writable agenda targets; create task/Jira/PR focus block | `/api/agenda/focus-blocks`, `components/FocusBlockProvider.tsx` |

MCP schemas reject all secret fields. Credential creation/change is the explicit
user-approved exception to parity: return a same-origin authenticated browser setup
URL, never a secret. Browser setup preserves existing blank-secret-field semantics.
MCP can inspect completion and manage non-secret metadata/test/remove/toggle actions.
Scopes cannot be widened by a tool. Focus requires `agenda:focus` plus read
access to the source; no general agenda CRUD is introduced. Permission denial or
lack of a writable connection must be visible. Credential/grant administration is
an access-control browser workflow, not available to low-privilege reporting tokens.

## Conformance evidence required per operation

Each concrete operation expanded from these groups needs one inventory row with
source UI/action, input/output schema, permission, success test, denial test, invalid
input test, provider failure test, and observed outcome. Existing fixtures may be
reused only after provenance is verified. Obtain missing sanitized real provider
fixtures before writing derived mocks. No operation is complete merely because a
tool name exists. Literal operation IDs and their exported registry are checked
against this inventory in tests.


## Concrete registered inventory

This section is maintained independently of implementation and read by
`tests/mcp/parity.test.ts`. Its first three columns are the reviewable transport
contract; adding, removing, widening or changing an operation requires updating
this inventory and reviewing the corresponding behavior.

Schema references identify the executable strict input/output contracts, rather
than duplicating their definitions here. Integration inputs are the named
`operation(...)` in the listed source; results are named entries in
`lib/operations/results.ts` or its shared `success` contract. Agent inputs are
named registrations in `lib/mcp/tools/agents.ts`, with domain results in
`lib/agents/model.ts`; their MCP output uses concrete validated schemas in the registry.
Every integration operation is exported through
`lib/mcp/tools/integrations.ts`; agent registration uses
`lib/mcp/registry.ts`. Read/write below is the actual advertised annotation,
not a claim that all composite actions require only that single scope.

Evidence keys:

- **A**: `tests/mcp/parity.test.ts`, complete agent callback lifecycle using a
  disposable database, versioning, replay and foreign-owner rejection. OAuth
  revalidation is mocked here; real transport/grant checks are separate.
- **B**: the same parity suite rejects unknown input and narrows granted scopes
  inside every callback, proves no external fetch and no created agent records,
  and compares per-scope discovery to this maintained inventory. Existing
  `tests/lib/operations/integrations.test.ts` also tests missing-scope denial
  before input validation for every integration operation.
- **I**: `tests/lib/operations/integrations.test.ts`; focused shared-operation
  behaviors, including safe uncertain outcomes, explicit connection ownership,
  disabled modules and runtime result-enum validation. This is not a full success
  and provider-failure matrix for every operation.
- **J**: `tests/lib/operations/jiraParity.test.ts`; all 19 Jira operations have direct
  success/result-schema, scope, foreign-connection, deleted-user and strict-input cases.
  External reads and writes have provider-failure cases; seven individual external
  writes have known-refusal, retry and replay cases. Bulk dates cover refusal,
  uncertainty and successful items together; flags cover persisted partial outcomes.
  Transition, approval and comment-resource mocks reuse captured GET fixtures
  and documented resource projections in `tests/fixtures/jira-write/README.md`.
  Mutation/failure replies are derived test scenarios, not assertions that a
  live external write was performed.
- **GH**: `tests/lib/operations/github.test.ts`; all ten GitHub operations have
  direct scope, foreign-connection and strict-input cases. Shared successes,
  captured read projections, replay, provider refusals/uncertainty, partial jobs,
  SHA/draft/self-review checks and real Jira-sync preflight are exercised.
  `tests/api/pullsActions.test.ts`, `tests/api/pullsRepos.test.ts` and
  `tests/api/pullJiraSync.test.ts` verify preserved browser contracts using those
  same operations/helpers.
- **MH**: `tests/mcp/github.test.ts`; scoped registration, strict inputs,
  confirmed replay, authoritative grant revocation and sanitized partial-job
  counts/IDs on both the first response and replay, without repeated writes.
- **P**: `tests/lib/operations/personalParity.test.ts`, direct personal-task reads,
  CRUD, board/completion/reopen and every subtask action, captured Microsoft To Do
  read models and provider-write replay/uncertainty; connection setup/edit/test/remove,
  metadata secrecy, source ownership and focus creation from all three source kinds.
  `I` also covers module toggling, due grouping and invalid configuration boundaries.
- **R**: `tests/api/agents/reporting.test.ts` exercises every reporting route;
  `tests/lib/agents/storage.test.ts` covers expiry, replay, versioning and restore.

All rows have B denial/invalid-input coverage. A success or provider-failure gap
is explicit below; legacy route/provider tests are supporting evidence only and
do not certify their new MCP adapter. Provider failures are not applicable to
purely local agent persistence, whose local failure cases are covered by A/R.

| Tool | Primary scope | Mode | Panel/API source | Input/result schema source | Success evidence | Failure/evidence status |
| --- | --- | --- | --- | --- | --- | --- |
| `agents_register` | `agents:write` | write | Reporting register API | `lib/mcp/tools/agents.ts` / agent domain model | A; R | B; local failures A/R; typed output verified (A/R) |
| `agents_sessions_create` | `agents:write` | write | Reporting sessions API | `lib/mcp/tools/agents.ts` / agent domain model | A; R | B; local failures A/R; typed output verified (A/R) |
| `agents_sessions_list` | `agents:read` | read | Agents workspace sessions tab | `lib/mcp/tools/agents.ts` / agent domain model | A; R | B; local failures A/R; typed output verified (A/R) |
| `agents_sessions_get` | `agents:read` | read | Reporting session detail API | `lib/mcp/tools/agents.ts` / agent domain model | A; R | B; local failures A/R; typed output verified (A/R) |
| `agents_sessions_heartbeat` | `agents:write` | write | Reporting session heartbeat API | `lib/mcp/tools/agents.ts` / agent domain model | A; R | B; local failures A/R; typed output verified (A/R) |
| `agents_tasks_create` | `agents:write` | write | Reporting create API | `lib/mcp/tools/agents.ts` / agent domain model | A; R | B; local failures A/R; typed output verified (A/R) |
| `agents_tasks_list` | `agents:read` | read | Home kanban / agents workspace | `lib/mcp/tools/agents.ts` / agent domain model | A; R | B; local failures A/R; typed output verified (A/R) |
| `agents_tasks_get` | `agents:read` | read | Task detail page | `lib/mcp/tools/agents.ts` / agent domain model | A; R | B; local failures A/R; typed output verified (A/R) |
| `agents_tasks_update` | `agents:write` | write | Task edit dialog | `lib/mcp/tools/agents.ts` / agent domain model | A; R | B; local failures A/R; typed output verified (A/R) |
| `agents_tasks_transition` | `agents:write` | write | Task lifecycle buttons | `lib/mcp/tools/agents.ts` / agent domain model | A; R | B; local failures A/R; typed output verified (A/R) |
| `agents_tasks_activity` | `agents:write` | write | Reporting activity API | `lib/mcp/tools/agents.ts` / agent domain model | A; R | B; local failures A/R; typed output verified (A/R) |
| `agents_tasks_list_activity` | `agents:read` | read | Task detail activity timeline | `lib/mcp/tools/agents.ts` / agent domain model | A; R | B; local failures A/R; typed output verified (A/R) |
| `agents_tasks_delete` | `agents:write` | write | Task delete dialog | `lib/mcp/tools/agents.ts` / agent domain model | A; R | B; local failures A/R; typed output verified (A/R) |
| `jira_work` | `jira:read` | read | JiraPanel / app/api/jira | `lib/operations/jira.ts` / `lib/operations/results.ts` | J: direct success/schema; scope, owner, input and identity boundaries | J: provider failure/refusal/replay where applicable; local people read has no provider; captured GET/resource projections with derived mutation/failure scenarios; no live write asserted |
| `jira_transitions` | `jira:read` | read | JiraPanel / app/api/jira | `lib/operations/jira.ts` / `lib/operations/results.ts` | J: direct success/schema; scope, owner, input and identity boundaries | J: provider failure/refusal/replay where applicable; local people read has no provider; captured GET/resource projections with derived mutation/failure scenarios; no live write asserted |
| `jira_transition` | `jira:write` | write | JiraPanel / app/api/jira | `lib/operations/jira.ts` / `lib/operations/results.ts` | J: direct success/schema; scope, owner, input and identity boundaries | J: provider failure/refusal/replay where applicable; local people read has no provider; captured GET/resource projections with derived mutation/failure scenarios; no live write asserted |
| `jira_approvals` | `jira:read` | read | JiraPanel / app/api/jira | `lib/operations/jira.ts` / `lib/operations/results.ts` | J: direct success/schema; scope, owner, input and identity boundaries | J: provider failure/refusal/replay where applicable; local people read has no provider; captured GET/resource projections with derived mutation/failure scenarios; no live write asserted |
| `jira_approval` | `jira:write` | write | JiraPanel / app/api/jira | `lib/operations/jira.ts` / `lib/operations/results.ts` | J: direct success/schema; scope, owner, input and identity boundaries | J: provider failure/refusal/replay where applicable; local people read has no provider; captured GET/resource projections with derived mutation/failure scenarios; no live write asserted |
| `jira_comment` | `jira:write` | write | JiraPanel / app/api/jira | `lib/operations/jira.ts` / `lib/operations/results.ts` | J: direct success/schema; scope, owner, input and identity boundaries | J: provider failure/refusal/replay where applicable; local people read has no provider; captured GET/resource projections with derived mutation/failure scenarios; no live write asserted |
| `jira_flag` | `jira:write` | write | JiraPanel / app/api/jira | `lib/operations/jira.ts` / `lib/operations/results.ts` | J: direct success/schema; scope, owner, input and identity boundaries | J: provider failure/refusal/replay where applicable; local people read has no provider; captured GET/resource projections with derived mutation/failure scenarios; no live write asserted |
| `jira_priorities` | `jira:read` | read | JiraPanel / app/api/jira | `lib/operations/jira.ts` / `lib/operations/results.ts` | J: direct success/schema; scope, owner, input and identity boundaries | J: provider failure/refusal/replay where applicable; local people read has no provider; captured GET/resource projections with derived mutation/failure scenarios; no live write asserted |
| `jira_edit` | `jira:write` | write | JiraPanel / app/api/jira | `lib/operations/jira.ts` / `lib/operations/results.ts` | J: direct success/schema; scope, owner, input and identity boundaries | J: provider failure/refusal/replay where applicable; local people read has no provider; captured GET/resource projections with derived mutation/failure scenarios; no live write asserted |
| `jira_story_create` | `jira:write` | write | JiraPanel / app/api/jira | `lib/operations/jira.ts` / `lib/operations/results.ts` | J: direct success/schema; scope, owner, input and identity boundaries | J: provider failure/refusal/replay where applicable; local people read has no provider; captured GET/resource projections with derived mutation/failure scenarios; no live write asserted |
| `jira_epics` | `jira:read` | read | JiraPanel / app/api/jira | `lib/operations/jira.ts` / `lib/operations/results.ts` | J: direct success/schema; scope, owner, input and identity boundaries | J: provider failure/refusal/replay where applicable; local people read has no provider; captured GET/resource projections with derived mutation/failure scenarios; no live write asserted |
| `jira_parent` | `jira:write` | write | JiraPanel / app/api/jira | `lib/operations/jira.ts` / `lib/operations/results.ts` | J: direct success/schema; scope, owner, input and identity boundaries | J: provider failure/refusal/replay where applicable; local people read has no provider; captured GET/resource projections with derived mutation/failure scenarios; no live write asserted |
| `jira_start_suggest` | `jira:read` | read | JiraPanel / app/api/jira | `lib/operations/jira.ts` / `lib/operations/results.ts` | J: direct success/schema; scope, owner, input and identity boundaries | J: provider failure/refusal/replay where applicable; local people read has no provider; captured GET/resource projections with derived mutation/failure scenarios; no live write asserted |
| `jira_start_apply` | `jira:write` | write | JiraPanel / app/api/jira | `lib/operations/jira.ts` / `lib/operations/results.ts` | J: direct success/schema; scope, owner, input and identity boundaries | J: provider failure/refusal/replay where applicable; local people read has no provider; captured GET/resource projections with derived mutation/failure scenarios; no live write asserted |
| `jira_people` | `jira:read` | read | JiraPanel / app/api/jira | `lib/operations/jira.ts` / `lib/operations/results.ts` | J: direct success/schema; scope, owner, input and identity boundaries | J: provider failure/refusal/replay where applicable; local people read has no provider; captured GET/resource projections with derived mutation/failure scenarios; no live write asserted |
| `jira_people_search` | `jira:read` | read | JiraPanel / app/api/jira | `lib/operations/jira.ts` / `lib/operations/results.ts` | J: direct success/schema; scope, owner, input and identity boundaries | J: provider failure/refusal/replay where applicable; local people read has no provider; captured GET/resource projections with derived mutation/failure scenarios; no live write asserted |
| `jira_people_follow` | `jira:write` | write | JiraPanel / app/api/jira | `lib/operations/jira.ts` / `lib/operations/results.ts` | J: direct success/schema; scope, owner, input and identity boundaries | J: provider failure/refusal/replay where applicable; local people read has no provider; captured GET/resource projections with derived mutation/failure scenarios; no live write asserted |
| `jira_watch` | `jira:write` | write | JiraPanel / app/api/jira | `lib/operations/jira.ts` / `lib/operations/results.ts` | J: direct success/schema; scope, owner, input and identity boundaries | J: provider failure/refusal/replay where applicable; local people read has no provider; captured GET/resource projections with derived mutation/failure scenarios; no live write asserted |
| `jira_summary` | `jira:read` | read | JiraPanel / app/api/jira | `lib/operations/jira.ts` / `lib/operations/results.ts` | J: direct success/schema; scope, owner, input and identity boundaries | J: provider failure/refusal/replay where applicable; local people read has no provider; captured GET/resource projections with derived mutation/failure scenarios; no live write asserted |
| `github_work` | `github:read` | read | PullsPanel / app/api/pulls | `lib/operations/github.ts` / `lib/operations/results.ts` | GH: tracked/review/mine captures, filters, paging and default branches | GH: partial data, unknown result enum/cursor, safe provider failure |
| `github_repositories` | `github:read` | read | PullsPanel / app/api/pulls | `lib/operations/github.ts` / `lib/operations/results.ts` | GH: owned configuration read; browser GET | GH/B: owner/scope/input; local configuration has no provider failure |
| `github_repository_add` | `github:write` | write | PullsPanel / app/api/pulls | `lib/operations/github.ts` / `lib/operations/results.ts` | GH: atomic local add/replay; browser POST capacity boundary | GH/B: owner/scope/input; no remote write |
| `github_repository_remove` | `github:write` | write | PullsPanel / app/api/pulls | `lib/operations/github.ts` / `lib/operations/results.ts` | GH: atomic local remove/replay; browser DELETE | GH/B: owner/scope/input; no remote write |
| `github_review` | `github:write` | write | PullsPanel / app/api/pulls | `lib/operations/github.ts` / `lib/operations/results.ts` | GH: current-pull/viewer preflight, review and replay; browser reviews | GH: self/draft/closed refusal, 4xx denial, malformed result and unknown outcome |
| `github_comment` | `github:write` | write | PullsPanel / app/api/pulls | `lib/operations/github.ts` / `lib/operations/results.ts` | GH/MH: confirmed identity/URL and replay; browser idempotency | GH/MH: 4xx denial, uncertainty, foreign connection, Origin and grant revocation |
| `github_request_review` | `github:write` | write | PullsPanel / app/api/pulls | `lib/operations/github.ts` / `lib/operations/results.ts` | GH: users/teams, deduplication and replay; browser reviewers | GH: author/draft refusal, invalid response, 4xx denial and unknown outcome |
| `github_merge` | `github:write` | write | PullsPanel / app/api/pulls | `lib/operations/github.ts` / `lib/operations/results.ts` | GH: exact-SHA merge and confirmed replay; browser merge | GH: stale SHA/draft/closed/conflict/unknown mergeability, 4xx denial and unknown outcome |
| `github_rerun` | `github:write` | write | PullsPanel / app/api/pulls | `lib/operations/github.ts` / `lib/operations/results.ts` | GH: bounded eligible jobs/zero jobs; browser legacy partial result | GH/MH: stale SHA, all/partial failures, sanitized partialOutcome and replay without repeated jobs |
| `github_jira_sync` | `github:read` | write | PullsPanel / app/api/pulls | `lib/operations/github.ts` / `lib/operations/results.ts` | GH: shared Jira suggestion/apply and replay; browser shared suggestion | GH: both providers/scopes, expected transition/intent/screen, provider failure and uncertainty |
| `tasks_list` | `tasks:read` | read | TasksPanel / app/api/tasks | `lib/operations/tasks.ts` / `lib/operations/results.ts` | P; I: direct shared-operation success and action variants | B; P/I: owner/scope/input boundaries; provider failure and replay where external; local configuration has no provider write |
| `tasks_get` | `tasks:read` | read | TasksPanel / app/api/tasks | `lib/operations/tasks.ts` / `lib/operations/results.ts` | P; I: direct shared-operation success and action variants | B; P/I: owner/scope/input boundaries; provider failure and replay where external; local configuration has no provider write |
| `tasks_create` | `tasks:write` | write | TasksPanel / app/api/tasks | `lib/operations/tasks.ts` / `lib/operations/results.ts` | P; I: direct shared-operation success and action variants | B; P/I: owner/scope/input boundaries; provider failure and replay where external; local configuration has no provider write |
| `tasks_edit` | `tasks:write` | write | TasksPanel / app/api/tasks | `lib/operations/tasks.ts` / `lib/operations/results.ts` | P; I: direct shared-operation success and action variants | B; P/I: owner/scope/input boundaries; provider failure and replay where external; local configuration has no provider write |
| `tasks_transition` | `tasks:write` | write | TasksPanel / app/api/tasks | `lib/operations/tasks.ts` / `lib/operations/results.ts` | P; I: direct shared-operation success and action variants | B; P/I: owner/scope/input boundaries; provider failure and replay where external; local configuration has no provider write |
| `tasks_delete` | `tasks:write` | write | TasksPanel / app/api/tasks | `lib/operations/tasks.ts` / `lib/operations/results.ts` | P; I: direct shared-operation success and action variants | B; P/I: owner/scope/input boundaries; provider failure and replay where external; local configuration has no provider write |
| `tasks_subtask_create` | `tasks:write` | write | TasksPanel / app/api/tasks | `lib/operations/tasks.ts` / `lib/operations/results.ts` | P; I: direct shared-operation success and action variants | B; P/I: owner/scope/input boundaries; provider failure and replay where external; local configuration has no provider write |
| `tasks_subtask_edit` | `tasks:write` | write | TasksPanel / app/api/tasks | `lib/operations/tasks.ts` / `lib/operations/results.ts` | P; I: direct shared-operation success and action variants | B; P/I: owner/scope/input boundaries; provider failure and replay where external; local configuration has no provider write |
| `connections_list` | `connections:read` | read | IntegrationsPanel / app/api/integrations | `lib/operations/connections.ts` / `lib/operations/results.ts` | P; I: direct shared-operation success and action variants | B; P/I: owner/scope/input boundaries; provider failure and replay where external; local configuration has no provider write |
| `connections_setup` | `connections:write` | read | IntegrationsPanel / app/api/integrations | `lib/operations/connections.ts` / `lib/operations/results.ts` | P; I: direct shared-operation success and action variants | B; P/I: owner/scope/input boundaries; provider failure and replay where external; local configuration has no provider write |
| `connections_update` | `connections:write` | write | IntegrationsPanel / app/api/integrations | `lib/operations/connections.ts` / `lib/operations/results.ts` | P; I: direct shared-operation success and action variants | B; P/I: owner/scope/input boundaries; provider failure and replay where external; local configuration has no provider write |
| `connections_remove` | `connections:write` | write | IntegrationsPanel / app/api/integrations | `lib/operations/connections.ts` / `lib/operations/results.ts` | P; I: direct shared-operation success and action variants | B; P/I: owner/scope/input boundaries; provider failure and replay where external; local configuration has no provider write |
| `connections_test` | `connections:read` | read | IntegrationsPanel / app/api/integrations | `lib/operations/connections.ts` / `lib/operations/results.ts` | P; I: direct shared-operation success and action variants | B; P/I: owner/scope/input boundaries; provider failure and replay where external; local configuration has no provider write |
| `connections_toggle` | `connections:write` | write | IntegrationsPanel / app/api/integrations | `lib/operations/connections.ts` / `lib/operations/results.ts` | P; I: direct shared-operation success and action variants | B; P/I: owner/scope/input boundaries; provider failure and replay where external; local configuration has no provider write |
| `focus_targets` | `agenda:focus` | read | FocusBlockProvider / app/api/agenda/focus-blocks | `lib/operations/focus.ts` / `lib/operations/results.ts` | P; I: direct shared-operation success and action variants | B; P/I: owner/scope/input boundaries; provider failure and replay where external; local configuration has no provider write |
| `focus_create` | `agenda:focus` | write | FocusBlockProvider / app/api/agenda/focus-blocks | `lib/operations/focus.ts` / `lib/operations/results.ts` | P; I: direct shared-operation success and action variants | B; P/I: owner/scope/input boundaries; provider failure and replay where external; local configuration has no provider write |


## Composite permissions and precise parity limits

- `github_jira_sync` is advertised under `github:read`; suggesting additionally
  requires `jira:read`. Applying requires `github:write` and `jira:write`, an
  explicitly selected Jira connection and current transition confirmation.
- `focus_create` requires `agenda:focus` and read access to its selected source:
  `tasks:read`, `jira:read` or `github:read`. It does not provide general agenda CRUD.
- `connections_setup` is a read-only setup-link operation requiring
  `connections:write`; it does not accept or reveal credentials.
- `tasks_create` and `tasks_edit` accept `boardStyle` paper/pin palettes and null
  automatic resets; style-only edits are local atomic mutations without a provider
  write. Task reads expose typed nullable paper/pin values.
- `tasks_transition` represents board movement, complete and reopen;
  `tasks_subtask_edit` represents edit, complete, reopen and delete. Jira flag,
  approval, following and watching actions similarly use explicit action enums.
- All Jira and GitHub operations require an owned, explicitly selected connection.
  The browser-only secret-entry exception remains user-approved.

## Open conformance gaps and CI coverage

**G1 — Resolved: typed agent outputs and aligned input limits.** The 13 agent
MCP tools now validate concrete agent/session/task/activity/page/null schemas.
Task titles are limited to the same 200 characters as persistence. The agent
lifecycle and parity suites exercise these contracts; generic JSON output is
not used for this boundary.

**G2 — Behavioral evidence now distinguished from live execution.** Jira and
GitHub have direct shared-operation success, authorization, invalid-input and
provider-failure/refusal/uncertain-outcome cases, with replay and partial behavior
where applicable (J/GH/MH). Their browser handlers use the shared orchestration;
legacy HTTP and provider tests provide additional supporting coverage. Fixture
READMEs distinguish captured GET/resource projections from derived mutation
replies and adversarial failures. A live external mutation is not implied by a
green test and is not fabricated as a remaining fixture requirement. Personal tasks, connections and focus use P/I evidence; every inventoried operation
has a direct success case, with provider failures tested where an external call exists.

**G3 — Product-action completeness is checked beyond registry equality.**
The Jira/GitHub group inventories map concrete action variants to the shared
orchestration and browser adapters. GitHub details and source/test mapping are in
`contracts/github-parity.md`: views/filters, default branches, repository
configuration, approve/request changes, comments, reviewer users/teams, merge
methods, failed-job reruns and cross-provider Jira synchronization. Named scopes,
state/SHA preflight, refusal, replay and partial results are tested. Registry
comparison remains a regression guard, not the sole evidence of parity. New
panel actions introduced by later upstream changes require the same inventory
and behavior review before integration.

**G4 — Runtime evidence remains separate from static registry tests.** Real
Claude/Codex/agy clients passed browser consent, an actual tool call and automatic
refresh after the normal 900-second lifetime, through the Next fallback proxy
and after companion/application restarts. Grant revocation and temporary-config
cleanup are recorded in `validation/oauth-clients.json`. HTTPS provider/proxy
cookies have an independent regression test. Production service/public-origin
acceptance remains a separate deployment gate.

The existing `npm test` CI step discovers the parity suite along with
`tests/mcp/auth.test.ts`, `tests/mcp/oauth-feasibility.test.ts`, and retention/
restore tests under `tests/lib/agents`. The existing `npm run build` runs the
OAuth companion compiler and the Next production build/type check. No duplicate
full-suite step or alternate unverified command is required. Live provider and
three-client acceptance cannot be inferred from a green offline CI run.

## Agent subtask extension (2026-10-23)

`agents_tasks_create.input.parentTaskId` creates a subtask using the existing
`agents:write` consent. `agents_tasks_list` supports `parentTaskId` and
`scope=all|roots`. All task outputs include nullable `parentTaskId`.
Use the returned child id with the existing get/update/transition/activity/delete
tools; each child has its own version and lifecycle. Parent linkage cannot be
edited. No additional tool or broader scope is needed. See reporting-api.md for
one-level nesting, parent deletion, idempotency and retention semantics.
