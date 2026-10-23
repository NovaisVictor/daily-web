# Implementation Plan: Daily Web Agent Workspace

**Branch**: documentation remains on `main`; feature identity is `001-agent-workspace`.
**Date**: 2026-10-23. **Spec**: [spec.md](spec.md).
**State**: Proposed implementation plan. No application implementation performed.

## Summary

Make home a task-based agent kanban, with session identity on each card and a
separate detailed workspace. Reported work expires 30 days after last activity.
Add personal reporting credentials and OAuth-authorized MCP with complete supported
module parity. Deliver agents/access first, then Jira and GitHub independently.

Reuse the existing user accounts, vault, integration clients, SQLite migrations,
and component system. Put business operations behind typed user-scoped functions
shared by browser routes and MCP. Keep remote provider writes synchronous with
persisted operation receipts and explicit uncertain outcomes.

## Technical Context

**Language/Version**: TypeScript; Node 24 (local v24.15.0 confirmed).
**Primary Dependencies**: Existing Next.js 16, React 19, better-sqlite3 and Vitest;
add official MCP server v2, its compatible schema dependency, and oidc-provider
with its types only during implementation. Pin versions after the interoperability
spike and security review. No framework rewrite or package-manager migration.
**Storage**: Existing SQLite/WAL; additive agent, access, and operation-receipt
records. Persistent encrypted OAuth-provider adapter. No generic deletion of
personal tasks or upstream Jira/GitHub data.
**Testing**: Vitest/unit/route/component, actual three-client MCP flow, SQLite
migration/expiry/restore checks, Playwright manual or scripted browser acceptance.
**Target Platform**: Current Linux/systemd/Traefik deployment and desktop/mobile web.
**Project Type**: Existing web application plus local OAuth companion process.
**Performance Goals**: p95 report-to-visible <=5 seconds at 100 simultaneous
sessions across 20 users, 10000 retained tasks and 10 accepted updates/second;
measure p95/p99 and document capacity rather than extrapolating production scale.
**Constraints**: No secrets in logs/prompts; 64 KiB reporting payload maximum;
local handlers 5-second deadline, upstream actions 15-second timeout, OAuth network
fetches 5 seconds; bounded 100-row pages and 500-row cleanup batches. Enforce
bounded concurrency and documented retry/backpressure; tune from benchmark evidence.
**Scale/Scope**: Initial benchmark is an engineering test profile, not a user quota.
Supported product modules are agents, personal tasks, Jira, GitHub, their connections,
and the existing shared focus action only. Other module MCP adapters are later work.

## Constitution Check

| Principle | Before research | After design | Required implementation evidence |
| --- | --- | --- | --- |
| User isolation and secrets | Pass | Pass by design | Two-user route/tool tests; redacted logs and consent isolation |
| Equivalent authorization | Pass | Pass by design | One principal/capability layer used by all transports; exact parity tests |
| Explicit contracts | Pass | Pass by design | Runtime input/output validation; captured fixtures; unknown enum errors |
| Minimal modular change | Pass | Pass with justified companion | Reuse existing stack; no provider rewrites; URL state; additive migration rollback |
| Evidence-backed delivery | Pass | Pass by design | Per-module gates plus final integrated gate on final tree |

The user-approved exception to feature parity is browser-only secret entry; MCP
returns setup links. This preserves, rather than exempts, the constitution.

The companion process is justified by the established OAuth library's Node HTTP
interface and SDK guidance against implementing a new authorization server with
legacy helpers. It owns protocol handling and token issuance only. The app keeps
account authentication and consent UI. No operational readiness is claimed yet.

## Project Structure

Documentation resides in this directory: `spec.md`, `research.md`, `data-model.md`,
`quickstart.md`, `contracts/`, `checklists/requirements.md`, and `tasks.md`.

Existing files reused or changed:

- `app/(app)/page.tsx`: macro task kanban.
- `components/TasksPanel.tsx`, `components/JiraPanel.tsx`, `components/PullsPanel.tsx`:
  preserve current actions while sharing typed operations.
- `lib/api/context.ts`, `lib/api/jira.ts`, `lib/api/pulls.ts`, `middleware.ts`:
  retain browser auth; add explicit alternate-transport boundaries.
- `lib/tasks/`, `lib/integrations/jira/`, `lib/integrations/github/`: reuse providers.
- `lib/db.ts`, `lib/auth/users.ts`, `instrumentation.ts`: additive schema, deletion
  coverage, and bounded cleanup lifecycle.
- `deploy/`, `.github/workflows/ci.yml`, `.github/workflows/deploy.yml`:
  add companion lifecycle, health, proxy discovery, and required gates.

Proposed new files/directories (not yet implemented):

```text
lib/agents/             model.ts, schemas.ts, store.ts, operations.ts, retention.ts
lib/access/             principal.ts, credentials.ts, receipts.ts, grants.ts
lib/operations/         tasks.ts, jira.ts, github.ts, connections.ts, focus.ts
lib/mcp/                server.ts, registry.ts, auth.ts, tools/
lib/oauth/              provider.ts, adapter.ts, interaction.ts
app/api/v1/agents/      reporting route handlers
app/api/agent-access/   browser credential/grant management
app/mcp/route.ts        authenticated Streamable HTTP
app/.well-known/        resource metadata
app/(app)/agents/       detail workspace and task detail
app/(app)/workspace/    existing panels outside home
app/(app)/access/       token, prompt, and OAuth consent management
components/agents/     task kanban, cards, detail, onboarding
scripts/oauth-server.ts   compiled to dist/oauth-server.js for systemd
tsconfig.oauth.json       companion build configuration
scripts/backup.ts       logical backup excluding agent history
scripts/restore.ts      retention-safe restore
```

Existing personal task state stays compatible. Agent lifecycle is a distinct enum;
reuse visual primitives without forcing the richer lifecycle into todo/doing/done.

## Delivery Sequence and Gates

1. **Foundation**: shared principal, contracts, additive persistence, operation
   receipts, retention, and OAuth/provider interoperability proof. A failed auth
   proof stops dependent MCP work; it is not excused by green unit tests.
2. **M1 + M2 first vertical slice**: reporting credentials, prompt generation,
   reporting API, task kanban, details, personal-task MCP, OAuth consent/revocation.
   Deliver a usable path from an agent report to a visible card.
3. **M3 Jira**: inventory each action and query, extract shared operations, add
   corresponding tools and focused permission/provider-error tests.
4. **M4 GitHub**: same workflow, preserving SHA/state checks and Jira synchronization.
5. **Integrated gate**: current module parity matrix, cross-user tests, no-secrets
   inspection, three-client OAuth flows, retention/restore proof, report latency,
   complete tests/build/audit, and final-tree verification before delivery.

## Retention and Failure Policy

Follow [data-model.md](data-model.md). Event history expires independently of a
live task snapshot. Heartbeat must explicitly target a task to renew that task;
reads and duplicate reports cannot extend it. Physical deletion runs hourly and
on startup; read-time expiry prevents data leakage during worker failure. Unknown
upstream outcomes are reconciled before retry. No unbounded queue or blind retries. Visible dashboards poll a lightweight
owner-scoped agent snapshot every two seconds, pause while hidden, and refetch on
visibility restoration. Use cache-free responses and cancel overlapping requests;
this is the mechanism underlying SC-002, with measured foreground latency.

## Validation and Compatibility

Follow [quickstart.md](quickstart.md); all commands there are implementation gates,
not results from this documentation task. Existing CI covers npm tests, production
build and critical dependency audit; add missing contract/OAuth/retention/parity
checks to CI where self-contained, with real-client acceptance recorded separately.

Keep migrations additive; compare versions against all remote branches at the
implementation base. Test old/new code with the evolved schema, backup restore,
user deletion cleanup, and rollback to old app without dropping new data. OAuth
companion has independent health and lifecycle; app remains usable if it fails,
while MCP auth fails closed. Deployment origin and routing must be tested under
Traefik, not only direct localhost.

## Complexity Tracking

| Addition | Why needed | Simpler alternative rejected |
| --- | --- | --- |
| OAuth companion | Standards-compliant delegated access using an established provider | Custom OAuth implementation or unverified Next request bridge |
| Separate agent records | Per-activity retention without deleting personal/provider tasks | Retrofitting destructive retention into existing task tables |
| Persisted mutation receipts | External retries can otherwise duplicate effects | In-memory keys lost on restart or blind automatic retry |

No constitution exception requested. Design readiness does not equal runtime proof.
