import { EventEmitter } from 'node:events';
import fs from 'node:fs';
import { resolve } from 'node:path';
const original = EventEmitter.prototype.emit;
const descriptions = new Set(['refresh token not found', 'refresh token is expired', 'refresh token already used', 'client mismatch', 'grant is invalid', 'session not found']);
const knownScopes = new Set(['openid', 'offline_access', 'agents:read', 'agents:write', 'tasks:read', 'tasks:write', 'jira:read', 'jira:write', 'github:read', 'github:write', 'connections:read', 'connections:write', 'agenda:focus']);
EventEmitter.prototype.emit = function (event, ...arguments_) {
  if (event === 'grant.error' && process.env.DAILY_WEB_VALIDATION_DIRECTORY) {
    const [context, error] = arguments_;
    const directory = process.env.DAILY_WEB_VALIDATION_DIRECTORY;
    let phase = 'unassigned'; try { phase = JSON.parse(fs.readFileSync(resolve(directory, 'validation-phase.json'), 'utf8')).phase; } catch {}
    const parameters = context?.oidc?.params ?? {};
    const scopes = String(parameters.scope ?? '').split(' ').filter(Boolean);
    const code = /^[a-z_]{1,40}$/.test(error?.error) ? error.error : 'unclassified';
    fs.appendFileSync(resolve(directory, 'oauth-events.jsonl'), JSON.stringify({ at: new Date().toISOString(), phase, kind: 'provider-grant-error', error: code, description: descriptions.has(error?.error_description) ? error.error_description : 'other', scope: scopes.every(scope => knownScopes.has(scope)) ? scopes : ['unknown_scope'], resourceMatches: parameters.resource === `${process.env.PUBLIC_ORIGIN}/mcp`, hasClientId: typeof parameters.client_id === 'string' }) + '\n', { mode: 0o600 });
  }
  return original.call(this, event, ...arguments_);
};
