# Research and Decisions

**Date**: 2026-10-23. Read-only source and official documentation review.
These are design decisions, not claims of implemented or tested behavior.

## 1. Reuse domain operations, not HTTP loopback

Decision: extract typed user-scoped operations reused by browser handlers,
reporting API, and MCP. Keep the existing integration clients and vault.
Evidence: `lib/api/context.ts`, `lib/auth/currentUser.ts`, `lib/api/jira.ts`,
`lib/api/pulls.ts` currently derive identity from the browser cookie.
Alternative rejected: fabricating cookies or forwarding OAuth tokens to internal
routes. That would couple MCP to browser auth and obscure authorization.

## 2. Isolate agent tracking from personal tasks

Decision: additive agent/session/task/activity storage using the current SQLite
connection and migration mechanism. Optional source links are references only.
Evidence: `lib/tasks/index.ts` chooses local or mstodo; `lib/tasks/boardStatus.ts`
and `lib/taskBoard.ts` derive todo/doing/done. Personal tasks have no agent identity
or last-activity field. Alternative rejected: purging the existing task tables or
changing external-provider lifecycle to fit agent retention.

## 3. Last activity and bounded history

Decision: task snapshots expire 30 days after accepted activity. Individual history
entries still expire after 30 days. Reads/retries never renew expiry. Server UTC
receipt time avoids future-dated client timestamps retaining data indefinitely.
Keep expired records inaccessible independently of cleanup availability. Exclude
agent data from durable logical backups and restore tests. Alternative rejected:
UI-only hiding, cleanup-only access checks, or retaining old event history forever
because a single task remains active.

## 4. OAuth is a new authorization surface

Decision: keep current login and add an OAuth authorization server using the
established `oidc-provider` library. Run it as a loopback-only companion process,
with same-origin reverse-proxy routes and an owner-scoped, one-use interaction
handoff from the existing authenticated app. Its protocol, PKCE, token generation,
and token lifecycle come from the library, not custom cryptography. Use a persistent
adapter; provider token payloads that must be recoverable are encrypted at rest,
while lookup identifiers and PAT secrets use digests. Never claim every provider
internal record can be stored as a hash if its adapter requires recovery.

This is a planned integration: first implementation task must prove login bridge,
resource audience, metadata, refresh rotation, restart persistence, and revocation
before building dependent features. Exact package patch versions are pinned during
that gate, after compatibility/security checks. The companion service is justified
because the provider exposes a Node HTTP interface rather than native Web Request
handlers; it avoids a custom Next.js server or an unverified request bridge.

Official evidence: [oidc-provider](https://github.com/panva/node-oidc-provider)
implements PKCE, discovery, resource indicators, introspection, revocation, opaque
tokens, and dynamic registration. Its CIMD support is experimental; do not assume
it is production-ready by default. Existing app Google/Slack OAuth is client-side
integration logic, not an authorization server.

## 5. Official MCP SDK and transport

Decision: use the stable v2 `@modelcontextprotocol/server`, Streamable HTTP at
`/mcp`, Web Request/Response integration in a Node-runtime Next.js Route Handler,
and stateless request handling. SDK context receives a verified principal; every
operation checks scopes, owner, module state, and connection access again.

Official evidence: [SDK repository](https://github.com/modelcontextprotocol/typescript-sdk)
identifies v2 as stable and targeting MCP 2026-07-28. The SDK's authorization-server
legacy helpers are not the basis for this new service. No Express dependency is
needed for the Next.js resource endpoint. Alternative rejected: shipping an
unauthenticated stdio-only proxy or implementing JSON-RPC manually.

## 6. Discovery and client compatibility

Decision: Authorization Code + PKCE S256, canonical resource indicator `/mcp`,
protected-resource metadata, authorization-server metadata, exact redirect URI
validation, and explicit per-client consent. Use pre-registration and DCR for
initial client interoperability. Add CIMD only when its experimental provider
support passes the same safety/compatibility gate; do not advertise it beforehand.
DCR is compatibility support, not a recommendation for unrestricted registration.
Protect registration against unbounded records and reject arbitrary redirect URLs.

References: [MCP authorization](https://modelcontextprotocol.io/specification/2026-07-28/basic/authorization),
[registration](https://modelcontextprotocol.io/specification/2026-07-28/basic/authorization/client-registration),
[security](https://modelcontextprotocol.io/specification/2026-07-28/basic/authorization/security-considerations).
MCP OAuth tokens must not be forwarded to Jira/GitHub. Invalid token is 401;
insufficient scope is 403; revoked grants are checked on every call.

Client documentation reviewed by research agent:
[Claude Code](https://code.claude.com/docs/en/mcp),
[Codex](https://learn.chatgpt.com/docs/extend/mcp?surface=cli),
[Gemini CLI](https://geminicli.com/docs/tools/mcp-server/).
Documented support is not end-to-end evidence. All three need actual acceptance
runs after implementation; headless agents complete interactive consent first.

## 7. Full module parity includes supporting actions

Decision: use the inventory in `contracts/mcp-capabilities.md` as the release gate.
Include filtering, summaries, watched resources, connection management, and the
focus-block action reachable from tasks/Jira/GitHub. The latter is a narrow shared
capability requiring separate agenda permission; it does not expose all agenda
features. External links become returned URLs, clipboard actions return text.
Alternative rejected: a handful of mutation tools marketed as full parity.

## 8. Existing delivery and framework

Evidence: Node 24, Next.js 16, React 19, TypeScript, SQLite/WAL, Vitest, and npm
lockfile/CI are current. This planning work does not change package management.
Use the repository's npm scripts and lockfile. CI runs tests, build, and critical
production dependency audit; no dedicated lint script exists. `deploy/` contains
systemd, publish, healthcheck, and Traefik snippets. Companion OAuth deployment
must update these artifacts in the implementation, without exposing a new public port.

No production writes, package installation, provider calls, or end-to-end auth
checks were performed during research. Graph coverage is partial for some files;
material integration and auth findings were checked in source.
