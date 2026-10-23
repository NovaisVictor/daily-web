# Implementation Validation Guide

Validation uses disposable users and sanitized fixtures. Captured provider reads
and derived mutation replies are identified explicitly; no production Jira or
GitHub write was performed to manufacture a fixture. Deployment acceptance is
separate from local implementation validation.

## Verified evidence — 2026-10-23

The feature began from `6a5d646022703870c70f52d0615dd03c7578f1e6` on
`feature/agent-workspace`. Codebase Memory was indexed before structural work.
The additive SQLite migration is version 15; remote migration versions were
checked before introducing it. Existing CI runs the native tests, production
build and production dependency audit at the critical threshold.

- Original baseline: 2,385 tests, production build and critical dependency gate
  passed. The original implementation checkpoint `d1421dd` passed 2,515 tests
  across 165 files and its optimized build. Ruflo-tracked independent review 4
  and its exception-subclass delta approved that checkpoint.
- Continuation pre-integration gate: **2,699 tests across 171 files passed**.
  This is an intermediate gate, preceding integration of the newer upstream task
  form and final release validation; it is not represented as the release gate.
- Jira: all 19 shared operations have direct success/result-schema, input, scope,
  owner and deleted-user cases, provider failures where external, refusal/retry,
  replay and mixed bulk outcomes. All browser Jira action handlers now use
  shared `jiraActions`, preserving cookie/Origin guards and HTTP contracts.
- GitHub: all ten operations and seven browser action handlers use shared
  orchestration. Focused GitHub/core validation passed 374 tests. Current SHA,
  self-review/draft/permission refusal, malformed output, partial reruns and
  persistent replay without duplicate provider effects are covered. See
  `contracts/github-parity.md` and the per-operation capability inventory.
- Personal tasks, connections and focus: direct shared-operation tests cover
  task CRUD, completion/reopen/board moves, every subtask action, provider
  failure/uncertainty/replay, private metadata, connection setup/edit/test/remove,
  ownership and focus creation from task, Jira and GitHub sources.
- Generated reporting instructions were copied unchanged from the browser API
  and executed by real Claude Code, Codex and Antigravity agy (Gemini family).
  The reporting token was supplied through each child process environment only.
  Each run created a working task with progress, then verified revocation and
  HTTP 401. Measured elapsed time: Claude **13.092 s**, Codex **13.081 s**, agy
  **81.575 s**, including agy's one-shot command approval. Artifact:
  `validation/reporting-clients.json`; reproduction: `scripts/validation/README.md`.
- Actual OAuth clients completed DCR, PKCE, browser-bound consent and a real
  `agents_sessions_list` invocation. Natural-expiry testing found and fixed
  Codex's refresh-scope incompatibility: `offline_access` is no longer advertised;
  issued refresh tokens still follow the provider's explicit policy. Regressions
  reject ungranted scopes and escalation; final timed client proof is separate.
- The bounded Next proxy serves `/oauth/` and authorization metadata through the
  existing public origin. Nine proxy tests plus middleware isolation tests cover
  canonical Host, cookies, safe redirects, CORS preflight, payload/deadline bounds,
  unknown paths and companion failure. No global Traefik change is required.
- Deployment and backup: 21 focused tests, OAuth compilation, TypeScript and
  shell/Node syntax passed. Compiled backup and restore commands ran against a
  disposable database: retained settings, zero agent rows and private 0600 files.
  The idempotent installer checks unmanaged units before stopping/copying, installs
  the companion on first upgrade, requires app and OAuth health, and enables a
  daily logical backup timer. Existing backups are preserved. A read-only host
  audit inspected 17 cron files and systemd inventory and found no application
  raw backup job to replace. This does not certify off-host storage snapshots.
  See `validation/deployment-readiness.json` and `../../docs/backup-and-services.md`.
- Browser acceptance against the optimized disposable application passed empty
  state, two task cards in one session, lifecycle/details/timeline, URL navigation
  and refresh, legacy workspace, two-user isolation, 500/unknown-enum failures,
  prompt without secrets, token revocation/401 and zero page errors.
- Browser load: 20 users, 100 sessions, 10,000 retained tasks, 100 reports at 10/s,
  20 Chromium contexts. All reports appeared in React cards: p95 **1,834.47 ms**,
  p99 **1,867.93 ms**, maximum **1,869.33 ms**, zero errors. Application RSS
  202.54 MB initially and 345.52 MB peak. Artifact:
  `validation/agents-browser-performance.json`. Local proxy/Next/DOM/polling are
  included; physical display paint and production network latency are excluded.
- Core retention passed bounded expiry/cleanup and logical restore tests,
  including a 1,200-event history, 500-row cleanup batches, content-free tombstones,
  secure deletion and WAL checkpointing. No filesystem/SSD forensic erase claim.
- Final React Doctor changed-source scan: zero errors, 53 advisory warnings.
  Full-repository scan: seven errors, all in files byte-identical to current
  `origin/main`; 198 warnings. The warning delta from the earlier 51 is a bounded
  serial Jira receipt loop and a guarded canonical-origin URL parse; Zod helper
  warnings moved without increasing their total. No baseline/allowlist was changed.
  React Scan offers instrumentation/init rather than a static gate; unrequested
  runtime instrumentation was not installed.

## Release gates still being executed

The continuation's independent review, integration of upstream `main`, final
integrated tests/build/audit, timed real-client refresh and new Next-proxy client
smoke must all complete before delivery. Source/test completion alone is not a
production acceptance assertion. No deployment is claimed by the local evidence.

## Practical boundaries

- Gemini-family acceptance uses installed Antigravity agy 1.4.6. A standalone
  official Gemini CLI was not installed; no separate-client result is claimed.
- External writes with unknown outcomes persist and require reconciliation.
  Inspect authoritative provider state before issuing another mutation; never
  blindly retry using a new key. No general automatic reconciliation tool is
  advertised.
- Live provider account permissions, network conditions and off-host backup
  systems are not inferred from offline fixtures or local benchmark results.

## Prerequisites

Node 24; repository dependencies from the existing npm lockfile; disposable SQLite
DB; two development users A/B; development Jira/GitHub connections when provider
capture is needed; OAuth companion and reverse proxy configuration from the plan.
No secrets in copied commands, shell history, prompts, or test output. Use existing
secret injection mechanisms. Back up the development DB before migration tests.

## Commands after implementation

Run `npm ci` only when dependencies are required, then use existing scripts:

```sh
npm test -- tests/lib/agents tests/lib/access tests/api/agents tests/mcp
npm test -- tests/lib/operations tests/api tests/components
npm test
npm run build
npm audit --omit=dev --audit-level=critical
```

Capture long outputs to a temporary log and inspect failure summaries. Discover
`react-doctor --help` and `react-scan --help`, then run applicable stack checks
with their documented options. Do not invent flags or claim either tool substitutes
for the repository tests. Record actual commands/results in the implementation PR.

## First vertical slice

1. User A generates a token: secret appears once; listing reveals only metadata.
2. Generated prompt has the deployment address and credential placeholder.
3. Follow those instructions from Claude, Codex, and Gemini: register an agent,
   start a session, create two tasks, transition one and report progress.
4. Verify two task cards even when assigned to one session. Open each detail and
   verify the correct history and current assignment; refresh and use back/forward
   with filters, pagination, and active tab preserved in URL state.
5. Verify keyboard movement/detail access, empty state, request failure, stale
   agent label, mobile layout, and navigation to all legacy panels.
6. Repeat a report; no new task/activity or retention extension. Send an older
   version and an unknown enum; reject visibly without changing current state.
7. Revoke the token and attempt its next operation; reject. B cannot read, change,
   or infer A's resources using copied IDs.

## OAuth and MCP

For each of the three real clients, run discovery → login → consent → list tools
→ call scoped tool → refresh → process restart → call again → revoke → denied call.
Also test denied consent, bad PKCE, replayed code, wrong audience, unknown scope,
redirect mismatch, inactive user, refresh-token reuse, and absent browser cookies.
Test private-socket introspection, startup migration ordering, DCR saturation
and unused-client cleanup. Verify /mcp is usable with OAuth alone and legacy protected API remains cookie-only.
Record client and SDK versions and origin used. Do not put authorization codes or
tokens in evidence logs. Test missing provider/companion with auth failing closed.

## Supported-module parity

Expand every row in `contracts/mcp-capabilities.md` into concrete operation test
cases. Cover happy path, 401, 403, 400, missing/foreign resource, provider timeout,
partial pages, and conflict for every applicable operation. Derive mocks from
sanitized captured responses. Test an unknown provider enum explicitly.

Jira: followed-person views, all filters and summary, follow/watch toggles,
transitions, approvals, comments, flags, fields, stories/epics, and start-date bulk
operations. GitHub: all work views/filters, repository management, reviews/comments,
reviewer requests, merge, rerun, and Jira sync. Personal tasks: CRUD, completion,
reopen, board moves, subtasks, and supported provider behavior. Include shared
browser-only secret setup links, MCP rejection of secret inputs, non-secret
connection management/test and focus creation with separate permissions.

For external uncertain writes, interrupt after submission, restart, and retry
same operation: reconcile state or return uncertain; never blindly issue it twice.
Test current SHA changes between display and GitHub mutation.

## Retention, migration, and backup

Use a controllable clock. Test at 30 days minus 1 ms, exactly 30 days, and plus 1 ms.
New activity extends expiry; reads, duplicate retries, unrelated session heartbeats,
and future client timestamps do not. Test individual event expiry under a live
parent, expired task updates, session references, user deletion, and cleanup errors.

Restart with expired data and verify all transports hide it before cleanup runs.
Restore a supported logical backup: agent data is absent and personal data remains.
Inspect caches and captured logs for expired content. Revoke access, restore an older backup, and verify it stays unusable.
Test expired externalId reuse and content-free DELETE replay. Test migration from current
schema and older-app startup against the new schema; no destructive down migration.

## Load and final delivery

Benchmark 20 users/100 agent sessions/10000 live tasks at 10 reports/second. Record
p95/p99 request and report-to-visible times, cleanup batch duration, memory, and
overload errors. Meet spec p95 <=5 seconds without unbounded buffers or cross-user
cache reuse. Re-run affected gates after the final edit; then commit and push using
the git-push workflow only when implementation delivery is authorized.
