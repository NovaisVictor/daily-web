import { sessionToolResult } from './mcp-result.mjs';
import { privateDirectory, privateJson } from './private-runtime.mjs';
import fs from 'node:fs';
import http from 'node:http';
import { spawn } from 'node:child_process';
import { resolve } from 'node:path';
import { gunzipSync, inflateSync, brotliDecompressSync } from 'node:zlib';

const directory = privateDirectory(process.argv[2] ?? '');
const configuration = privateJson(directory, 'runtime-env.json');
const environment = { ...process.env, ...configuration, DAILY_WEB_VALIDATION_DIRECTORY: directory };
const oauthViaNext = process.argv.includes('--oauth-via-next');
const eventsPath = resolve(directory, 'oauth-events.jsonl');
const phasePath = resolve(directory, 'validation-phase.json');
const children = [];
const record = event => fs.appendFileSync(eventsPath, JSON.stringify({ at: new Date().toISOString(), ...event }) + '\n', { mode: 0o600 });
const phase = () => { try { return JSON.parse(fs.readFileSync(phasePath, 'utf8')).phase; } catch { return 'unassigned'; } };
function start(arguments_, log) {
  const child = spawn(process.execPath, arguments_, { env: environment, stdio: ['ignore', fs.openSync(resolve(directory, log), 'a', 0o600), fs.openSync(resolve(directory, log), 'a', 0o600)] });
  children.push(child);
  return child;
}
if (!process.argv.includes('--external-app')) start(['node_modules/next/dist/bin/next', 'start', '-p', '8024', '-H', '127.0.0.1'], 'validation-next.log');
start(['--import', resolve('scripts/validation/oauth-diagnostics.mjs'), 'dist/oauth-server.js'], 'validation-oauth.log');
const proxy = http.createServer((request, response) => {
  const oauth = request.url.startsWith('/oauth/') || ['/.well-known/oauth-authorization-server/oauth', '/.well-known/openid-configuration/oauth'].includes(request.url);
  const port = oauth && !oauthViaNext ? 8023 : 8024;
  const tokenRequest = request.url === '/oauth/token';
  if (request.url.startsWith('/oauth/auth?')) {
    const parameters = new URL(request.url, configuration.PUBLIC_ORIGIN).searchParams;
    const knownScopes = new Set(['openid','offline_access','agents:read','agents:write','tasks:read','tasks:write','jira:read','jira:write','github:read','github:write','connections:read','connections:write','agenda:focus']);
    const scopes = (parameters.get('scope') ?? '').split(' ').filter(Boolean);
    record({ phase: phase(), kind: 'authorization-request', scopes: scopes.every(scope => knownScopes.has(scope)) ? scopes : ['unknown_scope'], consentPromptRequested: parameters.get('prompt')?.split(' ').includes('consent') ?? false });
  }
  const capturedPhase = phase();
  let grantType = 'unknown', requestMethod, toolName, bytes = 0, chunks = [];
  if (tokenRequest || request.url === '/mcp') {
    request.on('data', chunk => { bytes += chunk.length; if (bytes <= 65536) chunks.push(chunk); });
    request.on('end', () => { if (bytes <= 65536) { const body = Buffer.concat(chunks).toString(); if (tokenRequest) grantType = new URLSearchParams(body).get('grant_type') ?? 'unknown'; else { try { const message = JSON.parse(body); requestMethod = message.method; toolName = message.params?.name; record({ phase: capturedPhase, kind: 'mcp-request', method: message.method, ...(message.method === 'tools/call' ? { tool: message.params?.name } : {}) }); } catch {} } } chunks = []; });
  }
  const upstream = http.request({ hostname: '127.0.0.1', port, path: request.url, method: request.method, headers: { ...request.headers, 'x-forwarded-proto': 'http', 'x-forwarded-host': '127.0.0.1:8022' } }, result => {
    if (tokenRequest) {
      record({ phase: capturedPhase, kind: 'token-exchange', grantType, httpStatus: result.statusCode });
      let responseBytes = 0, responseChunks = [];
      result.on('data', chunk => { responseBytes += chunk.length; if (responseBytes <= 65536) responseChunks.push(chunk); });
      result.on('end', () => {
        if (responseBytes <= 65536 && result.statusCode >= 400) {
          try { const error = JSON.parse(Buffer.concat(responseChunks).toString()); const description = String(error.error_description ?? ''); record({ phase: capturedPhase, kind: 'token-error', error: /^[a-z_]{1,40}$/.test(error.error) ? error.error : 'unclassified', categories: ['scope','resource','expired','not found','already used','client mismatch','session','unsupported','required','duplicate','request body','authorization'].filter(category => description.includes(category)) }); } catch {}
        }
        responseChunks = [];
      });
    }
    if (request.url === '/mcp') {
      record({ phase: capturedPhase, kind: 'mcp-response', httpStatus: result.statusCode });
      let responseBytes = 0, responseChunks = [];
      result.on('data', chunk => { responseBytes += chunk.length; if (responseBytes <= 65536) responseChunks.push(chunk); });
      result.on('end', () => {
        if (requestMethod === 'tools/call' && responseBytes <= 65536) {
          try {
            let body = Buffer.concat(responseChunks);
            const encoding = result.headers['content-encoding'];
            if (encoding === 'gzip') body = gunzipSync(body, { maxOutputLength: 65536 });
            if (encoding === 'deflate') body = inflateSync(body, { maxOutputLength: 65536 });
            if (encoding === 'br') body = brotliDecompressSync(body, { maxOutputLength: 65536 });
            const text = body.toString();
            const messages = text.startsWith('{') ? [JSON.parse(text)] : text.split('\n').filter(line => line.startsWith('data:')).map(line => JSON.parse(line.slice(5)));
            for (const message of messages) {
              if (!message.result && !message.error) continue;
              const summary = toolName === 'agents_sessions_list' ? sessionToolResult(message) : { result: message.error || message.result?.isError ? 'error' : 'success' };
              record({ phase: capturedPhase, kind: 'mcp-tool-result', tool: toolName, httpStatus: result.statusCode, ...summary });
            }
          } catch {}
        }
        responseChunks = [];
      });
    }
    response.writeHead(result.statusCode, result.headers);
    result.pipe(response);
  });
  upstream.on('error', () => { if (!response.headersSent) response.writeHead(503); response.end('unavailable'); });
  upstream.setTimeout(15000, () => upstream.destroy());
  request.pipe(upstream);
});
proxy.requestTimeout = 10000;
proxy.listen(8022, '127.0.0.1', async () => {
  const deadline = Date.now() + 30000;
  while (Date.now() < deadline) {
    try {
      const [application, metadata] = await Promise.all([
        fetch('http://127.0.0.1:8022/api/agent-access/config', { signal: AbortSignal.timeout(1000) }),
        fetch('http://127.0.0.1:8022/.well-known/oauth-authorization-server/oauth', { signal: AbortSignal.timeout(1000) }),
      ]);
      if (application.status === 401 && metadata.status === 200) { console.log('Disposable validation runtime ready on loopback ports8022/8023/8024'); return; }
    } catch {}
    await new Promise(resolve_ => setTimeout(resolve_, 250));
  }
  console.error('Disposable validation runtime did not become ready'); stop();
});
function stop() { for (const child of children) child.kill('SIGTERM'); proxy.close(() => process.exit(0)); setTimeout(() => process.exit(1), 5000).unref(); }
process.on('SIGTERM', stop);
process.on('SIGINT', stop);
