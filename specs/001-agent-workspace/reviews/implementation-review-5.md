# Continuation implementation review

**Date:** 2026-10-23. **Final verdict:** APPROVED, no material blockers.
**Ruflo tracking:** `task-1792791311565-w63vjh`.

As in the earlier implementation review, Ruflo tracked the review and its status;
the available local Claude CLI executed independent read-only reviews with tools
disabled because the direct Ruflo review execution had no configured provider.
This is not a claim that Ruflo itself executed the model or local test gates.

The first continuation snapshot included 71 files. The reviewer raised one
conditional blocker because the companion runtime was absent from that snapshot:
HTTPS cookies would fail if the companion did not normalize forwarded protocol.
The second snapshot supplied that runtime plus the final OAuth and task metadata
deltas. It confirmed existing canonical protocol normalization and approved the
implementation. An additional automated test independently proved the real HTTPS
provider-through-proxy flow, DCR 201, authorization 303, public HTTPS Location and
Secure/HttpOnly cookies despite forged protocol/host headers.

| Finding | Owner and resolution | Commit/source evidence | Verification |
| --- | --- | --- | --- |
| Conditional HTTPS cookie blocker | Root: companion already normalizes protocol from configured origin; inventory added regression | Existing `lib/oauth/runtime.ts`; continuation test | Real provider/proxy HTTPS regression plus middleware tests |
| Suspected duplicate Jira watch keys | Root: false conditional; existing preference writer deduplicates uppercase keys | Existing `lib/preferences.ts` | Source inspection and watch parity tests |
| Codex natural-expiry refresh invalid_scope | OAuth module owner: stop advertising unused OIDC offline-access scope; keep strict application scope checks | `00ac5d9`, `lib/oauth/provider.ts` | Actual provider refresh/no-escalation tests; timed client evidence separately recorded |
| Upstream task create fields and recurring-task semantics | UI/domain owner: create metadata in same receipt, atomic local writes, safe partial remote creation, effective scheduling validation | `00ac5d9`, `lib/operations/tasks.ts` | 57 focused task/parser/CLI cases; integrated suite |
| Known monthly provider recurrence | UI/domain owner: normalize only absoluteMonthly; reject unknown enums visibly | `00ac5d9`, `lib/parsers/mstodo.ts` | Parser and MCP result-schema cases |
| Partial reruns lose client reconciliation details | Root + GitHub owner: persist bounded sanitized partial outcomes and expose in MCP errors and browser adapters | `00ac5d9`, receipt/context/registry | Confirmed and uncertain replay tests; no repeated provider call |
| Browser errors regress to English | UI owner: localize error presentation at the HTTP edge, preserve domain codes and statuses | Final browser adapter delta | Focused browser error-contract tests |

## Scope and non-blocking limits

- Browser Jira transport retains existing HTTP result contracts; MCP distinguishes
  refusal and uncertainty and persists receipts. This review does not assert a
  migration of every existing browser write onto client-supplied idempotency keys.
- Retry inputs must preserve their operation key and request timestamp. An internal
  reconciliation helper remains conservative and is not a generic public tool.
- Unsupported provider recurrence enums fail visibly; no lossy mapping of yearly
  or relative recurrence was introduced beyond the panel's supported actions.
- Backups omit agent history and preserve pre-existing backups. Their non-agent
  storage lifecycle and off-host snapshots remain operator responsibilities.
- Static approval does not establish production permissions, real client refresh,
  deployed service health or benchmark results; those have separate evidence.

Private raw reviewer responses and exact snapshot hashes remain under `/tmp`:
`daily-continuation-review-{result,hashes}.json` and
`daily-continuation-delta-{result,hashes}.json`. No private CLI credentials or
transcripts are included in the repository.
