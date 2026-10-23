# Ruflo Review Remediation

**Status**: APPROVED in round 2. Five nonblocking document corrections applied before implementation.
**Owner**: Claudinei for all items. Test entries are implementation tasks, not passed tests.

| Finding | Resolution | Artifact | Verification task |
| --- | --- | --- | --- |
| B1 Secret MCP inputs | User explicitly approved browser-only secret entry; MCP rejects secret fields and returns setup URL | spec.md; contracts/mcp-capabilities.md | T034, T052 |
| B2 Restore resurrects access | Restore invalidates all PATs, grants, codes and token families before listeners; raw backups inventoried/replaced | data-model.md; tasks.md | T001, T009, T010 |
| B3 Expired externalId collision | Atomically remove expired identity and dependents before fresh create; live collision is 409 external_id_in_use; stale retries rejected | data-model.md; contracts/reporting-api.md | T006, T010 |
| N1 DELETE receipt | Content-free receipt retained 30 days after deletion, replay returns original 204 | data-model.md | T006, T010 |
| N2 DCR limits | Documented deployment cap, per-source rate, unused-client expiry and bounded limiter | contracts/oauth.md | T026, T036 |
| N3 UI freshness | Two-second foreground polling with cancellation and visibility refetch | plan.md | T014, T051 |
| N4 Introspection/startup | Private Unix-socket introspection; app-only migrations; readiness order and busy_timeout | contracts/oauth.md | T004, T026, T029, T037 |
| N5 Early proxy dependency | Disposable local proxy harness in the early proof, production proxy validation later | contracts/oauth.md | T011, T037 |
| N6 Append-only versioning | Activity/heartbeat requires idempotency but not metadata version; cannot mutate assignment/status | data-model.md; contracts/reporting-api.md | T006, T021, T024 |
| N7 Personal task scope | Explicitly include local/Microsoft To Do personal task operations | spec.md | T033, T036 |

All modifications are currently uncommitted. No implementation approval was inferred
from the first rejected review.
