# Managed OAuth services and logical backups

`deploy/publish.sh` installs the OAuth companion on the first upgrade, including
hosts that only have the original `daily-web.service`. After copying the tested
artifact it invokes `deploy/install-services.mjs` as root using the runner's
resolved Node executable. The installer reads the existing application's systemd
`User`, `WorkingDirectory`, `EnvironmentFiles` and `MainPID`; the running process's
`/proc/<pid>/exe` identifies its actual Node binary. A stopped application uses
the installer's resolved Node binary. Installation fails for root app accounts,
ambiguous environment files, invalid paths or mismatched deployment directories.

The installer preserves the existing application unit and writes a managed
`50-agent-workspace.conf` drop-in plus OAuth service, backup service and daily
timer. Files must either be absent or carry the installer management marker;
custom units and symbolic links are not replaced. Re-running installation is
idempotent. Application and OAuth share a private `RuntimeDirectory` with mode
`0700` and `RuntimeDirectoryPreserve=yes`; migration runs before application
startup. OAuth starts only after the application. The daily backup timer is
enabled automatically. No infrastructure router changes are required by this
installer.

Publishing first validates service ownership and unit conflicts without writes,
then stops an existing companion before copying artifacts, installs the
services, restarts the application and starts the companion. Both application
and OAuth health must return HTTP 200, with bounded retries. Default checks are
`http://127.0.0.1:8010/login` and `http://127.0.0.1:8011/health`; customize
`DAILY_WEB_HEALTH_URL` and `DAILY_WEB_OAUTH_HEALTH_URL` for nondefault listeners.
A failed copy, installation, restart or health check fails publication. An old
companion is not restarted against a partially replaced artifact.

## Backup commands and storage

The production artifact includes `dist/backup.js` and `dist/restore.js`; no
TypeScript development runner is required:

```sh
node dist/backup.js /absolute/source.db /private/new-backup.db
node dist/restore.js /private/backup.db /private/new-database.db
```

The managed timer runs `node dist/backup.js --scheduled` as the existing service
account with its existing environment file and working directory. Source is
`DAILY_WEB_DB_PATH`, or `data/daily-web.db` under that working directory, matching
the application's default. Destination is `DAILY_WEB_BACKUP_DIR`; the managed
unit configures `data/backups/logical` under the actual working directory. The
environment file can supply a different absolute directory. Scheduled mode
requires a directory owned by the service account with mode `0700` and rejects
a symbolic link destination. Every backup is a new uniquely named file with
mode `0600`. Previous backups are retained; the installer never deletes legacy
or raw backup files.

Logical backups omit agent identities, sessions, tasks, activity, agent mutation
receipts and OAuth records. Personal API credentials are revoked in the copy.
Restoration creates a new database and applies the same exclusions and
revocation. It never overwrites the running database. Restored users must issue
new API credentials and authorize OAuth again. Existing non-agent application
information is retained. Credentials for other integrations remain encrypted;
back up the vault key separately using the host's secret-management process.

## Host audit evidence and rollout boundary

A read-only audit of the production host on 2026-10-23 found the original app
service, its configured public origin and no OAuth companion unit. The audit
checked 17 readable cron files and the systemd unit inventory: no Daily Web raw
backup, restic, borg, rclone or snapshot job was found; only the unrelated dpkg
database backup existed. This supports installing the new logical timer without
replacing a known application backup job. It does not certify storage snapshots
or backup systems outside the audited host. No production service changes were
made during preparation or local tests.
