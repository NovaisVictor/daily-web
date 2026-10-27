# GitHub shared-operation parity evidence

The ten registered GitHub operations now have a common orchestration path used
by MCP and the browser mutation/configuration routes. Browser edges keep their
cookie guard, selected owned connection, HTTP status conventions and response
shapes. They translate validated browser fields and optional idempotency headers
into `runGithubOperation`; provider writes, state checks, scope/owner validation,
receipts, cache invalidation and normalized outcomes live in
`lib/operations/github.ts`.

The GitHub panel's aggregate state snapshot remains the shared provider read
model; `github_work` adds the same URL filter parser and bounded cursor selection
without issuing writes. Configuration is available while the module is disabled;
work/actions require an enabled module. Repository changes use a local atomic
receipt instead of an external write reservation.

## Operation matrix

Every row has direct missing-scope, foreign-owner and invalid-input coverage in
`tests/lib/operations/github.test.ts`. Invalid browser fields and cookie guards
also remain covered in `tests/api/pullsActions.test.ts` and
`tests/api/pullsRepos.test.ts`. Provider failures do not apply to local repository
configuration operations.

| Operation | Shared success and supporting browser source | Additional behavior proved |
| --- | --- | --- |
| `github_work` | Captured tracked/review/mine provider models; existing state snapshot read model | URL filters/paging, default-branch metadata, partial data, invalid result enum/cursor, safe upstream failure |
| `github_repositories` | Shared owned-connection read; GET `/api/pulls/repos` | Configuration remains usable while module is disabled; foreign connections fail closed |
| `github_repository_add` | Local atomic receipt; POST `/api/pulls/repos` | Replay, no duplicate repository, capacity boundary through browser tests; no remote write |
| `github_repository_remove` | Local atomic receipt; DELETE `/api/pulls/repos` | Replay and removal, which also forgets the repo's followed authors; no remote write |
| `github_repository_authors` | Local atomic receipt; PUT `/api/pulls/repos/authors` | Replay, empty list follows everyone, untracked repo refusal, per-repo and total author limits; no remote write |
| `github_review` | Shared current pull/viewer preflight and review adapter; browser reviews route | Server-side self-review/draft/closed refusal; provider permission denial, malformed result state, uncertain write and confirmed replay |
| `github_comment` | Shared comment adapter; browser comments route | Confirmed identity/URL replay, 4xx refusal, network uncertainty, required text/length, browser idempotency and Origin check |
| `github_request_review` | Shared current-pull preflight and reviewer adapter; browser reviewers route | Users/teams, deduplication, author/draft restrictions, invalid response, 4xx refusal, uncertain write/replay |
| `github_merge` | Canonical merge adapter; browser merge route | Draft/closed/changed-SHA/unknown-mergeability/conflict refusal; exact-SHA submission, 4xx refusal, uncertainty, confirmed replay without a new preflight |
| `github_rerun` | Canonical bounded Actions adapter; browser rerun route | Expected SHA, eligible conclusions, zero jobs, bounded five jobs, all/partial refusals, unknown result, uncertain partial receipt/replay without repeating accepted jobs |
| `github_jira_sync` | `jiraActions.suggestSync` and `applySync`; browser GET Jira-sync uses the same suggestion helper | Both providers/scopes; confirmed replay, current expected transition, matching intent, required-screen refusal, provider failure/uncertainty |

Additional focused source tests:

- `tests/mcp/github.test.ts`: scoped advertisement, strict schemas, confirmed
  comment replay, authoritative grant revocation, foreign connection hiding and
  MCP uncertain-partial errors with safe retry guidance.
- `tests/lib/integrations/githubActions.test.ts`: provider request shapes, enum
  parsing, SHA/state checks, bounded Actions runs and normalized provider outputs.
- `tests/api/pullJiraSync.test.ts`: preserved browser suggestion contract,
  key/intent validation, Jira connection guard and unavailable transition.
- `tests/mcp/parity.test.ts`: maintained names/scopes/modes and complete discovery
  surface; `tests/lib/operations/integrations.test.ts`: shared transport boundaries.

## Outcomes and safe replay

A typed `GithubResponseError` identifies confirmed HTTP 4xx refusals before the
logical operation has any accepted effects. Shared orchestration records these
as not submitted. Network failures, 5xx failures or malformed write responses do
not become successes and require reconciliation before retry.

Actions reruns can have mixed effects. The shared operation throws the core
`ExternalPartialOutcome` carrying bounded, sanitized job identifiers/counts.
The receipt remains uncertain. MCP receives `uncertain_outcome` with reconciliation
guidance. The browser can preserve its existing partial-success HTTP payload
without claiming all jobs succeeded. Repeating the same key returns the recorded
partial outcome without another provider call. Confirmed successes replay their
original safe identifiers, reviewer list and GitHub URL.

## Fixture provenance and limits

`tests/fixtures/github/operation-contracts.json` records the extra read-only
public REST captures with exact endpoints and UTC time. The fixture README
describes normalization and omissions. Existing GraphQL, review and Actions
captures provide the other response models. Test mutation replies are derived
from captured object fields; no live review, comment, merge, rerun or repository
mutation was performed to obtain evidence. Adversarial statuses and enum values
are explicitly modified scenarios, not historical provider responses.

Automated tests prove shared behavior against these captured/derived contracts.
They do not assert that a production GitHub account performed a live mutation.
Final integrating test/build results belong in the feature validation record;
this document records the coverage and architectural ownership, not a fabricated
production acceptance result.
