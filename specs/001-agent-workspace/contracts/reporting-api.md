# Reporting API Contract (proposed)

Prefix `/api/v1/agents`. All routes use TLS in production, JSON, no-store responses,
and Bearer personal API credentials. Read/write scopes are `agents:read` and
`agents:write`. The principal comes from the credential; reject ownership fields.
OAuth tokens use the MCP audience and cannot be substituted for reporting tokens.

| Method / route | Capability | Result |
| --- | --- | --- |
| POST /register | Register owner-scoped agent externalId/provider/displayName | Agent identity |
| POST /sessions | Start a session for that agent | Session + version |
| POST /sessions/{id}/heartbeat | Refresh that session's observed freshness | Current version |
| GET /sessions | List live sessions with cursor | Items + nextCursor |
| GET /sessions/{id} | Inspect session and live work references | Session snapshot |
| POST /tasks | Create task with externalId, title, optional assignment/source link | Task + version |
| GET /tasks | Filter by status/agent/session, bounded cursor paging | Items + nextCursor |
| GET /tasks/{id} | Read live task details | Task + version |
| PATCH /tasks/{id} | Edit title/description/assignment/source link with expected version | Updated task |
| POST /tasks/{id}/transitions | Apply valid lifecycle transition with expected version | Updated task |
| POST /tasks/{id}/activity | Report progress or explicit task heartbeat | Updated activity time/version |
| GET /tasks/{id}/activity | Read retained activity with cursor | Items + nextCursor |
| DELETE /tasks/{id} | Explicitly remove an owner-scoped task | No content |

Writes require an Idempotency-Key and request timestamp; metadata/lifecycle edits
require expectedVersion. Append-only activity and session/task heartbeats omit it
and cannot change status/assignment. Live externalId collisions return 409
external_id_in_use; fresh creation can replace an expired identity atomically
with a new server id. DELETE retries return their stored 204 outcome. The shared schema rejects unknown status/provider values,
invalid links, oversized descriptions, and any owner mismatch. Time fields use
ISO UTC; server receipt time is authoritative. Text is rendered as text, never HTML.
Page size defaults to 50, maximum 100; title maximum 200 characters, description
4000, activity summary 2000, request body 64 KiB. These are initial documented
operational bounds, adjustable after measured load testing without broadening auth.

Errors expose a stable code, safe message, and retry classification. Use 400 invalid
input, 401 missing/invalid credentials, 403 insufficient scope, 404 missing/foreign/
expired resource, 409 version or idempotency conflict, 413 oversized input, 429
capacity limit with Retry-After, and 502/504 upstream failure/timeout. Never expose
provider secrets or sensitive upstream payloads.

Credential creation/listing/revocation is browser-session authenticated under
`/api/agent-access/tokens`; list returns metadata only. Generation is a CSRF-protected
POST, not GET. Credential administration cannot be performed with a reporting
credential. Prompt generation uses configured PUBLIC_ORIGIN and placeholders;
never trust Host to construct security-sensitive URLs.
