# OAuth and Access Contract

## Public routes and discovery

- `/mcp`: only OAuth bearer access; 401 points to protected-resource metadata.
- `/.well-known/oauth-protected-resource/mcp`: canonical MCP resource, scopes,
  and authorization-server issuer, derived from validated deployment configuration.
- Authorization-server discovery at its standards-compliant well-known route;
  authorization, token, registration, introspection, and revocation endpoints
  belong to the companion provider and are advertised from discovery.
- Same-origin `/oauth/` prefix routes to the loopback-only companion. Proxy
  configuration must preserve its advertised issuer and well-known discovery.
- Browser login/consent interaction stays in the Next app and uses a one-use,
  expiring server-side handoff; no user identity taken from query parameters.

Pre-register supported clients or use constrained DCR: at most 1000 dynamic client
records per deployment, at most 10 registrations per minute per source address,
and delete never-authorized clients after 24 hours. At capacity return 429 with
Retry-After rather than evicting an authorized client. Rate-limit state has a
bounded LRU of 1000 addresses. These are abuse controls, not user subscription
quotas. All three clients must pass configured-client or DCR interoperability.
Exact redirect matching,
PKCE S256, no implicit grant, no password grant, no open redirect. Permit loopback
callback rules required by supported native clients, not arbitrary HTTP callbacks.
CIMD is not advertised until separately verified against SSRF, redirects, DNS
rebinding, document size, timeout, identity matching, and provider compatibility.

## Authenticated interaction handoff

The companion creates an opaque interaction id and persists its immutable
client id, resource, exact redirect URI, PKCE request binding, requested scopes,
and expiry. The browser reaches the Next consent page with only that interaction
id; it never supplies a trusted user id, grant, or replacement client metadata.
Next reads interaction metadata over a Unix-domain socket owned by the application
service account with mode 0600, using a 5-second deadline. This internal listener
is not exposed through Traefik or a public TCP port. Both processes run in the same
trusted service account boundary; unrelated users cannot invoke the socket.

After existing-cookie authentication and CSRF/origin validation, Next submits the
resolved user id and approved subset of scopes back over that socket. The approval
request includes the interaction id and a one-use nonce bound to the immutable
request fields. Only the companion consumes it, atomically verifying pending
state, expiry, client/resource/redirect/PKCE binding, requested scope subset, and
user still active before issuing a code. Denial consumes the interaction without
issuing a code. Never send a code, handoff nonce, token, or provider credential to
logs. The nonce and opaque identifiers use library/OS random generation; no
custom signature scheme is introduced.

The internal socket supports only interaction inspection/decision, not arbitrary
user impersonation or token minting. Reject duplicate approvals, another
interaction's nonce, changed client/resource/scopes, and expired requests. Test
concurrent consent for two different users and clients, cross-interaction nonce
swaps, direct public endpoint attempts, and socket calls from an unauthorized OS
user. Do not claim isolation from a compromised process already running as the
trusted application account.

## Verification, migrations and process startup

Next verifies opaque MCP tokens through an internal introspection operation on
the companion's authenticated Unix socket. It returns only active state, subject,
client, grant id, audience, scopes and expiry; do not return token secrets. Next
checks active user/grant and required resource permission every call. No positive
cache delays revocation. An unavailable verifier yields a closed failure.

The application is the sole migration owner. It completes SQLite migration and
readiness before the companion starts; companion refuses an incompatible schema.
Configure busy_timeout=5000 on every SQLite connection, serialize migrations and
use bounded transactions for writer contention. Companion failure must not break
ordinary browser login. Deployment stops/restarts in an order that avoids old
companion writes against incomplete schema and never exposes introspection publicly.

The early T011 proof uses a disposable database and a temporary local reverse
proxy with the same issuer/path layout and all three actual clients. Its harness
provides routing needed for the proof independently of production deployment T037.
T037 repeats the proof with the production-style Traefik/systemd configuration.

## Token lifecycle

Opaque access tokens: 15 minutes. Refresh family idle expiry: 30 days; absolute
expiry: 90 days; rotate on use and revoke family on reuse. These are security
policy defaults independent of task retention. One-use authorization codes:
60 seconds. Persistent provider adapter survives application restarts. Opaque
identifiers/secrets use digests where possible; adapter payload requiring retrieval
is encrypted using the existing vault primitive with a distinct purpose.

Every `/mcp` call validates audience equals the configured canonical MCP resource,
expiry, owner still active, grant active, and required scopes. No long-lived cache
may delay revocation: check authoritative grant state on every operation. Provider
credentials remain in the vault and are never exchanged for MCP access tokens.

For browser mutations require same-origin/CSRF protection. For bearer endpoints
validate Origin when present without demanding browser cookies; reject conflicting
auth mechanisms. Only exact bearer routes bypass cookie middleware, then apply
their own authentication before any protected operation.

## Required proof before dependent implementation

Test all of: discovery, login, consent/denial, PKCE challenge failure, code replay,
redirect mismatch, wrong resource, scope denial, refresh rotation/reuse, restart,
user deactivation, and immediate revocation. Test Claude, Codex, and Gemini against
one development deployment; browser-only or direct-token success is insufficient.
Do not build on an OAuth spike that fails any of these acceptance gates.
