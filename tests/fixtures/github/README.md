# GitHub fixtures (pulls module)

Read-only responses captured from the real GitHub API on **2026-10-21** with the
admin user's `pulls` connection (8 tracked repositories). Only `GET` requests and
GraphQL **queries** were sent; no mutation, no write.

## Sanitization

- Viewer login → `viewer`; other human logins → `user-1`..`user-N` (stable across files).
  Public bot logins (`coderabbitai`, `coderabbitai[bot]`, `dependabot`) are kept as-is.
- Every owner → `acme`; every repository → `repo-1`..`repo-N` (stable, also inside URLs).
  `repo-1`..`repo-8` are the tracked repos in config order; `repo-9`+ only appear in search results.
- Team slugs → `team-N`. Check names specific to the org → `checks (module-N)` / `check-N`.
- PR/issue titles → `<conventional type>: <Jira keys> Change N` (Jira keys kept).
  Head branches → `feature/<Jira keys>-branch-N` (base branch names kept).
- Removed: bodies, emails, avatar URLs, node ids, check-run `output` text.
- Token value never captured; only its prefix type.

## Files

| File | Source |
| --- | --- |
| `token-scopes.json` | `GET /user` and `GET /repos/{owner}/{repo}` (first tracked repo): selected headers + `permissions` |
| `graphql-repos.json` | `POST /graphql`, one query with aliases `repo0..repo7`: open PRs (first 50, `UPDATED_AT DESC`) with review requests, latest reviews, last-commit `statusCheckRollup` + contexts; open issues; default branch rollup; `viewer`; `rateLimit` |
| `graphql-review-requests.json` | `POST /graphql`, `search(query:"is:open is:pr review-requested:@me", type:ISSUE, first:50)` with the same PR fields + `repository{nameWithOwner}` |
| `graphql-my-prs.json` | `POST /graphql`, `search(query:"is:open is:pr author:@me", type:ISSUE, first:50)` same fields |
| `actions-runs.json` | `GET /repos/{r}/actions/runs?branch=<default>&per_page=5` per tracked repo, trimmed to `id, name, status, conclusion, head_branch, event, html_url, created_at, run_attempt` (+ `total_count`) |
| `pull-reviews.json` | `GET /repos/{r}/pulls/{n}/reviews` for one open PR with a failing check (trimmed) |
| `check-runs.json` | `GET /repos/{r}/commits/{sha}/check-runs` for that PR's head commit (trimmed) |

## KEY FINDINGS

- **Token**: classic PAT (`ghp_` prefix), **no expiration** (`github-authentication-token-expiration` absent).
  `x-oauth-scopes` includes `repo` and `workflow` (plus many admin scopes). On the tracked repo the
  `permissions` object is `admin/maintain/push/triage/pull = true`. `x-accepted-oauth-scopes` for
  `GET /repos/{r}` is `repo`. Rate limit 5000/h.
- **Write capability**: with this token the app *can* approve, comment, merge and re-run workflows.
  Required in general: classic → `repo` covers review/comment/merge and workflow re-run
  (`workflow` is only needed to push changes to workflow files, not to re-run);
  fine-grained → `Pull requests: write` (review/comment), `Contents: write` (merge),
  `Actions: write` (re-run). The module's instructions currently only ask for `repo`, which is enough.
- **GraphQL cost**: repos query (8 aliases × 50 PRs with nested connections) costs **16** points;
  each search query costs **2**. Remaining after all three: 4975/5000.
- **Enum values seen**:
  - `reviewDecision`: `REVIEW_REQUIRED`, `APPROVED`, `null`
  - `mergeable`: `MERGEABLE`, `CONFLICTING`, `UNKNOWN`
  - `mergeStateStatus`: `CLEAN`, `BLOCKED`, `DIRTY`, `UNKNOWN`
  - `statusCheckRollup.state`: `SUCCESS`, `FAILURE`, `null`
  - `CheckRun.status`: `COMPLETED` only; `CheckRun.conclusion`: `SUCCESS`, `FAILURE`, `CANCELLED`, `SKIPPED`
  - `StatusContext.state`: `SUCCESS` only (CodeRabbit), `targetUrl` always `null`
  - `latestReviews.state`: `COMMENTED`, `APPROVED`
  - `requestedReviewer.__typename`: `User`, `Team`
  - REST reviews `state`: `COMMENTED`, `APPROVED`; `user.type`: `User`, `Bot`
  - REST runs `event`: `push`, `dynamic` (Dependabot updates); `status` `completed`; `conclusion` `success`, `failure`
- **`mergeable: UNKNOWN` is common**: 12 of 16 PRs in the repos query and 4 of 21 in review-requests
  came back `UNKNOWN` with `mergeStateStatus: UNKNOWN` (GitHub computes mergeability lazily).
  `UNKNOWN`/`UNKNOWN` always appear together. Treat it as "not computed yet", not as conflict.
- **Default branch CI failing**: `acme/repo-4` default branch rollup is `FAILURE` and its last 5
  `main` runs (`acceptance`, `push`) all failed. `acme/repo-8` rollup is `SUCCESS` but its last 5
  runs with `head_branch: main` are failing Dependabot `dynamic` runs: filter runs by `event`
  (e.g. `push`) or prefer the GraphQL default-branch rollup for "is main red".
- **Null-ability observed**:
  - `reviewDecision: null` in 20 of 41 PR nodes (repo has no required review).
  - `statusCheckRollup: null` on a PR with no checks (`graphql-my-prs.json`, `acme/repo-13#1`).
  - `CheckRun.conclusion` never null here (all completed), but it is nullable while in progress.
  - `author` was never null in this capture (no deleted users), but GraphQL types it as nullable.
  - Search nodes for review requests include repos outside the tracked list (`repo-9`+).

## Not captured

- In-progress / queued check runs (`status` other than `COMPLETED`), `PENDING`/`ERROR`/`EXPECTED`
  rollup states, `CHANGES_REQUESTED` reviews/decisions, `BEHIND`/`UNSTABLE`/`HAS_HOOKS`/`DRAFT`
  merge states: none existed at capture time.
- A PR authored by a deleted user (`author: null`).
- Fine-grained token responses (the stored token is classic).
