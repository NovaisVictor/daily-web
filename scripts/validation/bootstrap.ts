import { mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { randomBytes } from 'node:crypto';

process.umask(0o077);
const directory = mkdtempSync(join(tmpdir(), 'daily-web-client-validation-'));
const environment = {
  NODE_ENV: 'production',
  PUBLIC_ORIGIN: 'http://127.0.0.1:8022',
  DAILY_WEB_DB_PATH: join(directory, 'app.db'),
  DAILY_WEB_SECRET_KEY: randomBytes(32).toString('base64'),
  SESSION_SECRET: randomBytes(32).toString('base64url'),
  DAILY_WEB_OAUTH_RUNTIME_DIR: directory,
  DAILY_WEB_OAUTH_SOCKET: join(directory, 'oauth.sock'),
  DAILY_WEB_OAUTH_PORT: '8023',
};
Object.assign(process.env, environment);
const { createUser } = await import('../../lib/auth/users');
const { createSessionToken } = await import('../../lib/auth/session');
const { getDb } = await import('../../lib/db');
const user = await createUser('validation-owner', randomBytes(32).toString('base64url'));
const session = await createSessionToken(user.id, user.username, environment.SESSION_SECRET);
writeFileSync(join(directory, 'runtime-env.json'), JSON.stringify(environment), { mode: 0o600 });
writeFileSync(join(directory, 'auth.json'), JSON.stringify({ base: environment.PUBLIC_ORIGIN, users: [{ id: user.id, username: user.username, session }] }), { mode: 0o600 });
getDb().close();
console.log(directory);
