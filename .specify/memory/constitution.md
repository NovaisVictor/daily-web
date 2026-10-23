# Daily Web Constitution

## Core Principles

### I. User isolation and credential protection

Every protected operation MUST resolve the authenticated user and authorize both
resource and action server-side. Connections and data MUST remain owner-scoped.
Credentials MUST NOT appear in logs, fixtures, prompts, or ordinary responses.
Newly generated credentials may be revealed once to their owner.

### II. Equivalent authorization across entry points

The panel, public API, and MCP MUST enforce equivalent domain permissions.
An additional entry point MUST NOT bypass ownership, provider permissions, or
module availability. External failures MUST be visible, never reported as success.

### III. Explicit domain contracts

External responses MUST be validated. Unknown values MUST fail visibly instead
of silently selecting a default. Domain concepts MUST have explicit types;
related fields belong together. State-changing retries MUST NOT duplicate effects.
Network calls and background work MUST have explicit bounds and timeouts.

### IV. Simple, modular changes

Changes MUST use the smallest design meeting the accepted specification and
preserve unrelated user work. URL query parameters MUST be the source of truth
for filter, search, sorting, pagination, and active-tab state.
Persisted-format changes MUST account for concurrent old and new application versions.

### V. Evidence-backed delivery

Implementation MUST follow clarified requirements. Validation MUST cover affected
behavior, authorization failures, invalid inputs, and external-service failures.
Quality baselines MUST NOT grow to hide failures. Final source edits invalidate
earlier gates until affected checks run again. Completion claims MUST identify
actual checks and unresolved limitations.

## Repository Constraints

The existing application uses Next.js, React, TypeScript, and SQLite. Avoid new
dependencies without a concrete requirement. The interface is Brazilian Portuguese;
new code and specification documents use English. Preserve legacy documentation
language when editing it. Secrets and personal data MUST NOT enter version control.

## Development Workflow

Follow specification, clarification, planning, task decomposition, consistency
analysis, then separately authorized implementation. Read repository instructions
and module documentation first. Use Codebase Memory before structural exploration
and verify material findings in source.

Current CI runs tests, a production build, and a production-dependency critical
vulnerability audit. Plans MUST identify affected checks not covered by CI.
Documentation-only work requires document validation, not runtime-validation claims.

## Governance

User instructions and applicable repository rules govern this constitution.
Amendments MUST record rationale, compatibility impact, and version changes.
Major versions change principles incompatibly, minor versions add principles,
and patch versions clarify wording. Reviews MUST explicitly report deviations.

**Version**: 1.0.0 | **Ratified**: 2026-10-23 | **Last Amended**: 2026-10-23
