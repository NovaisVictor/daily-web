# Data Model: Agent Workspace

## Boundaries

These are logical TypeScript domain names, not migration column names. Read the
operator SQL rules before writing any DDL or embedded query. Extend the existing
versioned migrations in `lib/db.ts`; check remote branches for version collisions
before implementation. Changes are additive and old application versions must
ignore new tables safely. Never purge existing personal tasks or upstream data.

## Entities

| Entity | Required concepts | Constraints |
| --- | --- | --- |
| Agent | owner, id, externalId, provider, displayName | Unique owner + externalId; provider enum claude/codex/gemini; unknown values rejected |
| AgentSession | owner, id, agent, externalId, startedAt, lastActivityAt, version | Unique owner + agent + externalId; server UTC clock; no user-supplied ownership |
| AgentTask | owner, id, externalId, title, description, status, assignment, version, createdAt, lastActivityAt | Unique owner + externalId among live identities; assignment references an owner-matched session; unassigned tasks allowed |
| Activity | owner, id, task/session target, kind, summary, receivedAt, occurredAt | Bounded plain text; occurredAt is display-only; receivedAt controls retention |
| SourceLink | provider, connection, resource identity | Optional link to personal task, Jira issue, or GitHub PR; link is not an automatic write to source |
| ApiCredential | owner, public prefix, secret digest, scopes, state, createdAt, lastUsedAt | Random secret shown once; no plaintext persistence; state active/revoked |
| OAuthGrant | owner, client, scopes, resource audience, state, createdAt | Explicit consent; state active/revoked; check owner availability on every operation |
| OAuthCode | grant, redirect URI, PKCE challenge, expiry, consumption state | Single use, short lived, code redemption atomic |
| OAuthToken | grant, token digest, expiry, token family, rotation state | Opaque token; refresh rotation and reuse detection; revocation applies immediately |
| MutationReceipt | owner, capability, resource class/id, connection, idempotency key, request digest, state, outcome, createdAt, resolvedAt, expiresAt | Unique owner + capability + key; same key/different input is conflict |

Assignment is a domain object, not unrelated provider/name/session fields. Status,
provider, credential state, freshness, and mutation outcome are named enums.
Persist no prompt bodies, conversation transcripts, source code, or credentials
inside activity. Description is optional and length-bounded.

## Task lifecycle

Initial state is `queued`. Allowed transitions:

| From | To |
| --- | --- |
| queued | working, blocked, cancelled |
| working | blocked, completed, failed, cancelled |
| blocked | queued, working, failed, cancelled |
| completed, failed, cancelled | queued (explicit reopen) |

Task status determines its kanban column. Agent freshness never changes task
status: fresh <= 2 minutes, stale > 2 minutes, disconnected > 10 minutes since
last accepted session activity. These thresholds are implementation defaults,
not a claim about whether a remote process is alive. Heartbeat refreshes a session;
it refreshes a task only when explicitly scoped to that task. A task's heartbeat
records activity but need not append a repetitive timeline row.

## Last-activity retention

- A task becomes inaccessible when `lastActivityAt <= now - 30 days`.
- New accepted reports, material edits, transitions, and explicit task heartbeats
  advance its server-assigned lastActivityAt. Reads, duplicate retries, credential
  use, and unrelated session heartbeats do not.
- Activity records expire individually 30 days after receivedAt, even when their
  parent task stays active; retaining an active snapshot cannot preserve old logs.
- Expired tasks and dependent links/activity are physically deleted in batches
  at startup and every hour. Reads always enforce expiry, even if cleanup fails.
- Session metadata is retained while referenced by a live task; otherwise it
  expires 30 days after last session activity. Unreferenced agent metadata follows
  its live sessions. This preserves referential integrity without keeping old events.
- Expiry is authoritative. Updates to an expired task fail as not found and do
  not revive it. A fresh create may reuse an expired externalId but returns a NEW
  server task id. In one transaction, check request age/idempotency, delete the
  expired task and its dependent content, then insert the new identity. This avoids
  waiting for hourly cleanup to release the uniqueness constraint. A collision
  with a live externalId returns 409 external_id_in_use. A delayed retry of the
  old create fails request-age validation and cannot recreate expired work.
- DELETE receipts are the exception to local resource-coupled expiry: retain only
  operation digest, deleted opaque resource id and 204 outcome for 30 days after
  deletion. Repeating the same DELETE key returns 204 without re-extending expiry.
  They contain no task text or activity; expired old requests are rejected.
- Retention cleanup uses bounded transactions, never runs concurrently with itself,
  and reports counts/errors without task content. Index owner + activity timestamp
  and owner + status + sort key; confirm query plans during implementation.
- Agent-local mutation receipts contain no task payload and expire with the
  affected agent resource. External-operation receipts use a different lifecycle:
  pending/unknown receipts never expire before reconciliation; confirmed-success
  or confirmed-failure receipts expire 30 days after resolvedAt. They retain only
  owner, operation/provider/resource identifiers, request digest and outcome code,
  never agent task content, comments, or provider credentials. External identifiers
  are bounded bookkeeping, not an extension of agent-history retention.
- A confirmed upstream non-submission may be retried under the same reserved
  operation. A confirmed submission returns its original outcome. Pending/unknown
  outcomes require reconciliation or operator resolution, never another blind call.
  Validate request freshness and conditional version so an expired terminal receipt
  cannot allow an old retry to execute again. Cleanup excludes unresolved receipts;
  surface their count and age for reconciliation rather than silently deleting them.
- Agent/activity data must be excluded from durable backups; do not copy the raw
  mixed-content database into longer-lived backups. Provide a supported logical
  backup/restore path excluding these tables and test that restores do not revive
  expired work. Restore MUST invalidate all restored API credentials, OAuth
  grants, codes, access tokens and refresh families before opening any listener;
  users reauthorize/reissue access afterward. Restore never recreates prior active
  credentials from a snapshot. Inventory and disable/replace existing raw DB
  backup jobs before enabling agent writes. Retention concerns logical records,
  not guaranteed forensic erasure of storage media. No task bodies in logs or caches lasting past expiry.

## Concurrency and external writes

Local task mutation, activity entry, and receipt commit in one transaction. Clients
supply expected version for mutable task metadata and lifecycle changes; mismatch
returns conflict. Append-only progress and heartbeats require unique operation keys
but no expectedVersion. They cannot modify status or assignment. Their timestamp
updates are monotonic and do not increment the metadata/lifecycle version. Server receipt time, not client
wall-clock time, advances retention. A repeated key with matching input returns
its original outcome without changing timestamps. Limit request age to 24 hours;
clients create a new operation only after reconciling current state.

For upstream Jira/GitHub/personal-task-provider writes, reserve a receipt before
calling the provider, record the confirmed outcome afterward, and reconcile any
uncertain outcome before retrying. An in-progress or unknown receipt must never
trigger another blind write. Do not claim exactly-once upstream behavior where the
provider has no idempotency support. No new async queue or outbox is needed for
synchronous requests; introducing published events requires transactional outbox.

## SQLite deletion bounds

The application enables SQLite `secure_delete=ON` and `journal_size_limit=0`.
Retention transactions are immediate and share one budget of at most 500 deleted
rows across activities, receipts, tasks, sessions, and agents. Large expired task
histories are drained before deleting the parent; read-time expiry hides the
entire resource throughout that drain. A startup/hourly drain yields between
transactions, runs for at most five seconds per turn, and schedules a bounded
continuation when more work remains.

After each cleanup transaction, including an empty retry, a WAL TRUNCATE
checkpoint reclaims historical frames. The existing five-second SQLite busy timeout bounds lock waits. A busy
checkpoint is reported without payload content and retried by subsequent cleanup;
physical WAL reclamation can therefore lag logical expiry while another process
holds a reader/writer. This is not a promise of forensic erasure from SSD media,
filesystem snapshots, or unsupported raw database copies. Only the supported
logical backup path satisfies the documented backup retention policy.

Deleting a task keeps content-free tombstones for its former mutation keys for
30 days after deletion. Old create/update/activity retries cannot resurrect it;
repeated DELETE retains its prior 204 outcome. A new operation may explicitly
create a new task identity using the same external identifier.

## Agent subtask relationship

`AgentTask.parentTaskId` is nullable for a root and immutable for a child. The
additive nullable `tb_agent_task.uid_parent_task` column references the same task
table; application validation additionally requires a live parent owned by the
same user and a single hierarchy level. Parent/owner/time/id queries use
`tb_agent_task_ix5`; roots use the same index with a null parent. Its parent-first
ordering also indexes SQLite foreign-key checks during task deletion.

A child retains the existing task status, assignment, source, version, timestamps,
activity and receipt behavior. Accepted child writes (including explicit deletion)
advance the parent's timestamp atomically; no-op edits and replayed operations
have no retention effect. No automatic status rollup occurs. A parent's activity
never refreshes children. Explicit parent deletion requires removing live children
first; cleanup waits for expired children within the existing row budget.

Expired children awaiting physical cleanup do not block parent deletion: their
link is cleared atomically without changing timestamps, state, content or
receipts. They remain expired and cleanup retains its existing row budget.
Only live children cause `task_has_subtasks`; no live child is detached or deleted.

The database foreign key uses `ON DELETE SET NULL` for old-version delete/cleanup
compatibility. Current operations block live-child deletion before this action;
old processes preserve surviving child records as roots with unchanged timestamps.
