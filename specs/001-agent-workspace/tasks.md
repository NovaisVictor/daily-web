# Tasks: Daily Web Agent Workspace

**State**: implemented foundation and product modules; integrated acceptance in progress.
Checked tasks have executable evidence in quickstart.md. Unchecked tasks contain
remaining acceptance or operational work and must not be represented as complete.
**Input**: spec.md, plan.md, research.md, data-model.md, contracts/, quickstart.md.
**Tests**: Required by specification acceptance criteria and repository rules.
**Paths**: Relative to repository root. New paths are proposed files, not existing APIs.

## Phase 1: Setup and evidence

Capture baseline and freeze contracts before implementation.

- [x] T001 Review current instructions, remote migration versions, CI coverage, existing raw backup jobs and clean baseline; record evidence in specs/001-agent-workspace/quickstart.md. (FR-020)
- [x] T002 Expand each capability group into concrete operation rows with fixtures/provenance in specs/001-agent-workspace/contracts/mcp-capabilities.md; preserve every current panel action. (FR-014, SC-004)
- [x] T003 [P] Add bounded input/output schemas and named domain enums in lib/agents/schemas.ts and lib/agents/model.ts using contracts/reporting-api.md. (FR-004, FR-019)

## Phase 2: Foundation

Owner-safe persistence, operations, retention, and auth feasibility must pass before dependent stories.

- [x] T004 Add additive agent/access/receipt schema in lib/db.ts and owner deletion coverage in lib/auth/users.ts; read SQL rules and verify old-version compatibility. (FR-004, FR-010, FR-011)
- [x] T005 Implement typed owner/scopes/resource-audience principal in lib/access/principal.ts; no identity from payloads or fabricated cookies. (FR-010, FR-015)
- [x] T006 Implement atomic local mutation receipts, 30-day content-free DELETE receipts, explicit expired externalId reuse, expected-version conflicts, and stale-request rejection in lib/access/receipts.ts. (FR-009, SC-006)
- [x] T007 Add external outcome reservation/reconciliation in lib/access/receipts.ts; unresolved receipts cannot expire, terminal receipts expire 30 days after resolvedAt, and uncertain writes never retry blindly. (FR-009, FR-016)
- [x] T008 Implement read-time expiry and bounded hourly/startup cleanup in lib/agents/retention.ts and instrumentation.ts: "30 days after its last accepted activity"; reads/retries never renew. (FR-011, FR-012, SC-007)
- [x] T009 Implement logical backup/restore excluding agent data in scripts/backup.ts and scripts/restore.ts; preserve existing personal/provider data, replace unsafe raw backup jobs and invalidate all restored tokens/grants before service startup. (FR-012, SC-007)
- [x] T010 Validate migrations, two-user ownership, duplicate/concurrent writes, expired externalId reuse, DELETE replay, expiry boundaries, cleanup failure and restore revocation in tests/lib/agents/storage.test.ts and tests/lib/access/receipts.test.ts. (FR-009, FR-010, FR-011, FR-012, SC-005, SC-006, SC-007)
- [x] T011 Prove official MCP v2 and oidc-provider interoperability on Node 24 in tests/mcp/oauth-feasibility.test.ts; pin compatible dependencies in package.json/package-lock.json only after the gate passes. Use a disposable local reverse-proxy harness independent of T037; verify real-client discovery, audience, consent, persistence and revocation before dependent OAuth implementation. (FR-013, FR-017, SC-008)

## Phase 3: US1 — Task kanban and detailed work (P1)

One task per card, responsible agent/session, accurate status and navigation.

**Independent test**: Seed two users and several tasks; home/details isolate ownership and preserve URL state.

- [x] T012 [US1] Implement owner-scoped agents/sessions/tasks read-write operations and live queries in lib/agents/store.ts and lib/agents/operations.ts; session heartbeat only renews explicitly targeted tasks. (FR-004, FR-008, FR-011)
- [x] T013 [US1] Implement validated browser read routes in app/api/agents/route.ts and app/api/agents/tasks/[id]/route.ts; no expired/private records. (FR-002, FR-010, FR-012)
- [x] T014 [US1] Build task cards and lifecycle columns plus two-second foreground snapshot polling in components/agents/AgentTaskBoard.tsx; "Each kanban card MUST represent one task" and separate freshness from task status. (FR-003, FR-004, SC-001)
- [x] T015 [US1] Replace home main content in app/(app)/page.tsx and preserve old panel access at app/(app)/workspace/page.tsx with navigation in components/shell/AppShell.tsx. (FR-001)
- [x] T016 [US1] Build session/work overview and task details in app/(app)/agents/page.tsx and app/(app)/agents/tasks/[id]/page.tsx, showing activity and source links. (FR-002, SC-001)
- [x] T017 [US1] Make filters/sort/pagination/tab URL-driven and add empty/error/stale/keyboard/mobile states in components/agents/AgentTaskBoard.tsx and tests/components/AgentTaskBoard.test.tsx. (FR-018, FR-019)
- [x] T018 [US1] Verify card-to-task details, multi-task session, cross-user isolation and expired results in tests/api/agents/read.test.ts and tests/components/AgentWorkspace.test.tsx. (FR-001, FR-002, FR-003, SC-001, SC-005)

## Phase 4: US2 — Self-service reporting access (P1)

Generate/revoke a token and onboard any supported agent without operator intervention.

**Independent test**: Follow generated instructions, report work, observe cards, revoke access and verify denial.

- [x] T019 [US2] Implement random secret generation, digested storage, metadata listing and revocation in lib/access/credentials.ts. (FR-005, FR-006, FR-017)
- [x] T020 [US2] Add session-authenticated CSRF-protected token administration in app/api/agent-access/tokens/route.ts and app/api/agent-access/tokens/[id]/route.ts. (FR-005, FR-010)
- [x] T021 [US2] Implement the reporting contract in app/api/v1/agents/ with shared schemas/operations, bounded inputs, idempotency and no-store errors. (FR-008, FR-009, FR-019, FR-020)
- [x] T022 [US2] Adjust exact bearer route handling in middleware.ts while retaining legacy cookie-route protection; reject ambiguous auth and owner overrides. (FR-010, FR-015)
- [x] T023 [US2] Build token/onboarding UI in app/(app)/access/page.tsx and prompt generation in lib/agents/onboarding.ts; configured origin and placeholders only, no secret in saved prompt. (FR-005, FR-006, FR-007, SC-003)
- [x] T024 [US2] Test token disclosure/revocation, every reporting route, version conflict, duplicate retry, oversized input and wrong user in tests/api/agents/reporting.test.ts and tests/lib/access/credentials.test.ts. (FR-006, FR-009, FR-010, FR-017, FR-019, FR-020, SC-005, SC-006, SC-008)
- [x] T025 [US2] Validate generated reporting instructions from Claude/Codex/Gemini and record onboarding time in specs/001-agent-workspace/quickstart.md. (FR-007, SC-003)

## Phase 5: US3 — OAuth MCP and task workflows (P1)

Complete agent/personal-task workflows through MCP with scoped OAuth access.

**Independent test**: All three real clients complete grant/call/refresh/revoke; every task operation has parity.

- [x] T026 [US3] Implement provider configuration, sole app-owned migrations, busy_timeout=5000, bounded DCR registration/expiry and encrypted persistent adapter in lib/oauth/provider.ts and lib/oauth/adapter.ts, plus scripts/oauth-server.ts and tsconfig.oauth.json; compile dist/oauth-server.js via a new build:oauth script integrated into build/deploy, and use library PKCE/code/token lifecycle. (FR-013)
- [x] T027 [US3] Implement the Unix-socket authenticated interaction handoff and explicit consent in lib/oauth/interaction.ts and app/(app)/access/consent/page.tsx; bind nonce to client/resource/redirect/PKCE/scopes, reject cross-interaction reuse, and never trust a query-supplied owner. (FR-010, FR-013)
- [x] T028 [US3] Implement grant listing/revocation and authoritative per-call checks in lib/access/grants.ts and app/api/agent-access/grants/route.ts. (FR-015, FR-017, SC-008)
- [x] T029 [US3] Add canonical protected-resource metadata in app/.well-known/oauth-protected-resource/mcp/route.ts and verified OAuth auth via private-socket introspection in lib/mcp/auth.ts; no positive revocation-delaying cache. (FR-013, FR-015)
- [x] T030 [US3] Implement stateless Streamable HTTP at app/mcp/route.ts and lib/mcp/server.ts; exact public auth routing in middleware.ts; reject wrong audience and invalid origin. (FR-010, FR-013, FR-020)
- [x] T031 [US3] Implement scoped capability registry and structured tool errors in lib/mcp/registry.ts; explicit owned connectionId/provider selection, input/output schemas, mutability and completeness required. (FR-014, FR-015, FR-016, FR-019)
- [x] T032 [US3] Expose agent reporting/read/lifecycle tools through lib/mcp/tools/agents.ts with the same retention and receipts. (FR-008, FR-009, FR-011, FR-012, FR-021)
- [x] T033 [US3] Extract and expose personal-task CRUD, provider-aware completion/reopen, board, subtasks and query/grouping via lib/operations/tasks.ts and lib/mcp/tools/tasks.ts. (FR-014, SC-004)
- [x] T034 [US3] Extract supported connection metadata/non-secret-update/delete/test/toggle operations and browser-only secret-setup links in lib/operations/connections.ts and lib/mcp/tools/connections.ts; reject secret fields in MCP inputs and never return stored secrets. (FR-006, FR-014, FR-015)
- [x] T035 [US3] Expose focus targets and source-authorized focus creation in lib/operations/focus.ts and lib/mcp/tools/focus.ts with explicit agenda:focus scope, persisted receipts/uncertain-outcome reconciliation from T007, and no general agenda adapter. (FR-014, FR-015)
- [x] T036 [US3] Test metadata, PKCE failure, code replay, scopes/audience, refresh reuse, restart, denied consent, cross-interaction/user handoff swap, unauthorized socket caller, revoked/deactivated user and task parity in tests/mcp/auth.test.ts and tests/mcp/tasks.test.ts. (FR-013, FR-014, FR-015, FR-017, SC-004, SC-005, SC-008)
- [x] T037 [US3] Add loopback companion service, reverse proxy discovery routes, startup/rollback and health checks in deploy/daily-web-oauth.service, deploy/traefik-router-snippet.yml, deploy/traefik-service-snippet.yml, deploy/publish.sh and deploy/healthcheck.sh. (FR-013, FR-020)
- [x] T038 [US3] Run real Claude/Codex/Gemini OAuth workflows behind the development proxy; record exact versions and outcomes in specs/001-agent-workspace/quickstart.md. (FR-013, FR-017, SC-008)

## Phase 6: US4 — Jira parity (P2)

Every existing Jira action is available with identical ownership/provider permissions.

**Independent test**: Expanded Jira operation inventory has success, denial, invalid-input and failure evidence.

- [x] T039 [US4] Capture missing sanitized Jira responses and provenance in tests/fixtures/jira-write/; derive validation fixtures from real responses. (FR-016, FR-019)
- [x] T040 [US4] Extract work views, filters, people/following, watches and summaries into lib/operations/jira.ts while reusing lib/jiraFilters.ts and lib/standup.ts. (FR-014)
- [x] T041 [US4] Extract transitions, approvals, comments, flags, fields, stories/epics and individual/bulk start dates into lib/operations/jira.ts; preserve current restrictions. (FR-014, FR-015)
- [x] T042 [US4] Migrate app/api/jira/ handlers to shared operations without broadening supported user actions or requiring MCP credentials for the browser. (FR-010, FR-014)
- [x] T043 [US4] Expose every Jira inventory operation in lib/mcp/tools/jira.ts with explicit connection selection and validated pagination/completeness. (FR-014, FR-015, FR-016)
- [x] T044 [US4] Test Jira parity, no cross-connection access, unknown enums, partial pages and uncertain-write reconciliation in tests/mcp/jira.test.ts and tests/lib/operations/jira.test.ts. (FR-014, FR-015, FR-016, FR-019, SC-004, SC-005)

## Phase 7: US5 — GitHub parity (P2)

Every existing GitHub action has equivalent state/SHA checks and MCP behavior.

**Independent test**: Expanded GitHub operation inventory passes including cross-module Jira sync.

- [x] T045 [US5] Capture missing sanitized GitHub fixtures/provenance in tests/fixtures/github/; derive mocks and unknown-enum fixtures from contracts. (FR-016, FR-019)
- [x] T046 [US5] Extract work views/filters, tracked repos and action orchestration into lib/operations/github.ts, preserving lib/integrations/github/actions.ts checks. (FR-014, FR-015)
- [x] T047 [US5] Migrate app/api/pulls/ handlers to shared operations and implement lib/mcp/tools/github.ts for reviews/comments/reviewers/merge/rerun/repos. (FR-014, FR-015)
- [x] T048 [US5] Expose Jira-sync suggestion/application in lib/mcp/tools/github.ts with both providers/scopes, current transition checks and persisted uncertain outcome handling. (FR-014, FR-015, FR-016)
- [x] T049 [US5] Test current-SHA conflicts, self-review/draft/permission denial, partial reads, external failures and each inventory action in tests/mcp/github.test.ts and tests/lib/operations/github.test.ts. (FR-014, FR-015, FR-016, SC-004, SC-005)

## Phase 8: Integrated acceptance and delivery

Finish with measured, reproducible evidence on the final implementation tree.

**Independent test**: No incomplete parity row; retained data, OAuth and UI verified end-to-end.

- [x] T050 Add regression checks matching the capability inventory in tests/mcp/parity.test.ts and self-contained OAuth/expiry/parity gates to .github/workflows/ci.yml. (FR-014, SC-004)
- [x] T051 Add/execute report-to-visible load scenarios in tests/performance/agents.ts and record p95/p99/memory/cleanup results in specs/001-agent-workspace/quickstart.md. (FR-020, SC-002)
- [x] T052 Verify no protected data leaks through logs, prompts, credential lists, caches, backup or multi-user tool output in tests/mcp/isolation.test.ts. (FR-006, FR-010, FR-012, SC-005, SC-007)
- [x] T053 Update README.md and .env.example for reporting, OAuth companion configuration, revocation, retention, migration, three-client onboarding and no remote agent execution. (FR-007, FR-013, FR-021)
- [x] T054 Run affected checks, full tests/build/audit, applicable react-doctor/react-scan checks, real-client/proxy and browser unhappy paths; record exact final-tree outcomes in specs/001-agent-workspace/quickstart.md. (SC-001, SC-002, SC-003, SC-004, SC-005, SC-006, SC-007, SC-008)

## Dependencies and Execution Order

Phase 1 → Phase 2 → US1 and US2 → US3 → US4 → US5 → integrated gate.
US1/US2 can be developed independently after the foundation, but the usable first
release includes both plus US3 OAuth/task parity. US3 first proves OAuth before
dependent MCP modules. US5 Jira-sync specifically depends on US4. Shared files
(lib/db.ts, middleware.ts, registry.ts, provider operations) require serialized edits.

## Parallel Opportunities

After contract freeze, schema design (T003) can run independently of the baseline
and inventory documentation. After the foundation, UI US1 and credential/reporting
US2 work can run independently until integration. Within each story, fixture
capture and test design can run separately from UI work; shared operation files
are never edited concurrently. US4 and US5 fixture capture can overlap; Jira-sync
integration waits for US4. This is task scheduling, not permission to skip gates.

## Implementation Strategy

Deliver the M1+M2 vertical slice first, then the Jira and GitHub modules, with
per-module tests on the integrating branch. Do not call partial parity complete.
Preserve existing user data and credentials; no destructive migration or remote
agent execution. A failed authorization or compatibility gate stops dependent
implementation. Run final checks after the last edit before commit/push.

All operation groups must be expanded to concrete entries during T002; the matrix
is the completion gate and any newly discovered panel action is added to its
existing story before implementation, not silently deferred.

## Implementation status and documented deviations

Local implementation and independent source review are complete. Release acceptance
is not equivalent to every external operational task being complete. Keep these
items open rather than inferring success from the registry or offline suite:

- T002/T039/T044/T045/T049: the 58-operation inventory is expanded, but complete
  per-operation live Jira/GitHub success/refusal/failure fixture coverage is not
  available. Existing captured provider contracts and their tests are reused;
  no production mutations were performed solely to collect fixtures.
- T009: logical backup/restore and restored-access revocation are implemented and
  tested; raw backup jobs on a deployed host still require audit/replacement.
- T025: actual OAuth client login and read tool calls are proven; generated PAT
  onboarding prompts were tested for origin/placeholder safety, not timed as
  three separate end-user onboarding studies.
- T042/T047: existing browser handlers share provider domain adapters with MCP,
  but have not all been migrated onto the new operation facade. Their existing
  response contracts are preserved and tested. This is an explicit plan deviation.
- T011 feasibility used real provider HTTP early; the complete three-client proof
  was finished on the integrated production-style local build, not before every
  dependent source file was implemented. This process deviation is recorded.
- Client-specific automatic refresh on actual access-token expiry remains a
  separate acceptance gap; the provider HTTP tests verify rotation/replay/restart.
- No push, pull request, deployment or production acceptance was requested or done.

Exact checks, approval scope and sanitized benchmark/client artifacts are recorded
in quickstart.md, reviews/implementation-review-4.md and validation/.

## Continuation evidence

The original local checkpoint `d1421dd` left nine items open. The continuation
closed route migration and all-operation coverage with direct Jira/GitHub and
personal-task suites, documented captured/derived contracts, measured generated
reporting instructions in the three installed clients, and added first-upgrade
OAuth services plus scheduled logical backups. Production cron/systemd inspection
was read-only; no unsafe application backup job was found to replace. See
`contracts/mcp-capabilities.md`, `contracts/github-parity.md`,
`validation/reporting-clients.json` and `../../docs/backup-and-services.md`.
Natural-expiry client refresh and the integrated release gate are recorded in
`quickstart.md`; completed implementation tasks do not alone certify a release.

## Follow-up: agent task and subtask creation

- [x] T055 Implement FR-030/FR-032 owner-scoped one-level hierarchy, additive migration, atomic retention propagation and deletion protection.
- [x] T056 Implement FR-030 API/MCP hierarchy inputs, filtered reads and safe generated onboarding instructions.
- [x] T057 Implement FR-031 macro home board and independently paginated subtasks with parent/child navigation.
- [x] T058 Validate hierarchy, migration, authorization, idempotency, retention and UI; complete independent review and affected release gates.
