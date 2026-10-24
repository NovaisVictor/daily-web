import {afterEach,beforeEach,describe,expect,it,vi} from 'vitest';
import {existsSync,mkdtempSync,readFileSync,rmSync,writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import path from 'node:path';
vi.mock('@/lib/auth/currentUser',()=>({getCurrentUser:vi.fn()}));
import {getCurrentUser} from '@/lib/auth/currentUser';
import {getDb} from '@/lib/db';
import * as ops from '@/lib/agents/operations';
import {liveState,sessionKey} from '@/lib/agents/deck';
import {GET as live} from '@/app/api/agents/sessions/[id]/live/route';
import {POST as message} from '@/app/api/agents/sessions/[id]/messages/route';
import {GET as snapshot} from '@/app/api/agents/route';

const ORIGIN='https://daily.example';
const BIN=path.resolve('tests/fixtures/agent-deck/fake-agent-deck.mjs');
const DECK_ID='960b1dad-1792822461';
let dir:string,sequence=0;
const mutation=()=>({key:`terminal-operation-${++sequence}`,requestedAt:new Date().toISOString()});
const params=(id:string)=>({params:Promise.resolve({id})});
const user=(id:string)=>vi.mocked(getCurrentUser).mockResolvedValue({id,username:id,passwordHash:'unused',isAdmin:true,createdAt:'2026-01-01'});
function session(owner:string,externalId:string){const agent=ops.registerAgent(owner,{externalId:`agent-${++sequence}`,provider:'claude',displayName:'Claude'},mutation());return ops.createSession(owner,{agentId:agent.id,externalId},mutation());}
function post(id:string,text:unknown,key=`message-${++sequence}`,origin=ORIGIN){return message(new Request(`${ORIGIN}/api/agents/sessions/${id}/messages`,{method:'POST',headers:{'content-type':'application/json',origin,'idempotency-key':key,'x-request-timestamp':new Date().toISOString()},body:JSON.stringify({text})}),params(id));}
const sends=()=>existsSync(path.join(dir,'sends.jsonl'))?readFileSync(path.join(dir,'sends.jsonl'),'utf8').trim().split('\n').map(line=>JSON.parse(line)):[];

beforeEach(()=>{
 dir=mkdtempSync(path.join(tmpdir(),'daily-agent-terminal-'));
 vi.stubEnv('DAILY_WEB_DB_PATH',path.join(dir,'db'));
 vi.stubEnv('PUBLIC_ORIGIN',ORIGIN);
 vi.stubEnv('AGENT_DECK_BIN',BIN);
 vi.stubEnv('FAKE_DECK_DIR',dir);
 vi.stubEnv('DAILY_WEB_AGENT_DECK_OWNER','a');
 delete (globalThis as {__agentDeckList?:unknown}).__agentDeckList;
 for(const id of ['a','b'])getDb().prepare('INSERT INTO users(id,username,password_hash,is_admin,created_at) VALUES(?,?,?,?,?)').run(id,id,'unused',1,new Date().toISOString());
 user('a');
});
afterEach(()=>{vi.unstubAllEnvs();rmSync(dir,{recursive:true,force:true});});

describe('agent deck bridge',()=>{
 it('derives the same session key as the reporting helper',()=>{
  expect(sessionKey('claude',DECK_ID,'host-a')).toBe('dw-70fce3576277274e1af71f3b3b14b520');
 });
 it('maps every deck status to a live state, preferring background work over an idle prompt',()=>{
  expect(liveState({status:'running',substate:'running'})).toBe('working');
  expect(liveState({status:'starting',substate:null})).toBe('working');
  expect(liveState({status:'waiting',substate:'running'})).toBe('background');
  expect(liveState({status:'idle',substate:'running'})).toBe('background');
  expect(liveState({status:'waiting',substate:'menu-open'})).toBe('prompt');
  expect(liveState({status:'waiting',substate:'idle-at-empty-prompt'})).toBe('idle');
  expect(liveState({status:'stopped',substate:null})).toBe('stopped');
  expect(liveState({status:'error',substate:'running'})).toBe('stopped');
 });
 it('shows the terminal and last response of the owner local session without escape codes',async()=>{
  const s=session('a',sessionKey('claude',DECK_ID));
  const value=await(await live(new Request(`${ORIGIN}/x`),params(s.id))).json();
  expect(value.available).toBe(true);
  expect(value.live).toEqual({state:'background',since:'2026-10-24T06:12:08Z'});
  expect(value.pane).toBe('◯ general-purpose  Verifying e2e… 54m 54s\n❯ faz o push');
  expect(value.response).toEqual({content:'Build rodando em segundo plano; aviso quando terminar.',at:'2026-10-24T06:12:08.305Z'});
 });
 it('fails closed when no owner is configured or the viewer is someone else',async()=>{
  const s=session('a',sessionKey('claude',DECK_ID));
  vi.stubEnv('DAILY_WEB_AGENT_DECK_OWNER','');
  expect(await(await live(new Request(`${ORIGIN}/x`),params(s.id))).json()).toEqual({available:false,reason:'not_enabled'});
  expect((await post(s.id,'oi')).status).toBe(403);
  vi.stubEnv('DAILY_WEB_AGENT_DECK_OWNER','a');
  const other=session('b',sessionKey('claude',DECK_ID));
  user('b');
  expect(await(await live(new Request(`${ORIGIN}/x`),params(other.id))).json()).toEqual({available:false,reason:'not_enabled'});
  expect((await live(new Request(`${ORIGIN}/x`),params(s.id))).status).toBe(404);
  expect((await post(s.id,'oi')).status).toBe(404);
  expect(sends()).toEqual([]);
 });
 it('reports sessions that do not run on this host as not local',async()=>{
  const s=session('a',sessionKey('claude','not-on-this-host'));
  expect(await(await live(new Request(`${ORIGIN}/x`),params(s.id))).json()).toEqual({available:false,reason:'not_local'});
  expect((await post(s.id,'oi')).status).toBe(404);
 });
 it('adds live state to the board and lets busy sessions keep their raw attention',async()=>{
  const s=session('a',sessionKey('claude',DECK_ID));
  ops.setSessionAttention('a',s.id,{attention:{kind:'input'}},mutation());
  ops.createTask('a',{externalId:`task-${++sequence}`,title:'Ship',assignment:{sessionId:s.id}},mutation());
  const value=await(await snapshot(new Request(`${ORIGIN}/api/agents`))).json();
  expect(value.tasks.items[0].assignment.live).toEqual({state:'background',since:'2026-10-24T06:12:08Z'});
  expect(value.tasks.items[0].assignment.attention.kind).toBe('input');
  expect(value.sessions.items[0].live.state).toBe('background');
 });
 it('queues a reply once per idempotency key, through stdin, even when it looks like a flag',async()=>{
  const s=session('a',sessionKey('claude',DECK_ID));
  const first=await post(s.id,'--help me','reply-key-0001');
  expect(first.status).toBe(202);
  expect(await first.json()).toEqual({ok:true,id:'01M5P8QK3ZCBEJ7831BP5842MF',state:'queued'});
  expect((await post(s.id,'--help me','reply-key-0001')).status).toBe(202);
  expect(sends()).toEqual([{args:['session','send','--message-file','-','--queue','--json','--no-tag',DECK_ID],text:'--help me'}]);
  expect((await post(s.id,'other text','reply-key-0001')).status).toBe(409);
 });
 it('lets a refused send be retried with the same key and rejects bad input and foreign origins',async()=>{
  const s=session('a',sessionKey('claude',DECK_ID));
  writeFileSync(path.join(dir,'refuse'),'');
  expect((await post(s.id,'oi','reply-key-0002')).status).toBe(502);
  rmSync(path.join(dir,'refuse'));
  expect((await post(s.id,'oi','reply-key-0002')).status).toBe(202);
  expect(sends()).toHaveLength(1);
  expect((await post(s.id,'   ')).status).toBe(400);
  expect((await post(s.id,'x'.repeat(4001))).status).toBe(400);
  expect((await post(s.id,'oi',undefined,'https://attacker.example')).status).toBe(403);
  vi.mocked(getCurrentUser).mockResolvedValue(null);
  expect((await post(s.id,'oi')).status).toBe(401);
  expect(sends()).toHaveLength(1);
 });
 it('refuses to type into a stopped session',async()=>{
  writeFileSync(path.join(dir,'list.json'),JSON.stringify([{id:DECK_ID,tool:'claude',status:'stopped',substate:null}]));
  const s=session('a',sessionKey('claude',DECK_ID));
  const response=await post(s.id,'oi');
  expect(response.status).toBe(409);
  expect((await response.json()).error.code).toBe('session_stopped');
  expect(sends()).toEqual([]);
 });
});
