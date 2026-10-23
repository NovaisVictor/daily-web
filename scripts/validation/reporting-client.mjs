import { privateDirectory, privateJson } from './private-runtime.mjs';
import fs from 'node:fs';
import { spawn } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { resolve } from 'node:path';
import { z } from 'zod';
const credentialResponse = z.object({ secret: z.string().regex(/^dwp_[A-Za-z0-9_-]{43}$/), credential: z.object({ id: z.uuid() }) });
const promptResponse = z.object({ prompt: z.string().min(1) });
const taskPage = z.object({ items: z.array(z.object({ id: z.uuid(), externalId: z.string(), status: z.enum(['queued','working','blocked','completed','failed','cancelled']) })), nextCursor: z.string().nullable(), complete: z.literal(true) });
const activityPage = z.object({ items: z.array(z.object({ kind: z.enum(['progress','transition','created','updated']), summary: z.string() })), nextCursor: z.string().nullable(), complete: z.literal(true) });

const [client, directoryArgument] = process.argv.slice(2);
if (!['claude', 'codex', 'agy'].includes(client) || !directoryArgument) throw new Error('Usage: reporting-client.mjs claude|codex|agy PRIVATE_RUNTIME_DIRECTORY');
const directory = privateDirectory(directoryArgument);
const auth = privateJson(directory, 'auth.json');
const browserHeaders = { Cookie: `daily_web_session=${auth.users[0].session}`, Origin: auth.base, 'Content-Type': 'application/json' };
const request = async (path, options = {}) => fetch(new URL(path, auth.base), { ...options, signal: AbortSignal.timeout(5000) });
const startedAt = new Date().toISOString(), started = performance.now();
const created = await request('/api/agent-access/tokens', { method: 'POST', headers: browserHeaders, body: JSON.stringify({ label: `Disposable ${client} onboarding`, scopes: ['agents:read', 'agents:write'] }) });
if (created.status !== 201) throw new Error(`Credential creation HTTP${created.status}`);
const { secret, credential } = credentialResponse.parse(await created.json());
const generated = await request('/api/agent-access/prompt', { headers: browserHeaders });
const { prompt } = promptResponse.parse(await generated.json());
if (!prompt.includes('<DAILY_WEB_REPORTING_TOKEN>') || prompt.includes(secret)) throw new Error('Unsafe generated prompt');
const externalId = `onboarding-${client}-${randomUUID()}`;
const summary = `Verified ${client} generated-prompt reporting`;
const provider = client === 'agy' ? 'gemini' : client;
const instruction = `${prompt}\n\nDisposable local acceptance. Follow the generated instructions above using provider ${provider}. The credential is already in the DAILY_WEB_REPORTING_TOKEN environment variable: reference process.env.DAILY_WEB_REPORTING_TOKEN in Node fetch; never print/read its value into conversation, command output, files, or URLs. Use Node fetch for HTTP, no MCP tools. Register your agent and session, create one task with externalId ${externalId} and title "${client} onboarding acceptance", transition it to working, and post progress summary "${summary}". Then stop: no other tasks or providers, no repository edits, no environment inspection. Report only completion and accepted HTTP status codes. All writes need their own UUID idempotency key and current ISO request timestamp. Session/task responses are direct JSON objects. Do not invent successful results. Use the real API now.`;
const common = { cwd: process.cwd(), env: { ...process.env, DAILY_WEB_REPORTING_TOKEN: secret }, detached: true, stdio: ['pipe', 'pipe', 'pipe'] };
let child;
if (client === 'claude') child = spawn('claude', ['--print', '--no-session-persistence', '--strict-mcp-config', '--mcp-config', '{"mcpServers":{}}', '--allowedTools', 'Bash(node:*)', '--tools', 'Bash'], common);
if (client === 'codex') child = spawn('codex', ['exec', '--ephemeral', '--skip-git-repo-check', '-s', 'workspace-write', '-c', 'sandbox_workspace_write.network_access=true', instruction], common);
if (client === 'agy') child = spawn('python3', [resolve('scripts/validation/cli-pty.py'), 'agy'], common);
let buffer = '', sent = client !== 'agy', approvals = 0, approvalNotified = false, done = false;
const privateLog = fs.openSync(resolve(directory, `${externalId}.log`), 'a', 0o600);
const receive = chunk => {
  if (done) return;
  fs.writeSync(privateLog, chunk); buffer = (buffer + chunk).slice(-65536);
  const clean = buffer.replace(/\x1b\[[0-9;?]*[A-Za-z]/g, '');
  if (client === 'agy' && !sent && clean.includes('Gemini 4 Argon')) { sent = true; buffer = ''; child.stdin.write(instruction + '\r'); console.log('Generated reporting instructions delivered to agy'); }
  if (client === 'agy' && (clean.includes('Allow running this command?') || clean.includes('Run this command?')) && !approvalNotified) {
    approvalNotified = true; console.log('Agy command approval requires operator inspection; driver will not grant broad permission');
  }
};
child.stdout.on('data', receive); child.stderr.on('data', receive);
if (client === 'claude') child.stdin.end(instruction);
if (client === 'codex') child.stdin.end();
let exitCode;
child.on('exit', code => { exitCode = code; });
process.stdin.on('data', data => { if (client === 'agy' && !done) { child.stdin.write(data); approvals++; approvalNotified = false; } });
let result;
try {
  const deadline = Date.now() + 240000;
  while (Date.now() < deadline) {
    await new Promise(resolve_ => setTimeout(resolve_, 1000));
    const listed = await request('/api/v1/agents/tasks?limit=100', { headers: { Authorization: `Bearer ${secret}` } });
    if (listed.status !== 200) throw new Error(`Task listing HTTP${listed.status}`);
    const body = taskPage.parse(await listed.json()); const task = body.items.find(item => item.externalId === externalId);
    if (task?.status === 'working') {
      const activity = await request(`/api/v1/agents/tasks/${encodeURIComponent(task.id)}/activity?limit=100`, { headers: { Authorization: `Bearer ${secret}` } });
      const history = activityPage.parse(await activity.json());
      if (activity.status === 200 && history.items.some(item => item.kind === 'progress' && item.summary === summary)) {
        result = { client, provider, startedAt, elapsedMs: Math.round(performance.now() - started), generatedPrompt: 'unmodified server-generated instructions with secret placeholder', tokenDelivery: 'child process environment only', taskStatus: task.status, progressAccepted: true, result: 'passed' }; break;
      }
    }
    if (exitCode !== undefined) break;
  }
  if (!result) result = { client, provider, startedAt, elapsedMs: Math.round(performance.now() - started), result: 'failed', exitCode: exitCode ?? null };
} finally {
  done = true;
  const revoked = await request(`/api/agent-access/tokens/${encodeURIComponent(credential.id)}`, { method: 'DELETE', headers: browserHeaders });
  const denied = await request('/api/v1/agents/tasks?limit=1', { headers: { Authorization: `Bearer ${secret}` } });
  result ??= { client, result: 'failed' }; result.revocationHttpStatus = revoked.status; result.revokedTokenHttpStatus = denied.status;
  fs.writeFileSync(resolve(directory, `reporting-${client}-result.json`), JSON.stringify(result, null, 2) + '\n', { mode: 0o600 });
  child.stdin.destroy(); try { process.kill(-child.pid, 'SIGTERM'); } catch {} fs.closeSync(privateLog);
  result.credentialLiteralInOutput = fs.readFileSync(resolve(directory, `${externalId}.log`), 'utf8').includes(secret);
  result.approvedCommands = approvals;
  fs.writeFileSync(resolve(directory, `reporting-${client}-result.json`), JSON.stringify(result, null, 2) + '\n', { mode: 0o600 });
}
console.log(JSON.stringify(result));
process.exit(result.result === 'passed' && result.revokedTokenHttpStatus === 401 ? 0 : 1);
