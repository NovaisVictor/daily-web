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
