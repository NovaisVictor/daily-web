import { privateDirectory, privateJson } from './private-runtime.mjs';
import fs from 'node:fs';
import { spawn } from 'node:child_process';
import { resolve } from 'node:path';
import { chromium } from 'playwright';

const [client, mode, directoryArgument] = process.argv.slice(2);
if (!['claude', 'codex', 'agy'].includes(client) || !['authenticate', 'call'].includes(mode) || !directoryArgument) throw new Error('Usage: oauth-client.mjs claude|codex|agy authenticate|call PRIVATE_RUNTIME_DIRECTORY');
const directory = privateDirectory(directoryArgument), server = 'daily_oauth_proof';
const auth = privateJson(directory, 'auth.json');
const origin = auth.base;
const startedAt = new Date().toISOString(), started = performance.now();
const phase = `${client}-${mode}`;
const requireRefresh = process.argv.includes('--require-refresh');
fs.writeFileSync(resolve(directory, 'validation-phase.json'), JSON.stringify({ phase }), { mode: 0o600 });
const pty = resolve('scripts/validation/cli-pty.py');
const prompt = 'Development interoperability acceptance: use the actual MCP tool agents_sessions_list exposed by server daily_oauth_proof with JSON input {"limit":1}. Call it exactly once. The tool namespace may include the server name; select the available agents_sessions_list tool. Do not read files, run commands, reauthorize, or use other tools. Report success and item count from the actual response. If unavailable, report the precise blocker. Use the existing OAuth login.';
let command, arguments_;
if (client === 'codex') {
  command = 'codex'; arguments_ = [...(mode === 'authenticate' ? ['-c', `mcp_servers.${server}.url="${origin}/mcp"`, 'mcp', 'login', server, '--no-browser', '--scopes', 'agents:read', '--oauth-client-registration', 'dcr'] : ['exec', '--ephemeral', '--skip-git-repo-check', '-s', 'read-only', '-C', '/tmp', '-c', `mcp_servers.${server}.url="${origin}/mcp"`, '-c', `mcp_servers.${server}.enabled_tools=["agents_sessions_list"]`, prompt])];
} else if (client === 'claude' && mode === 'authenticate') {
  command = 'python3'; arguments_ = [pty, 'claude', 'mcp', 'login', server, '--no-browser'];
} else if (client === 'claude') {
  command = 'claude'; arguments_ = ['--print', '--no-session-persistence', '--strict-mcp-config', '--mcp-config', JSON.stringify({ mcpServers: { [server]: { type: 'http', url: `${origin}/mcp` } } }), '--allowedTools', `mcp__${server}__agents_sessions_list`, '--tools', ''];
} else { command = 'python3'; arguments_ = [pty, 'agy']; }
const child = spawn(command, arguments_, { cwd: process.cwd(), detached: true, stdio: ['pipe', 'pipe', 'pipe'] });
if (mode === 'call' && client === 'codex') child.stdin.end();
if (mode === 'call' && client === 'claude') child.stdin.end(prompt);
let browser, context, buffer = '', began = false, consented = false, approved = false, stage = 0, returning = false, stopped = false;
const log = fs.openSync(resolve(directory, `${phase}-${Date.now()}.log`), 'a', 0o600);
const cleanText = text => text.replace(/\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)/g, '').replace(/\x1b\[[0-9;?]*[A-Za-z]/g, '');
async function authorize(url) {
  browser = await chromium.launch({ channel: 'chrome', headless: true }); context = await browser.newContext();
  await context.addCookies([{ name: 'daily_web_session', value: auth.users[0].session, url: origin }]);
  const page = await context.newPage();
  await page.route('**/*', async route => {
    const target = new URL(route.request().url());
    if (target.searchParams.has('code') && ((client === 'agy' && target.origin === 'https://antigravity.google' && target.pathname === '/oauth-callback') || (client !== 'agy' && ['localhost', '127.0.0.1'].includes(target.hostname) && target.pathname.includes('callback')))) {
      child.stdin.write((client === 'agy' ? target.searchParams.get('code') : target.href) + (client === 'agy' ? '\r' : '\n'));
      await route.fulfill({ status: 200, contentType: 'text/plain', body: 'Development authorization complete' });
    } else await route.continue();
  });
  await page.goto(url);
  try { await page.getByRole('button', { name: 'Entendi', exact: true }).click({ timeout: 3000 }); } catch {}
  await page.getByRole('button', { name: 'Autorizar', exact: true }).click({ timeout: 15000 });
  consented = true; console.log(`${client}: browser consent submitted`);
}
function receive(chunk) {
  if (stopped) return;
  fs.writeSync(log, chunk); buffer = (buffer + chunk.toString()).slice(-120000); const clean = cleanText(buffer);
  if (client === 'agy' && stage === 0 && clean.includes('Gemini 4 Argon')) { stage = 1; child.stdin.write(mode === 'authenticate' ? '/mcp\r' : prompt + '\r'); }
  if (client === 'agy' && mode === 'authenticate') {
    if (stage === 1 && clean.includes('MCP Servers') && clean.includes(server)) { stage = 2; setTimeout(() => { child.stdin.write('\x1b[B'.repeat(Number(process.env.AGY_MCP_POSITION ?? 4))); setTimeout(() => child.stdin.write('\r'), 300); }, 5000); }
    if (stage === 2 && clean.includes('Authenticate') && clean.includes('Restart')) { stage = 3; child.stdin.write('\x1b[C\x1b[C\r'); }
    const compact = clean.replace(/\s/g, '').replace(/[\x00-\x1f]/g, '');
    const end = compact.lastIndexOf('Pastetheauthorizationcodebelow:'); const start = compact.lastIndexOf(`${origin}/oauth/auth?`, end);
    if (stage === 3 && start >= 0 && end > start && !began) { began = true; stage = 4; authorize(compact.slice(start, end)).catch(() => finish('browser-failed')); }
    if (stage === 4 && clean.includes('Authentication successful!') && !returning) { returning = true; child.stdin.write('\r'); }
  } else if (mode === 'authenticate' && !began) {
    const match = clean.match(new RegExp(origin.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + '/oauth/auth\\?[^\\s]+'));
    if (match) { began = true; authorize(match[0].replace(/[\x00-\x1f].*$/s, '')).catch(() => finish('browser-failed')); }
  }
  if (client === 'agy' && mode === 'call' && !approved && clean.includes(`${server}/agents_sessions_list`) && clean.includes('Allow calling this tool?')) { approved = true; buffer = ''; child.stdin.write('1\r'); console.log('Approved once: agents_sessions_list only'); }
  if (client === 'agy' && mode === 'call' && approved && (/(?:sucesso|success|funcionou).{0,100}1\s*item/i.test(clean.replace(/\s+/g, ' ')) || (/sucesso|success/i.test(clean) && /(?:items\.length|count)[).:\s]*1\b/i.test(clean)))) finish('passed');
  if (client === 'agy' && mode === 'authenticate' && returning && new RegExp(`${server}\\s+\\[Authed\\]`).test(clean)) finish('passed');
}
child.stdout.on('data', receive); child.stderr.on('data', receive);
const progress = setInterval(() => console.log(`${client}: ${mode} still running (${Math.round((performance.now() - started) / 1000)}s)`), 20000);
const toolResultPoll = mode === 'call' ? setInterval(() => { const path = resolve(directory, 'oauth-events.jsonl'); if (!fs.existsSync(path)) return; const results = fs.readFileSync(path, 'utf8').split('\n').filter(Boolean).map(line => JSON.parse(line)); if (results.some(event => event.at >= startedAt && event.phase === phase && event.kind === 'mcp-tool-result' && event.tool === 'agents_sessions_list' && event.result === 'success' && event.httpStatus === 200 && event.itemCount === 1)) finish('passed'); }, 1000) : undefined;
const timer = setTimeout(() => finish('timeout'), 240000);
async function finish(outcome, exitCode) {
  if (stopped) return; stopped = true; clearInterval(progress); if (toolResultPoll) clearInterval(toolResultPoll); clearTimeout(timer);
  const clean = cleanText(buffer);
  if (outcome === 'exited') outcome = exitCode === 0 && (mode === 'authenticate' ? /authenticated|success|logged in/i.test(clean) : /(?:sucesso|success|funcionou|succeeded).{0,150}(?:1|one)\s*item/i.test(clean)) ? 'passed' : 'unconfirmed';
  const eventsFile = resolve(directory, 'oauth-events.jsonl');
  const events = fs.existsSync(eventsFile) ? fs.readFileSync(eventsFile, 'utf8').split('\n').filter(Boolean).map(line => JSON.parse(line)).filter(event => event.at >= startedAt && event.phase === phase) : [];
  const toolResults = events.filter(event => event.kind === 'mcp-tool-result' && event.tool === 'agents_sessions_list');
  if (mode === 'call' && toolResults.some(event => event.result === 'success' && event.httpStatus === 200 && event.itemCount === 1)) outcome = 'passed';
  if (mode === 'authenticate' && !events.some(event => event.kind === 'token-exchange' && event.grantType === 'authorization_code' && event.httpStatus === 200)) outcome = 'unconfirmed';
  if (mode === 'call' && outcome === 'passed' && !events.some(event => event.kind === 'mcp-request' && event.method === 'tools/call' && event.tool === 'agents_sessions_list')) outcome = 'unconfirmed';
  if (requireRefresh && (!events.some(event => event.kind === 'token-exchange' && event.grantType === 'refresh_token' && event.httpStatus === 200) || events.some(event => event.kind === 'token-exchange' && event.grantType === 'authorization_code'))) outcome = 'unconfirmed';
  const result = { client, mode, requireRefresh, toolResults, startedAt, elapsedMs: Math.round(performance.now() - started), outcome, consented, approvedOnce: approved, refreshExchanges: events.filter(event => event.kind === 'token-exchange' && event.grantType === 'refresh_token').map(({ at, httpStatus }) => ({ at, httpStatus })), authorizationCodeExchanges: events.filter(event => event.kind === 'token-exchange' && event.grantType === 'authorization_code').length, actualToolRequests: events.filter(event => event.kind === 'mcp-request' && event.method === 'tools/call').map(event => event.tool) };
  fs.writeFileSync(resolve(directory, `${phase}-result.json`), JSON.stringify(result, null, 2) + '\n', { mode: 0o600 });
  console.log(JSON.stringify(result));
  child.stdin.destroy(); try { process.kill(-child.pid, 'SIGTERM'); } catch {} if (browser) await browser.close().catch(() => {}); fs.closeSync(log); process.exit(outcome === 'passed' ? 0 : 1);
}
child.on('exit', code => finish('exited', code));
