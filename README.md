# daily-web

[![CI](https://github.com/joaosouzacoder/daily-web/actions/workflows/ci.yml/badge.svg)](https://github.com/joaosouzacoder/daily-web/actions/workflows/ci.yml)
[![License: PolyForm Noncommercial 1.0.0](https://img.shields.io/badge/license-PolyForm%20Noncommercial%201.0.0-blue)](LICENSE)
[![Node](https://img.shields.io/badge/node-%E2%89%A522-brightgreen)](.nvmrc)

A personal workspace for agent work and daily integrations, behind a login.
The home screen is a task kanban for Claude, Codex and Gemini; the original
email, calendar, Jira, pull requests, tasks and focus dashboard remains at `/workspace`.

Everyone connects their own accounts from the settings screen. Nothing is
shared between users and no module is mandatory — if you do not use Jira, you
do not turn Jira on.

Next.js 16 · React 19 · SQLite · no UI framework, CSS written by hand.

> The interface is in Brazilian Portuguese. Code, comments and documentation
> are in English. There is no translation layer yet.

---

## Contents

- [What you can connect](#what-you-can-connect)
- [Why no OAuth for email](#why-no-oauth-for-email)
- [Getting started](#getting-started)
- [Where to get each credential](#where-to-get-each-credential)
- [Installing as an app](#installing-as-an-app)
- [How it is put together](#how-it-is-put-together)
- [Tests](#tests)
- [Deployment](#deployment)
- [Contributing](#contributing)
- [Security](#security)
- [License](#license)

---

## What you can connect

| Module | How it authenticates | Cost |
|---|---|---|
| Email | IMAP/SMTP with an app password | free |
| Calendar | Google OAuth, or an iCal (.ics) URL | free |
| Jira | Atlassian API token | free |
| Pull requests | GitHub personal access token | free |
| Tasks | stored on this server (default) | — |
| Quick notes | stored on this server; optional copy in Google Drive (OAuth) | free |
| Slack | OAuth with each user's own Slack account | free |

Each module is independent. A module with no connection does not render an
empty panel — it does not render at all.

**Tasks** live in the app's own database, so the panel works on first login
with nothing configured. If you have the `mstodo` CLI installed you can point
it at Microsoft To Do instead and keep phone sync.

**Quick notes** are Markdown. The editor has a toolbar and shortcuts (Ctrl/Cmd
+B, +I, +K for a link, +E for code, Ctrl/Cmd+Shift+X for strikethrough), and
Enter continues a list, a numbered list or a task list. **Visualizar** renders
the note with GitHub-flavoured Markdown — tables, task lists, fenced code with
syntax highlighting, links. Rendering never goes through `innerHTML`: raw HTML
in a note is dropped, the tree is sanitized against GitHub's allowlist, and
`javascript:`-style URLs are stripped.

Notes are saved on this server first, so typing never waits on the network.
**Guardar no Google Drive**, in the settings screen, adds a durable copy:
each note becomes a `.md` file in a *daily-web — notas* folder of the user's
own Drive, uploaded a few seconds after each change. The scope is
`drive.file`, so the app only sees files it created. On a fresh install,
connecting the same Google account brings the notes back. The copy is one-way —
editing the file in Drive does not change the note, and the next edit here
overwrites it. Deleting a note moves its file to the Drive trash. Notes that
existed before connecting are uploaded the next time they are edited.

## Why no OAuth for email

Email needs no OAuth application at all: an app password over IMAP works with
any provider, and each person generates their own in a minute.

Calendar has two paths. The iCal link requires nothing from whoever hosts the
app, but it is fragile: it is easy to copy the wrong link (Google shows three
on the same screen) and corporate Workspace administrators commonly disable
external sharing, which kills the secret address permanently. That is why the
Google connection exists, and it is the recommended path for Google accounts.

Creating the OAuth client is **free**. Google's paid CASA review is only
required to publish an app that reaches other people's accounts at scale; an
unverified app serves up to 100 accounts. Whoever hosts creates the client
once (step by step in `.env.example`, under `GOOGLE_CLIENT_ID`); everyone else
just clicks **Conectar com Google**. The same client serves the notes copy in
Google Drive, through the same redirect URI.
Focus blocks need the `calendar.events` scope; users who connected Google Calendar before this feature must reconnect once.

Slack follows the same host-once, connect-per-user model. Whoever hosts creates
one Slack app using the steps in `.env.example`; each person then clicks
**Conectar com Slack** and authorizes their own account. People who do not
connect it see no Slack panel or Slack notifications.

## Getting started

Node.js 22 or newer. Production runs 24, which is what `.nvmrc` pins for CI.

```sh
git clone https://github.com/joaosouzacoder/daily-web.git
cd daily-web
npm install
cp .env.example .env.local
```

Fill in at least `SESSION_SECRET` and `DAILY_WEB_SECRET_KEY`:

```sh
openssl rand -hex 32      # SESSION_SECRET
openssl rand -base64 32   # DAILY_WEB_SECRET_KEY
```

Create the first user and start:

```sh
npm run users -- add <username> <password> --admin
npm run dev                    # http://localhost:8010
```

`users` also takes `list`, `password <username> <new-password>` and
`remove <username>`.

Once you are in, open **Configuração** and connect what you use. Each module
carries a walkthrough of where to find the credential, and a **Testar** button
that tells you right away whether it worked.

## Where to get each credential

The inbox groups messages into conversations: one row per thread, with the
count and who took part, expanding to the messages in order. Inside a message,
the quoted history folds behind a button.

**Email** — needs an app password, not your account password:

- Gmail: turn on two-step verification, then generate one at
  [myaccount.google.com/apppasswords](https://myaccount.google.com/apppasswords)
- Outlook / Microsoft 365: at account.microsoft.com/security, under advanced
  security options
- iCloud: at account.apple.com, Security section
- Any other IMAP provider: choose "Outro" and fill in host and port

**Calendar** — on a Google account, click **Conectar com Google** and pick
which calendars to show. For other providers, use the iCal address:

- Google Calendar: Settings → click the calendar on the left → "Integrate
  calendar" → "Secret address in iCal format" (ends in `.ics` — it is not the
  address in your browser's bar)
- Outlook: Settings → Calendar → Shared calendars → Publish
- Apple, Fastmail, Nextcloud: any `.ics` URL works

It is read-only: the panel shows appointments, it does not create or edit them.
How many days appear — from today up to 14 — is each user's choice, in the
panel's own buttons, and it governs what the server fetches too.

**Jira** — API token at
[id.atlassian.com](https://id.atlassian.com/manage-profile/security/api-tokens).
The domain is the start of the URL: in `acme.atlassian.net`, it is `acme`.

The panel has two tabs. **Em aberto** lists the issues where you are the
assignee or the reporter; **Entregues** lists the ones you closed today, in
green. Both group by project and nest the hierarchy, so an epic and its
stories read as one tree. Nothing here names a status: the delivered list
asks for issues in the Done category that you moved today, which works the
same whether your workflow ends in "Resolvido" or in "Done".

**GitHub** — personal access token at
[github.com/settings/tokens](https://github.com/settings/tokens). Scope `repo`
for private repositories; for public ones, no scope is needed.

**Slack** — click **Conectar com Slack**. The panel shows mentions from the
last seven days and unread direct messages for the account that authorized it.
Some workspaces require an administrator to approve the app first.

## Rearranging the dashboard

Click **Organizar** to move panels by dragging and resize them by the
bottom-right corner; **Concluir** leaves the mode. Outside it the panels are
ordinary content, so clicking a message, ticking a task and selecting text
keep working.

**Salvar para esta tela** stores the arrangement together with the exact
window size it was made at; **Descartar** throws the changes away. Opening the
dashboard picks the saved arrangement whose window size is closest to the
current one, so a resized window keeps your layout and a different monitor gets
its own. **Restaurar disposição**, in the settings screen, clears them all.

Panels have a fixed height on the grid and scroll internally, which is what
makes resizing mean anything. Below 1024px the grid gives way to a single
column in the order the panels are arranged.

## Installing as an app

The page ships a manifest and a service worker, so Chrome offers **Install**
and it opens in its own window without an address bar. Works on desktop and
Android; on iOS, use "Add to Home Screen" from Safari.

The service worker caches nothing today — the panel shows data as it is right
now, and serving a stale copy would be worse than showing a network error. It
is the starting point for a PWA with a real per-route strategy.

## How it is put together

```
app/            Next.js App Router: pages and API routes
  api/          one route per action; each resolves the user from the cookie
components/     panels and UI primitives; no UI framework
lib/
  auth/         users, password hashing, session tokens
  vault/        AES-256-GCM encryption and per-user connections
  integrations/ IMAP, iCal, Google Calendar, Jira REST, GitHub REST
  tasks/        local SQLite provider and the optional mstodo adapter
  db.ts         schema and numbered migrations
  refresher.ts  background fetch loop and the per-user state cache
deploy/         systemd unit, Traefik snippets, publish and healthcheck
docs/           design documents
```

Two ideas explain most of the structure:

**Connections, not credentials.** A user can have several mailboxes and
several calendars. Each connection is a row with its own label, encrypted at
rest, resolved through the session's owner.

**I/O separated from logic.** Anything that talks to a network lives beside a
pure function that can be tested without one. `expandEvents` parses a calendar;
`fetchIcs` downloads it. That is why the suite runs in seconds with no fixture
server.

## Tests

```sh
npm test           # the whole suite, once
npm run test:watch
npm run build      # runs TypeScript
```

Tests never touch a real database: `tests/setup.ts` points every file at a
throwaway one. They never touch the network either.

## Deployment

`deploy/` holds **an example** of the setup this project uses: a host process
under systemd listening on `127.0.0.1:8010`, with Traefik in front terminating
TLS. The files contain paths and a domain specific to that machine — treat
them as a reference, not a ready-made configuration.

In short:

1. Create `/etc/daily-web/env` (outside git, `chmod 600`) from `.env.example`.
2. Adjust `deploy/daily-web.service` for your user, directory and `npm` path
   (`which npm`), then `systemctl enable --now`.
3. Merge `deploy/traefik-*-snippet.yml` into your Traefik `dynamic.yml`, or use
   whatever proxy you prefer.
4. Point DNS at the machine.

Pushes to `main` deploy automatically through a self-hosted GitHub Actions
runner: `deploy/publish.sh` copies the tested build into place and
`deploy/healthcheck.sh` confirms the service answers before the run goes
green. Read the security note at the top of `.github/workflows/deploy.yml`
before changing anything there.

## Contributing

Pull requests are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) first — it
says what tends to be accepted, what tends to be turned down, and how the
tests are written here.

The [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) applies.

## Security

Read [SECURITY.md](SECURITY.md) before exposing this anywhere. In short:
credentials are encrypted at rest with `DAILY_WEB_SECRET_KEY` and every
connection is resolved through the session's owner, so one person cannot reach
another's account. Even so this is **not multi-tenant**: there is no process
isolation and no audit log, and the machine's operator has the database. It is
built to run on your machine, for you and people you trust.

Report vulnerabilities privately through
[Security Advisories](https://github.com/joaosouzacoder/daily-web/security/advisories/new),
never in a public issue.

## License

[PolyForm Noncommercial 1.0.0](LICENSE) — free for personal use, study,
research, nonprofits and public institutions; commercial use is not permitted.

This is **not an open source license** in the OSI sense, which does not allow
field-of-use restrictions. It is source-available.


## Agent workspace and MCP

Open `/access` to create a personal reporting token, copy onboarding instructions,
and inspect or revoke MCP access. A token is shown once; the generated prompt uses
an environment-variable placeholder instead of copying the secret into a chat.
Each user sees only their own tasks, sessions, credentials and connections.

The reporting API is rooted at `/api/v1/agents`. The generated instructions describe
agent registration, sessions, task creation, transitions, activity and heartbeat.
Writes require `Idempotency-Key` and `X-Request-Timestamp`; metadata and lifecycle
updates also require the current version. Keep the same key and input when retrying.
The main board has one card per task, with its responsible agent/session. `/agents`
shows tasks and sessions; opening a card reveals its details and retained activity.

Agent work expires **30 days after its last accepted activity**. Reading or replaying
an update does not renew it. Session-only heartbeats do not keep tasks alive. Each
activity entry also expires after 30 days. Existing personal tasks, Jira issues and
GitHub PRs are not deleted by this policy. The cleanup worker does not need a browser
open; expired records are hidden even before physical cleanup runs.

The remote MCP endpoint is `/mcp` and requires OAuth. It exposes agent work, personal
tasks, Jira, GitHub and the shared focus action using the user's own permissions.
Provider operations require an explicit connection selection. Secrets are entered
only in the browser: an MCP client receives a setup URL, never an integration token.
Revocation takes effect on the next request or tool call. An uncertain provider
write is recorded and must be reconciled before it can be retried.

### OAuth companion

`npm run build` also builds the companion into `dist/oauth-server.js`. Use the same
`PUBLIC_ORIGIN`, database path and vault key for the application and companion;
configure its private Unix socket with `DAILY_WEB_OAUTH_SOCKET` and loopback port
with `DAILY_WEB_OAUTH_PORT`. Complete the application migrations before starting
`node dist/oauth-server.js`. The example systemd service and Traefik snippets in
`deploy/` show startup ordering, internal routing and health checks. Do not publish
the internal socket or the loopback port directly. The browser application remains
usable if the companion is unavailable; MCP authentication fails closed.

The companion implements authorization code + PKCE, scoped consent, rotating
refresh tokens, persistent encrypted grants and revocation. Configure a compatible
remote MCP client with the canonical HTTPS `/mcp` URL and complete its browser login.
Headless use requires previously completed authorization. Reporting tokens and MCP
OAuth tokens are different credentials and are not interchangeable.

### Backup and restore

Use the supported `scripts/backup.ts` and `scripts/restore.ts` flows for logical
backups. Agent tracking data is excluded; restore invalidates API/MCP credentials
before service startup, so an old backup cannot reactivate revoked access. Replace
raw database backup jobs before enabling agent reporting. Restoring requires users
to issue new reporting tokens and authorize MCP clients again.

Design, module scope and acceptance criteria live in `specs/001-agent-workspace/`.
Client interoperability and production-style routing must pass the documented
acceptance gates before deployment.
