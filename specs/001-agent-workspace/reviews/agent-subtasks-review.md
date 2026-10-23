# Agent subtasks independent review

Verdict: **APPROVED**. No unresolved blocker was found in the reviewed final implementation. This is a scoped code and contract review, not an assertion that the final integrated release gates or deployment have completed.

## Review execution and limitations

- Ruflo reviewer: `agent-1792796717819-23p3c9` (`daily-web-agent-subtasks-review`).
- Ruflo tracking task: `task-1792796786986-6m5xip`.
- Ruflo direct execution was unavailable because its Anthropic provider had no `ANTHROPIC_API_KEY`. Registration and task status are coordination evidence, not proof of a provider review.
- Actual independent execution used the existing local Claude CLI in print mode, with session persistence disabled, an empty strict MCP configuration and no tools. It received source-only numbered snapshots; no credentials, runtime database, private API payload or OAuth token was supplied.
- The first review rejected expired-parent external identifier reuse. A second review confirmed the production correction and rejected an outdated test expectation. A supplementary review of the final migration, index, operations, retention and regression tests returned **APPROVED**. The coordinating reviewer checked the final test-only timestamp correction directly and reran the focused checks below.
- The CLI reviewer performed static review only and did not claim to execute tests. Test and SQLite evidence below was executed separately by the coordinating reviewer.

## Findings and resolution

| Finding | Resolution | Regression evidence |
| --- | --- | --- |
| Accepted child DELETE did not touch its parent | Touch the parent inside the same immediate mutation transaction before deleting the child; replay skips the mutation | Explicit deletion updates only parent activity once; replay does not touch again |
| Invisible expired children blocked parent deletion and expired external identifier reuse | Block live children only; detach expired links using the same cutoff inside the mutation transaction, preserving child content, timestamps, versions, history and receipts | Live-parent deletion with expired children; replacement of an expired parent; no resurrection from expired receipts or a new key |
| Foreign-key child lookup could scan retained tasks | Make the index start with parent identifier, followed by owner, update time and task identifier | Indexed owner/parent pagination at 10,000 children; parent-only foreign-key lookup uses SEARCH without SCAN |
| Old v16 delete/cleanup could fail against the new self-reference | Use additive nullable `ON DELETE SET NULL`; retain the v17 live-child guard | Raw v16-style parent DELETE and expired-parent cleanup preserve child data and timestamps with foreign keys enabled |
| Expired-child regression expected 404 before receipt expiry and used a stale clock anchor | Preserve existing `receipt_expired` 409 precedence; use the child's actual activity timestamp after reporting | Old receipt fails closed; new operation against the deleted parent returns 404; deterministic retained child timestamp |

## Contract checks

The reviewed paths enforce ownership before parent selection, reject missing/foreign/expired parents, reject grandchildren and prevent live task reparenting. REST and MCP return required nullable parent identifiers. List filters preserve the all/default, roots and selected-parent behavior with bounded keyset pagination. The home kanban requests roots, while the workspace can display all tasks and individual children.

Accepted child create, effective metadata update, transition, activity, heartbeat and deletion touch only parent activity. No-op updates, rejected versions and idempotent replays do not touch the parent, change its lifecycle/version, or manufacture parent events. The child has its own lifecycle and history. Cleanup selects leaves before parents and retains its shared batch budget; expired-link detachment does not extend retention.

The browser's acceptance of a missing parent identifier as a root and missing subtasks as an empty list is the explicitly documented mixed-wire compatibility rule. Present invalid values, unknown enums and inconsistent hierarchy remain errors; this exception is not a claim that an old server understands subtasks.

The additive migration follows version 16. A v16 rollback can delete a parent and promote children to roots, preserving their data; it has no hierarchy UI, guard or child-to-parent activity propagation. Re-entering v17 after old writers may encounter an expired parent with a live child; hierarchy behavior then follows the new activity rules. This is documented downgrade degradation, not v17's normal lifecycle. Unreleased intermediate migration-17 schemas in disposable development databases must be recreated before validating the final schema; this is not an upgrade issue for published production version 16.

User removal deletes all owned agent tasks in one SQL statement. A disposable SQLite experiment with the installed driver confirmed foreign keys enabled by default and successful same-statement parent/child deletion. Logical backup recreates the schema while excluding agent/task/session/activity/OAuth rows; this review inspected that behavior, without claiming a new end-to-end restore exercise.

## Executed validation

Final focused execution after the timestamp correction:

```sh
npm test -- tests/lib/agents/subtasks.test.ts tests/api/agents/reporting.test.ts tests/mcp/parity.test.ts tests/components/agents/TaskHierarchy.test.tsx tests/lib/dbMigration.test.ts tests/lib/auth/users.test.ts
node_modules/.bin/tsc --noEmit --incremental false --pretty false
```

Result: **78 tests passed across 6 files**; TypeScript completed with exit code 0 and no diagnostics. Both commands ran against the final timestamp correction and final migration/index schema. Full-suite/build, remote migration collision inspection, final browser acceptance and release publication remain the root agent's separate gates. OAuth behavior was not changed by this feature and its previous timed client proofs were not rerun or represented as new evidence.

## Final reviewed source hashes

These hashes identify the implementation and deterministic regression snapshot reviewed here. Later evidence or task-status documentation edits do not change implementation approval.

| Repository path | SHA-256 |
| --- | --- |
| `lib/agents/model.ts` | `c6f26e70ac537facecfe259718135d4ed362b5682c3b62ee73458688ed465e72` |
| `lib/agents/operations.ts` | `0d108f10c7e533ca6032727a75801230f11e563b7f7592c65d37b3e873ce6ad3` |
| `lib/agents/http.ts` | `1774c640a07e5d621b5a1dc1dbdd2bf72d2e652b4919a359f052cb20f76303af` |
| `lib/agents/retention.ts` | `ff2dce3e4a198bd1aa832bcaa998621eb57030302919351019d21b3bbc5a1eaa` |
| `lib/db.ts` | `81bff4e737c6e521240c13c984f058a785e8eb63fad1e5cc73c66a039edd451e` |
| `lib/mcp/tools/agents.ts` | `42ab70b85840f49b8cdc647c102b45262ff78ccf58bc42906ae6539e3863a949` |
| `app/api/agents/tasks/[id]/route.ts` | `ffc129a0ed309dc78c46b655348223e12c29a4487fada8885e4c8a3c6875b6fa` |
| `components/agents/AgentBoard.tsx` | `dbbb582f483d63fbee555fdc661ad814aea5265d7778a1bd5724b020202b15ec` |
| `components/agents/TaskCard.tsx` | `ce16f92d5afbd985fac54fa01784db5c419c45951fc4cddf468480787e1ab730` |
| `components/agents/TaskDetail.tsx` | `b3a7c193db0a05aac809312020a603b05b7fe69fa305091b5a30b421e080ad5c` |
| `components/agents/contracts.ts` | `aeaa20daa78e1f2e6973c3d2c27fc180a7997f293c58ec8b2ff454e980aad3bd` |
| `components/agents/request.ts` | `38e8ccd940ba9cd9c64552e078032457851afcf4c7927456f771ba7b527e1e98` |
| `tests/lib/agents/subtasks.test.ts` | `b50c8e253849c05211bf60fdcb620beafe96a7bf09df60eb980335303a1f4ffa` |

Reviewer: Claudinei. No implementation edits, commit, push or production data changes were performed by this review.
