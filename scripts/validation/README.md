# Real client acceptance

These opt-in drivers use installed, already signed-in Claude Code, Codex and
Antigravity (`agy`) clients. They do not install clients, change global safety
policy, or use production data. Run from the repository root after a successful
production build. Chrome is required by Playwright's `channel: chrome` browser.
Ports 8022, 8023 and 8024 must be unused; never stop an unrelated listener.

1. Run `node_modules/.bin/vite-node --config vitest.config.ts scripts/validation/bootstrap.ts`.
   It prints only a new private runtime directory. The database, random keys and
   disposable browser session stay in that directory with owner-only permissions.
   Set `validation_directory` to the printed path; never print its secret files.
2. Start `node scripts/validation/runtime.mjs "$validation_directory"` in a
   dedicated terminal. It runs the existing production build and compiled OAuth
   companion behind a loopback reverse proxy. Ctrl-C stops only its own children.
   Add `--oauth-via-next` to route OAuth and authorization metadata through
   the Next.js fallback proxy rather than directly to the companion. This checks
   deployments whose reverse proxy only routes the public origin to Next.
   OAuth events contain timestamps, grant type, status, method and tool name;
   authorization headers, request arguments, tokens and authorization codes are
   excluded. Private diagnostic CLI logs must never be committed.
3. Configure temporary clients:
   `claude mcp add --transport http --scope local daily_oauth_proof http://127.0.0.1:8022/mcp`
   and `agy mcp add --type http daily_oauth_proof http://127.0.0.1:8022/mcp`.
   Codex uses a per-command configuration override, not a saved MCP entry.
4. Authenticate each client sequentially with
   `node scripts/validation/oauth-client.mjs CLIENT authenticate "$validation_directory"`
   where CLIENT is `claude`, `codex`, then `agy`. The test browser uses the
   disposable session, approves consent, and privately delivers the expected
   callback URL/code to the actual CLI. For agy, `AGY_MCP_POSITION` is the zero-based
   row of this server in `/mcp` (default 4 for the acceptance host); adjust it to
   the installed server ordering. No credential is added to the model prompt.
5. Run `node scripts/validation/reporting-client.mjs CLIENT "$validation_directory"`
   for all three clients. Use an interactive terminal for agy: inspect the Node
   command against the private log, then approve only option 1, once, by typing
   `1` and Enter. The driver relays input to that CLI. Never select persistent
   approval. It passes the generated reporting prompt unchanged, adds a disposable
   task instruction, and injects the reporting credential only through the child
   environment. It verifies task status and progress through the real API, then
   revokes the credential and expects 401. The recorded duration starts before
   credential creation and ends at the first verified working task plus progress;
   it includes prompt retrieval, model/tool execution and manual command approval.
6. Wait until every initial authorization-code exchange in `oauth-events.jsonl`
   is older than **900 seconds** (the normal access-token lifetime). Do not
   reauthenticate or adjust the clock, stored token, library or server TTL.
   Run `node scripts/validation/oauth-client.mjs CLIENT call "$validation_directory" --require-refresh`
   **sequentially** for the three clients. The driver permits only
   `agents_sessions_list`; agy receives one-shot approval for that exact tool.
   A refresh proof requires a recorded `refresh_token` exchange with HTTP 200,
   zero new authorization-code exchanges, and the actual tool call succeeding.
   A model's claim without these server observations is insufficient.
7. Revoke the three fixture grants using the disposable authenticated browser's
   access page, check the next operations are rejected, then log out and remove
   temporary client configuration:
   `claude mcp logout daily_oauth_proof`,
   `claude mcp remove --scope local daily_oauth_proof`,
   `codex -c 'mcp_servers.daily_oauth_proof.url="http://127.0.0.1:8022/mcp"' mcp logout daily_oauth_proof`,
   and `agy mcp remove daily_oauth_proof`.
   Stop the dedicated runtime. Keep only sanitized result objects in the feature's
   validation directory; never commit private configuration or CLI transcripts.

Client wording, terminal rendering and command syntax may change. A timeout or
unrecognized UI is a failed driver run, not proof of a protocol failure. Diagnose
against official client help before changing the application.
