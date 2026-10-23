# Agent browser contracts

`browser-contract.json` was captured from the running application through its
local reverse proxy on 2026-10-23, using a disposable database and test account.
The capture uses the real browser-session `GET /api/agents` and
`GET /api/agents/tasks/{id}` handlers after creating an agent, a session, two
tasks and a lifecycle transition through the reporting API.

Only the current acceptance session is retained in this fixture. Opaque
identifiers and generated test-name suffixes are normalized. No credentials,
cookies or production user data are included. Response field names, nesting,
enums, pagination flags and timestamps remain those returned by the service.
Component tests derive mock responses from this capture and replace timestamps
where the test needs live, unexpired work.

## Task hierarchy HTTP capture

`hierarchy-contract.json` was captured on 2026-10-23 from the actual reporting and browser HTTP routes of a local Next.js development server on loopback port 8032, using a fresh disposable schema 17 database. A temporary reporting credential registered an agent/session, created a root task and one child, moved the child to working, and reported child progress. The fixture includes all-task/root-only snapshots, both task details, and the HTTP 409 refusal to delete a parent with children. Its provenance lists the captured endpoints.

Opaque IDs are replaced consistently; credentials and user records are excluded. The capture credential was revoked after validation. Hierarchy component scenarios derive from these responses; synthetic pagination cursors and malformed inputs are explicitly test variations. The older `browser-contract.json` remains unchanged to verify rolling compatibility with responses that omit `parentTaskId` and `subtasks`.
