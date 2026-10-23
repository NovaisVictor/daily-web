# Implementation Validation Guide

Implementation checks below use only disposable development users and sanitized
fixtures. No production provider writes or deployment were performed. The verified
results and remaining acceptance gaps are recorded first; the rest of this document
is the reproducible validation procedure.


## Verified implementation evidence — 2026-10-23

Branch: `feature/agent-workspace`, based on `6a5d646022703870c70f52d0615dd03c7578f1e6`.
The repository was initially clean. Codebase Memory was fully indexed before
structural exploration. Remote migration versions were checked: maximum 14;
this additive migration is version 15. Existing CI runs `npm test`, the build,
and production dependency audit at the critical threshold.

- Baseline: 2,385 tests passed; production build passed; no critical production
  dependency advisory. One moderate `ip-address` advisory was already present.
- Integrated implementation suite: 2,515 tests across 165 files passed after
  the final provider-refusal corrections. No application source edits followed
  this passing suite.
- `npm run build`: companion TypeScript/bundle and optimized Next production build
  passed. The first attempt caught a benchmark type error; that error was corrected
  before the passing build. External runtime socket paths are explicitly excluded
  from Turbopack artifact tracing.
- Focused remediation: 463 provider/operation/access tests passed, covering local atomic
  rollback, deterministic missing resources, safe uncertain external retries,
  non-secret connection settings, and maximum-length bulk idempotency keys.
- Core retention: 22 focused tests passed, including a 1,200-event history, bounded
  total deletion batches, content-free deletion tombstones, secure deletion and
  WAL checkpointing. No forensic erase guarantee for filesystem snapshots/SSD.
- Browser acceptance was repeated against the optimized production application
  behind a disposable loopback reverse proxy. Passed: empty state, two tasks in
  one session, reporting/lifecycle/details/timeline, URL navigation and refresh,
  legacy workspace access, two-user isolation, 500 and unknown-enum errors, prompt
  without secrets, UI token revocation followed by 401, and zero page errors.
- Real browser load: 20 users, 100 sessions, 10,000 retained tasks, 100 reports at
  10/s, 20 visible Chromium contexts. All 100 reports appeared in React cards;
  p95 1,834.47 ms, p99 1,867.93 ms, maximum 1,869.33 ms, zero errors. Application
  RSS 202.54 MB initially, 345.52 MB peak. Artifact:
  `validation/agents-browser-performance.json`. This measures local proxy + Next
  production + React DOM and natural two-second polling; physical display paint,
  production network latency and agents' own reporting overhead are excluded.
- OAuth provider tests exercise actual HTTP discovery/DCR/PKCE/token exchange,
  persistence/restart, replay/rotation, immediate revocation, private-socket
  verification, browser-bound consent, scope/audience isolation and bounded
  registrations. Real Claude Code 2.1.309, Codex CLI 0.163.0 and Antigravity
  (agy) 1.4.6 completed DCR, browser consent, PKCE authorization and an actual
  `agents_sessions_list` call returning one item. Each used the disposable
  production runtime; agy required one-shot approval for the exact read-only call.
  Revoked grants returned 200 from the browser API; Codex subsequently received
  `AuthRequired` with `invalid_token` at transport initialization. Artifact:
  `validation/oauth-clients.json`. Provider refresh/replay/restart tests are
  distinct from these real-client checks; timed client auto-refresh was not tested.
- Deployment script syntax passed. Isolated shell mocks verified normal publish,
  rsync failure and application restart failure. No live service deployment or
  systemd/Traefik production acceptance was performed.

### Explicit remaining acceptance and operational gaps

- A standalone official Gemini CLI was unavailable; the Gemini-family result is
  from installed Antigravity agy. All three installed clients completed positive
  tool calls before the final integrated rebuild with frozen OAuth sources. After
  that rebuild and a companion restart, agy rejected the revoked fixture grant
  with `initialize: Unauthorized [Auth Needed]`, as expected. Positive tool calls
  were not repeated after that last rebuild. All temporary client configurations
  and fixture grants were removed/revoked; disposable CLI/browser drivers stopped.
- Independent implementation review 4 and its final exception-subclass delta
  review both approved the source. The final optimized production build passed after the source freeze.
- The capability inventory lists 58 registered tools. Registry/scope/schema and
  lifecycle tests are executable; successful and failed live-provider evidence
  for every Jira/GitHub write is not yet captured. Existing sanitized captures
  are reused with their recorded provenance. No production write was made just
  to manufacture a fixture.
- Existing cookie-authenticated Jira/GitHub handlers continue to call the same
  provider domain adapters used by the new application operations. They have not
  all been migrated to the new operation facade; their browser response contracts
  are preserved. This is an implementation-plan deviation, not a claim that such
  route migration was executed.
- Logical backup/restore excludes agent content and revokes restored access.
  Existing host-level raw backup jobs have not been audited/replaced on a deployed
  host. Deployment must do this before asserting the retention policy covers
  external snapshots and backups.
- Uncertain external writes fail closed and remain persisted. The internal
  reconciliation helper requires authoritative server verification; a generic
  provider reconciliation MCP tool is not yet exposed. Clients must inspect
  provider state and must never retry an unknown outcome under a new key blindly.
- React Doctor 0.9.14: zero errors, 51 advisory warnings. Reviewed categories include
  supported-but-deprecated Zod compatibility methods, deliberate sequential receipt
  writes, polling effects, URL state and edit-version snapshots. No baseline or
  allowlist was expanded. React Scan has an instrumentation/init workflow rather
  than a static gate; no unrequested runtime instrumentation was installed.
- No push, PR, deployment or production acceptance is asserted by local checks.

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
