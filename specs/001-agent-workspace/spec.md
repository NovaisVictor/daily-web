# Feature Specification: Daily Web Agent Workspace

**Feature Branch**: `feature/agent-workspace`

**Created**: 2026-10-23

**Status**: Specification approved by Ruflo review round 2; implementation and release validation tracked in `tasks.md` and `quickstart.md`

**Input**: Transform Daily Web from a passive monitor dashboard into a personal
workspace for tracking Claude, Codex, and Gemini agents. Every user can report
agents and tasks through an API, retain only the last 30 days, generate API
credentials and a ready-to-copy instruction prompt, and use supported actions
through MCP. Start with agents/tasks, Jira, and GitHub. Provide a detailed agent
workspace and make the home screen exclusively a macro-level kanban.

## Objectives and Module Boundaries

- Make agent progress understandable at a glance, without mixing unrelated panels
  into the home screen.
- Let every existing user integrate their own agents, without operator-managed
  credentials or access to another user's information.
- Make MCP sufficient to complete supported workflows without falling back to
  browser interaction for missing actions.
- Deliver in bounded modules with an independently demonstrable acceptance gate:
  **M1 Agents and kanban**, **M2 API access and MCP foundation**,
  **M3 Jira MCP parity**, **M4 GitHub MCP parity**.
- M1 and M2 form the first usable vertical slice: authenticated reporting, macro
  kanban, details, onboarding, and retention. Neither alone completes that slice.
- M3 and M4 reuse the same user identity and authorization boundaries. Their order
  may be finalized in planning. Other module adapters are later work.
- Parity means all user-facing actions within each supported module, including
  supporting reads and configuration needed to finish its workflows. Record an
  action inventory before claiming parity. Secret entry is the user-approved
  exception: onboarding or changing credentials takes place only in a secure
  browser flow; MCP returns its URL and can inspect completion. It does not mean all actions offered
  by the external Jira or GitHub products.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - See agent activity at a glance (Priority: P1)

As a user, I open Daily Web and immediately see my agents' work as a macro kanban,
then open the detailed workspace to understand a particular work item.

**Why this priority**: Agent visibility is the main purpose of the new experience.

**Independent Test**: Seed work for two users, sign in as each, and verify the
home, card-to-detail navigation, state changes, empty state, and ownership isolation.
Each card represents one task and identifies its responsible agent/session.

**Acceptance Scenarios**:

1. **Given** reported agent work, **When** I open the home screen, **Then** its main
   content is only the macro kanban, with concise status and current-work context.
2. **Given** multiple Claude, Codex, and Gemini instances, **When** I inspect my
   work, **Then** each instance can be distinguished without provider-name collisions.
3. **Given** a kanban card, **When** I open it, **Then** I reach the task details
   showing its responsible agent/session, timestamps, activity, and latest known state.
4. **Given** one agent session works on multiple tasks, **When** I open the home,
   **Then** each task has its own card, with that session identified on each card.
5. **Given** no reported work, **When** I open the home, **Then** I see a kanban empty
   state with an actionable link to agent onboarding.
6. **Given** an agent stops reporting, **When** its freshness threshold expires,
   **Then** the interface distinguishes stale information from confirmed completion.

### User Story 2 - Connect my agents (Priority: P1)

As a user, I generate a personal API credential and copy a prompt explaining how
my Claude, Codex, or Gemini agent reports work and uses supported capabilities.

**Why this priority**: Users need self-service onboarding for agent visibility.

**Independent Test**: Generate a credential, follow the generated instructions,
report a new task and progress, revoke the credential, and verify access fails.

**Acceptance Scenarios**:

1. **Given** an authenticated user, **When** they create an API credential,
   **Then** it belongs only to them and the secret is revealed only at creation.
2. **Given** onboarding instructions, **When** the user copies the prompt,
   **Then** it contains the correct deployment address, usage examples, reporting
   lifecycle, failure guidance, and credential placeholders rather than a secret.
3. **Given** a valid credential, **When** an agent reports or updates its work,
   **Then** the user's kanban and detail workspace reflect the accepted information.
4. **Given** a revoked credential or another user's resource identifier,
   **When** a caller attempts access, **Then** no unauthorized read or change occurs.
5. **Given** the same update is retried, **When** the request is processed again,
   **Then** it does not create duplicate tasks or duplicate activity.

### User Story 3 - Work through MCP (Priority: P1)

As a user, I authorize an MCP client to manage agent/task work and use supported
Daily Web modules with my permissions.

**Why this priority**: MCP must be a complete interaction surface for the modules
included in a release, not just a read-only summary.

**Independent Test**: Authorize a client, discover capabilities, complete an
agent/task workflow, revoke access, and verify the next operation is rejected.

**Acceptance Scenarios**:

1. **Given** a compatible MCP client, **When** I authorize it using OAuth,
   **Then** it acts as me with explicit granted permissions without copying my
   Daily Web password or Jira/GitHub credential into the client.
2. **Given** the agents/tasks module, **When** I use MCP, **Then** all its supported
   user actions can be completed, including creation, reading, updating, and the
   same lifecycle transitions offered in the panel.
3. **Given** denied, expired, or revoked authorization, **When** a client operates,
   **Then** it receives an actionable error without executing the operation.
4. **Given** invalid inputs, provider failures, or a missing connection,
   **When** a supported operation fails, **Then** the client sees the actual outcome
   and safe retry guidance rather than a false success.

### User Story 4 - Complete Jira workflows through MCP (Priority: P2)

As a user, I use MCP to perform everything available in my Daily Web Jira panel
using my existing Jira connections and effective permissions.

**Why this priority**: Jira is one of the two requested initial external modules.

**Independent Test**: Build a current panel-action inventory and exercise each
entry through MCP, comparing resulting state and authorization with the panel.

**Acceptance Scenarios**:

1. **Given** an available Jira action, **When** I execute its MCP equivalent,
   **Then** its reads, changes, and resulting state match the panel's behavior.
2. **Given** multiple Jira connections, **When** I target one, **Then** the operation
   uses that authorized connection and does not silently choose another.
3. **Given** provider refusal or incomplete results, **When** MCP reports the
   outcome, **Then** it distinguishes refusal, partial results, and success.

### User Story 5 - Complete GitHub workflows through MCP (Priority: P2)

As a user, I use MCP to perform everything available in my Daily Web GitHub panel
using my existing GitHub connections and effective permissions.

**Why this priority**: GitHub completes the requested initial external scope.

**Independent Test**: Inventory current GitHub panel actions and verify each MCP
equivalent against the same authorized repositories and resulting state.

**Acceptance Scenarios**:

1. **Given** an available GitHub action, **When** I execute its MCP equivalent,
   **Then** its behavior and permissions match the panel, including supporting
   reads and repository configuration required by that workflow.
2. **Given** an inaccessible repository or changed pull request, **When** I operate,
   **Then** MCP reports denial or conflict without claiming the action succeeded.

### Edge Cases

- Concurrent updates and out-of-order reports must not silently overwrite newer
  state; clients receive a deterministic conflict or ordering outcome.
- Reusing an external identifier across users or agent sessions must not mix work.
- Retry after an uncertain external write must not cause an automatic duplicate.
- Revocation must take effect on the next operation, including an existing client.
- Expired records must be unavailable from the panel, API, and MCP, not merely hidden.
- Cleanup failure must be observable and retryable without exposing expired records.
- Pagination and filters must not turn a partial Jira/GitHub result into a complete one.
- Retention must define behavior for a task still running at the 30-day boundary.
- Refresh failure must preserve the distinction between last-known and current state.
- Unknown statuses, oversized reports, invalid timestamps, and unsupported agent
  providers must receive explicit validation outcomes.
- A disconnected module must explain what is missing without leaking credentials.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The home main content MUST be exclusively a macro kanban; global
  navigation and account controls may remain. Existing panels MUST remain
  accessible elsewhere without deleting their data or connections.
- **FR-002**: A separate workspace MUST expose agent/task details and recent
  activity, with direct navigation from home cards.
- **FR-003**: Each kanban card MUST represent one task and identify its responsible
  agent/session. Multiple tasks handled by the same session MUST have separate
  cards. Opening a card MUST show that task's details and activity. Card placement
  MUST reflect the task's lifecycle state, independently of agent freshness.
- **FR-004**: The system MUST distinguish agent identity, execution session,
  task identity, task lifecycle state, and reporting freshness.
- **FR-005**: Every authenticated user MUST be able to create, list metadata for,
  and revoke their own API credentials without operator intervention.
- **FR-006**: Credential secrets MUST be shown only on creation and MUST NOT be
  embedded in saved prompts, URLs, logs, examples, or ordinary credential listings.
- **FR-007**: Onboarding MUST generate deployment-specific instructions usable by
  Claude, Codex, and Gemini, including the report lifecycle and recovery guidance.
- **FR-008**: Authenticated agents MUST be able to report tasks, lifecycle changes,
  and progress, and retrieve their authorized current state.
- **FR-009**: Duplicate reports MUST be idempotent and concurrent or out-of-order
  updates MUST have defined, visible outcomes.
- **FR-010**: Authorization MUST derive ownership from the credential or OAuth
  identity, never a user identity supplied in a request payload.
- **FR-011**: Agent/task information MUST expire 30 days after its last accepted
  activity. New meaningful activity renews this window; reads and duplicate retries
  do not. Active work may remain longer than 30 days from creation while it keeps
  receiving activity. Work with no activity for 30 days expires regardless of status.
- **FR-012**: Expiry MUST apply consistently to panel, API, and MCP access and to
  related agent activity. Planning MUST define physical cleanup, caches, logs,
  and backup treatment so storage does not defeat the retention requirement.
- **FR-013**: MCP MUST use OAuth authorization; public reporting MUST support
  personal API credentials. MCP grants MUST be revocable and permission-scoped.
- **FR-014**: MCP MUST support complete panel-action parity for agents/tasks,
  existing personal tasks (local or Microsoft To Do), Jira, and GitHub as each
  module ships, with an auditable action inventory. Secret entry remains in the
  browser by explicit user decision; MCP must not accept password/token fields.
- **FR-015**: MCP MUST use the user's configured connections and enforce provider
  authorization, resource ownership, module availability, and granted scopes.
- **FR-016**: Jira and GitHub MCP actions MUST expose failures, conflicts,
  pagination, and incomplete results explicitly.
- **FR-017**: Revoking an API credential or MCP grant MUST prevent its next use.
- **FR-018**: Filter, search, ordering, pagination, and active-tab state MUST live
  in URL query parameters in browser workflows.
- **FR-019**: Invalid reports and unsupported operations MUST fail visibly;
  credential material and unnecessary sensitive payloads MUST NOT be recorded.
- **FR-020**: Reporting and external operations MUST have bounded payloads,
  timeouts, and overload behavior; exact operational values belong in the plan.
- **FR-021**: Agent integration reports work; this release MUST NOT assume Daily
  Web launches processes, edits user repositories, or remotely controls machines.

### Key Entities *(include if feature involves data)*

- **User**: Existing owner of private work, grants, and configured connections.
- **Agent**: A distinguishable user-owned assistant instance and provider identity.
- **Agent session**: One execution context with reporting freshness and related work.
- **Task**: A user-owned unit of work with explicit lifecycle and optional linkage
  to existing Daily Web tasks, Jira issues, or GitHub pull requests.
- **Activity report**: A timestamped update associated with a session/task and a
  stable identity for retry detection; covered by agent-data retention.
- **API credential**: A revocable reporting authorization owned by a user.
- **MCP grant**: A revocable client authorization with explicit module permissions.
- **Module capability**: A panel action and its MCP equivalent, authorization
  requirements, inputs, outputs, and failure outcomes.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A user can locate an active or blocked work item from the home and
  reach its details in at most two interactions.
- **SC-002**: A newly connected agent's accepted report becomes visible within
  five seconds on a visible foreground dashboard for at least 95% of updates
  under the planning benchmark workload.
- **SC-003**: Onboarding allows a user to generate access and obtain copyable
  instructions in at most three minutes, excluding installing an agent client.
- **SC-004**: 100% of inventoried panel actions in each shipped module have a
  tested MCP equivalent; missing actions prevent declaring that module complete.
- **SC-005**: Cross-user access attempts fail in every panel/API/MCP acceptance
  case, including guessed identifiers and multiple provider connections.
- **SC-006**: Replaying an accepted report produces exactly one logical change.
- **SC-007**: Records outside the agreed 30-day window are inaccessible through
  every user-facing surface and are deleted according to the cleanup contract.
- **SC-008**: Every revocation acceptance test rejects the next operation without
  requiring a client restart.

## Assumptions

- Existing accounts and user-owned integrations remain the identity foundation;
  public registration, organizations, and shared boards are not implied.
- The 30-day requirement covers new agent/task reporting data; existing unrelated
  Jira/GitHub source records, user accounts, and integration settings are not purged.
- Whether new agent tasks share storage/lifecycle with existing personal tasks is
  a planning decision constrained by the agreed retention policy.
- Proposed initial lifecycle labels are queued, working, blocked, completed,
  failed, and cancelled; freshness is separate. These are planning defaults, not an additional user decision; transitions and
  validation will be specified in the data model.
- OAuth for MCP authorizes access to Daily Web. It does not require replacing
  existing Jira/GitHub connection credentials or the browser login system.
- Optional modules remain optional, and non-agent panels remain reachable through
  navigation despite leaving the home screen.
- Advanced orchestration, billing, team collaboration, other MCP modules, and
  arbitrary remote execution are outside this initial release.
- Performance targets are proposed acceptance targets, not measurements of the
  current application. Planning must specify representative load and p95/p99 checks.
- The existing CI runs tests, build, and a critical production-dependency audit.
  Feature-specific auth, retention, integration, and usability gates must be added
  to the plan; this draft does not claim those checks have run.

## Clarifications

### Session 2026-10-23

- Q: What does a home kanban card represent? → A: One task per card, identifying
  its responsible agent/session. The user revised the earlier session-card choice.
- Q: What starts the 30-day retention clock? → A: Last activity, accepted by the user.
- Q: May secrets be entered only in the browser? → A: Yes, explicitly accepted
  by the user after Ruflo review; MCP returns a secure setup link.
- Both core decisions are integrated. The implementation plan and module backlog
  are recorded separately; implementation has not started.

### Follow-up: agent subtasks (2026-10-23)

The user explicitly authorized agents to create tasks and subtasks and confirmed
that these are agent-kanban tasks, linked to a parent with their own progress.

- FR-030: Agents can create one-level subtasks through the reporting API and MCP,
  under the existing owner-scoped write permission. Each child has its own state,
  activity, metadata version and 30-day inactivity retention.
- FR-031: The home kanban displays top-level tasks; task detail displays linked,
  paginated subtasks with navigation to their independent activity/status view.
  Child activity counts as parent activity, without automatic status changes.
- FR-032: Enforce parent ownership, reject nested/reparenting requests, preserve
  idempotent writes and reject implicit destructive parent deletion.
