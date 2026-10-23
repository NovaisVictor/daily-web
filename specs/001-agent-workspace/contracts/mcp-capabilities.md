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
| tasks | list/get/create/update/complete/reopen/delete | `lib/tasks/index.ts`, `app/api/tasks/route.ts`, `app/api/tasks/[id]/route.ts`, state snapshot |
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
- **J**: `tests/lib/operations/jiraParity.test.ts`; focused Jira shared-operation
  behaviors listed per row. Approval mocks derive from the recorded approval
  fixture; other focused mocks are not evidence of newly captured live writes.
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
| `jira_work` | `jira:read` | read | JiraPanel / app/api/jira | `lib/operations/jira.ts` / `lib/operations/results.ts` | J: delivered filters/order; I: followed-person denial | B; G2 per-operation failure/real-provider proof incomplete |
| `jira_transitions` | `jira:read` | read | JiraPanel / app/api/jira | `lib/operations/jira.ts` / `lib/operations/results.ts` | GAP: direct adapter success case | B; G2 per-operation failure/real-provider proof incomplete |
| `jira_transition` | `jira:write` | write | JiraPanel / app/api/jira | `lib/operations/jira.ts` / `lib/operations/results.ts` | GAP: direct adapter success case | B; G2 per-operation failure/real-provider proof incomplete |
| `jira_approvals` | `jira:read` | read | JiraPanel / app/api/jira | `lib/operations/jira.ts` / `lib/operations/results.ts` | GAP: direct adapter success case | B; G2 per-operation failure/real-provider proof incomplete |
| `jira_approval` | `jira:write` | write | JiraPanel / app/api/jira | `lib/operations/jira.ts` / `lib/operations/results.ts` | J: replay confirmed approval | B; G2 per-operation failure/real-provider proof incomplete |
| `jira_comment` | `jira:write` | write | JiraPanel / app/api/jira | `lib/operations/jira.ts` / `lib/operations/results.ts` | GAP: direct adapter success case | B; G2 per-operation failure/real-provider proof incomplete |
| `jira_flag` | `jira:write` | write | JiraPanel / app/api/jira | `lib/operations/jira.ts` / `lib/operations/results.ts` | GAP: direct adapter success case | B; G2 per-operation failure/real-provider proof incomplete |
| `jira_priorities` | `jira:read` | read | JiraPanel / app/api/jira | `lib/operations/jira.ts` / `lib/operations/results.ts` | GAP: direct adapter success case | B; G2 per-operation failure/real-provider proof incomplete |
| `jira_edit` | `jira:write` | write | JiraPanel / app/api/jira | `lib/operations/jira.ts` / `lib/operations/results.ts` | GAP: direct adapter success case | B; G2 per-operation failure/real-provider proof incomplete |
| `jira_story_create` | `jira:write` | write | JiraPanel / app/api/jira | `lib/operations/jira.ts` / `lib/operations/results.ts` | GAP: direct adapter success case | B; G2 per-operation failure/real-provider proof incomplete |
| `jira_epics` | `jira:read` | read | JiraPanel / app/api/jira | `lib/operations/jira.ts` / `lib/operations/results.ts` | GAP: direct adapter success case | B; G2 per-operation failure/real-provider proof incomplete |
| `jira_parent` | `jira:write` | write | JiraPanel / app/api/jira | `lib/operations/jira.ts` / `lib/operations/results.ts` | GAP: direct adapter success case | B; G2 per-operation failure/real-provider proof incomplete |
| `jira_start_suggest` | `jira:read` | read | JiraPanel / app/api/jira | `lib/operations/jira.ts` / `lib/operations/results.ts` | J: safe provider error text | B; G2 per-operation failure/real-provider proof incomplete |
| `jira_start_apply` | `jira:write` | write | JiraPanel / app/api/jira | `lib/operations/jira.ts` / `lib/operations/results.ts` | GAP: direct adapter success case | B; G2 per-operation failure/real-provider proof incomplete |
| `jira_people` | `jira:read` | read | JiraPanel / app/api/jira | `lib/operations/jira.ts` / `lib/operations/results.ts` | GAP: direct adapter success case | B; G2 per-operation failure/real-provider proof incomplete |
| `jira_people_search` | `jira:read` | read | JiraPanel / app/api/jira | `lib/operations/jira.ts` / `lib/operations/results.ts` | GAP: direct adapter success case | B; G2 per-operation failure/real-provider proof incomplete |
| `jira_people_follow` | `jira:write` | write | JiraPanel / app/api/jira | `lib/operations/jira.ts` / `lib/operations/results.ts` | J: concurrent follow, replay, changed-input conflict | B; G2 per-operation failure/real-provider proof incomplete |
| `jira_watch` | `jira:write` | write | JiraPanel / app/api/jira | `lib/operations/jira.ts` / `lib/operations/results.ts` | J: watch replay and changed-input conflict | B; G2 per-operation failure/real-provider proof incomplete |
| `jira_summary` | `jira:read` | read | JiraPanel / app/api/jira | `lib/operations/jira.ts` / `lib/operations/results.ts` | J: explicit GitHub sources and incomplete result | B; G2 per-operation failure/real-provider proof incomplete |
| `github_work` | `github:read` | read | PullsPanel / app/api/pulls | `lib/operations/github.ts` / `lib/operations/results.ts` | I: partial read and invalid provider enum | B; G2 per-operation failure/real-provider proof incomplete |
| `github_repositories` | `github:read` | read | PullsPanel / app/api/pulls | `lib/operations/github.ts` / `lib/operations/results.ts` | GAP: direct adapter success case | B; G2 per-operation failure/real-provider proof incomplete |
| `github_repository_add` | `github:write` | write | PullsPanel / app/api/pulls | `lib/operations/github.ts` / `lib/operations/results.ts` | GAP: direct adapter success case | B; G2 per-operation failure/real-provider proof incomplete |
| `github_repository_remove` | `github:write` | write | PullsPanel / app/api/pulls | `lib/operations/github.ts` / `lib/operations/results.ts` | GAP: direct adapter success case | B; G2 per-operation failure/real-provider proof incomplete |
| `github_review` | `github:write` | write | PullsPanel / app/api/pulls | `lib/operations/github.ts` / `lib/operations/results.ts` | GAP: direct adapter success case | B; G2 per-operation failure/real-provider proof incomplete |
| `github_comment` | `github:write` | write | PullsPanel / app/api/pulls | `lib/operations/github.ts` / `lib/operations/results.ts` | I: confirmed replay and changed-input conflict | B; G2 per-operation failure/real-provider proof incomplete |
| `github_request_review` | `github:write` | write | PullsPanel / app/api/pulls | `lib/operations/github.ts` / `lib/operations/results.ts` | GAP: direct adapter success case | B; G2 per-operation failure/real-provider proof incomplete |
| `github_merge` | `github:write` | write | PullsPanel / app/api/pulls | `lib/operations/github.ts` / `lib/operations/results.ts` | GAP: direct adapter success case | B; G2 per-operation failure/real-provider proof incomplete |
| `github_rerun` | `github:write` | write | PullsPanel / app/api/pulls | `lib/operations/github.ts` / `lib/operations/results.ts` | GAP: direct adapter success case | B; G2 per-operation failure/real-provider proof incomplete |
| `github_jira_sync` | `github:read` | write | PullsPanel / app/api/pulls | `lib/operations/github.ts` / `lib/operations/results.ts` | GAP: direct adapter success case | B; G2 per-operation failure/real-provider proof incomplete |
| `tasks_list` | `tasks:read` | read | TasksPanel / app/api/tasks | `lib/operations/tasks.ts` / `lib/operations/results.ts` | I: due-window grouping | B; G2 per-operation failure/real-provider proof incomplete |
| `tasks_get` | `tasks:read` | read | TasksPanel / app/api/tasks | `lib/operations/tasks.ts` / `lib/operations/results.ts` | GAP: direct adapter success case | B; G2 per-operation failure/real-provider proof incomplete |
| `tasks_create` | `tasks:write` | write | TasksPanel / app/api/tasks | `lib/operations/tasks.ts` / `lib/operations/results.ts` | I: owner-scoped local creation | B; G2 per-operation failure/real-provider proof incomplete |
| `tasks_edit` | `tasks:write` | write | TasksPanel / app/api/tasks | `lib/operations/tasks.ts` / `lib/operations/results.ts` | I: date/time validation and accepted past date | B; G2 per-operation failure/real-provider proof incomplete |
| `tasks_transition` | `tasks:write` | write | TasksPanel / app/api/tasks | `lib/operations/tasks.ts` / `lib/operations/results.ts` | I: local completion lifecycle | B; G2 per-operation failure/real-provider proof incomplete |
| `tasks_delete` | `tasks:write` | write | TasksPanel / app/api/tasks | `lib/operations/tasks.ts` / `lib/operations/results.ts` | GAP: direct adapter success case | B; G2 per-operation failure/real-provider proof incomplete |
| `tasks_subtask_create` | `tasks:write` | write | TasksPanel / app/api/tasks | `lib/operations/tasks.ts` / `lib/operations/results.ts` | I: local subtask creation | B; G2 per-operation failure/real-provider proof incomplete |
| `tasks_subtask_edit` | `tasks:write` | write | TasksPanel / app/api/tasks | `lib/operations/tasks.ts` / `lib/operations/results.ts` | I: repeated subtask deletion | B; G2 per-operation failure/real-provider proof incomplete |
| `connections_list` | `connections:read` | read | IntegrationsPanel / app/api/integrations | `lib/operations/connections.ts` / `lib/operations/results.ts` | I: secret-free metadata | B; G2 per-operation failure/real-provider proof incomplete |
| `connections_setup` | `connections:write` | read | IntegrationsPanel / app/api/integrations | `lib/operations/connections.ts` / `lib/operations/results.ts` | GAP: direct adapter success case | B; G2 per-operation failure/real-provider proof incomplete |
| `connections_update` | `connections:write` | write | IntegrationsPanel / app/api/integrations | `lib/operations/connections.ts` / `lib/operations/results.ts` | GAP: direct adapter success case | B; G2 per-operation failure/real-provider proof incomplete |
| `connections_remove` | `connections:write` | write | IntegrationsPanel / app/api/integrations | `lib/operations/connections.ts` / `lib/operations/results.ts` | GAP: direct adapter success case | B; G2 per-operation failure/real-provider proof incomplete |
| `connections_test` | `connections:read` | read | IntegrationsPanel / app/api/integrations | `lib/operations/connections.ts` / `lib/operations/results.ts` | GAP: direct adapter success case | B; G2 per-operation failure/real-provider proof incomplete |
| `connections_toggle` | `connections:write` | write | IntegrationsPanel / app/api/integrations | `lib/operations/connections.ts` / `lib/operations/results.ts` | I: owner module toggle | B; G2 per-operation failure/real-provider proof incomplete |
| `focus_targets` | `agenda:focus` | read | FocusBlockProvider / app/api/agenda/focus-blocks | `lib/operations/focus.ts` / `lib/operations/results.ts` | GAP: direct adapter success case | B; G2 per-operation failure/real-provider proof incomplete |
| `focus_create` | `agenda:focus` | write | FocusBlockProvider / app/api/agenda/focus-blocks | `lib/operations/focus.ts` / `lib/operations/results.ts` | GAP: direct adapter success case | B; G2 per-operation failure/real-provider proof incomplete |


## Composite permissions and precise parity limits

- `github_jira_sync` is advertised under `github:read`; suggesting additionally
  requires `jira:read`. Applying requires `github:write` and `jira:write`, an
  explicitly selected Jira connection and current transition confirmation.
- `focus_create` requires `agenda:focus` and read access to its selected source:
  `tasks:read`, `jira:read` or `github:read`. It does not provide general agenda CRUD.
- `connections_setup` is a read-only setup-link operation requiring
  `connections:write`; it does not accept or reveal credentials.
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

**G2 — Full per-operation behavioral proof.** B covers denied scopes and invalid
inputs for every registered adapter. The success column records only focused
existing cases. Operations marked GAP still need their direct success cases;
external operations need corresponding provider refusal/timeout/unknown-outcome
and permission cases using verified fixture provenance. Existing tests such as
`tests/lib/integrations/githubActions.test.ts`, Jira provider tests and legacy
`tests/api/*` route tests remain useful supporting evidence, not replacement for
this adapter-level matrix. No 100% behavioral-parity claim is made.

**G3 — Product-action completeness.** The group inventories remain the checklist
for checking all panel action variants, view filters, hierarchy/default-branch
information and connection configuration options. Registry equality proves no
untracked tool appeared; it cannot prove that every UI action and option was
implemented. Retain this separate acceptance gate.

**G4 — Deployment/client acceptance.** Unit and disposable-provider HTTP tests
exercise OAuth behavior and immediate revocation. Actual Claude/Codex/Gemini
and production Traefik acceptance remain separately recorded gates; an SDK
callback test is not proof of client interoperability.

The existing `npm test` CI step discovers the parity suite along with
`tests/mcp/auth.test.ts`, `tests/mcp/oauth-feasibility.test.ts`, and retention/
restore tests under `tests/lib/agents`. The existing `npm run build` runs the
OAuth companion compiler and the Next production build/type check. No duplicate
full-suite step or alternate unverified command is required. Live provider and
three-client acceptance cannot be inferred from a green offline CI run.
