import {afterEach,beforeEach,describe,expect,it,vi} from 'vitest';
import {mkdtempSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import path from 'node:path';
const push=vi.hoisted(()=>({send:vi.fn()}));
vi.mock('web-push',()=>{class WebPushError extends Error{statusCode:number;constructor(message:string,statusCode:number){super(message);this.statusCode=statusCode;}}return {default:{sendNotification:push.send},WebPushError};});
vi.mock('@/lib/auth/currentUser',()=>({getCurrentUser:vi.fn()}));
import {WebPushError} from 'web-push';
import {getCurrentUser} from '@/lib/auth/currentUser';
import {getDb} from '@/lib/db';
import * as ops from '@/lib/agents/operations';
import {pushEndpoint,saveSubscription,removeSubscription,subscriptionsOf} from '@/lib/push/subscriptions';
import {drainPush} from '@/lib/push/dispatch';
import {sessionKey} from '@/lib/agents/deck';
import {GET as key} from '@/app/api/push/route';
import {POST as subscribe,DELETE as unsubscribe} from '@/app/api/push/subscriptions/route';
import {POST as test} from '@/app/api/push/test/route';
import {POST as ownerTransition} from '@/app/api/agents/tasks/[id]/transitions/route';

const ORIGIN='https://daily.example';
const FCM='https://fcm.googleapis.com/fcm/send/device-1';
const KEYS={p256dh:'B'+'A'.repeat(86),auth:'A'.repeat(22)};
let dir:string,sequence=0;
const mutation=()=>({key:`push-operation-${++sequence}`,requestedAt:new Date().toISOString()});
type Outbox={kind:string;state:string;payload:string;due:string;attempts:number};
const outbox=()=>getDb().prepare('SELECT typ_kind AS kind,typ_state AS state,jsn_payload AS payload,tsz_due AS due,num_attempts AS attempts FROM main.tb_push_outbox ORDER BY tsz_insert,rowid').all() as Outbox[];
function session(owner='a'){const agent=ops.registerAgent(owner,{externalId:`agent-${++sequence}`,provider:'claude',displayName:'Claude — Linux'},mutation());return ops.createSession(owner,{agentId:agent.id,externalId:`session-${++sequence}`},mutation());}
function task(sessionId:string,input:Partial<ops.CreateTask>={}){return ops.createTask('a',{externalId:`task-${++sequence}`,title:'Ship the feature',assignment:{sessionId},...input},mutation());}
const move=(id:string,status:string,version:number,hold?:unknown)=>ops.transitionTask('a',id,{status:status as never,expectedVersion:version,...(hold?{hold}:{})},mutation());
const browser=(method:string,body?:unknown,origin=ORIGIN)=>new Request(`${ORIGIN}/api/push`,{method,headers:{'content-type':'application/json',origin,'idempotency-key':`push-${++sequence}`,'x-request-timestamp':new Date().toISOString()},...(body===undefined?{}:{body:JSON.stringify(body)})});

beforeEach(()=>{
 dir=mkdtempSync(path.join(tmpdir(),'daily-push-'));
 vi.stubEnv('DAILY_WEB_DB_PATH',path.join(dir,'db'));
 vi.stubEnv('PUBLIC_ORIGIN',ORIGIN);
 vi.stubEnv('DAILY_WEB_VAPID_PUBLIC_KEY','public-key');
 vi.stubEnv('DAILY_WEB_VAPID_PRIVATE_KEY','private-key');
 vi.stubEnv('DAILY_WEB_AGENT_DECK_OWNER','');
 for(const id of ['a','b'])getDb().prepare('INSERT INTO users(id,username,password_hash,is_admin,created_at) VALUES(?,?,?,?,?)').run(id,id,'unused',0,new Date().toISOString());
 vi.mocked(getCurrentUser).mockResolvedValue({id:'a',username:'a',passwordHash:'unused',isAdmin:false,createdAt:'2026-01-01'});
 push.send.mockReset();push.send.mockResolvedValue({statusCode:201});
});
afterEach(()=>{vi.useRealTimers();vi.unstubAllEnvs();rmSync(dir,{recursive:true,force:true});});

describe('push subscriptions',()=>{
 it('accepts only the HTTPS endpoints of the browsers push services',()=>{
  for(const url of [FCM,'https://updates.push.services.mozilla.com/wpush/v2/x','https://web.push.apple.com/x','https://wns2-bl2p.notify.windows.com/w/?token=x'])expect(pushEndpoint(url)).toBe(new URL(url).toString());
  for(const url of ['http://fcm.googleapis.com/x','https://fcm.googleapis.com.evil.example/x','https://evil.example/fcm.googleapis.com','https://user:pass@fcm.googleapis.com/x','https://fcm.googleapis.com:8443/x','https://127.0.0.1/x','not a url',42])expect(()=>pushEndpoint(url)).toThrowError(expect.objectContaining({status:400}));
 });
 it('upserts by endpoint, follows the last user who subscribed and only removes the owner subscription',()=>{
  const first=saveSubscription('a',{endpoint:FCM,keys:KEYS,expirationTime:null});
  expect(saveSubscription('a',{endpoint:FCM,keys:KEYS})).toEqual(first);
  removeSubscription('b',{endpoint:FCM});
  expect(subscriptionsOf('a')).toHaveLength(1);
  saveSubscription('b',{endpoint:FCM,keys:KEYS});
  expect(subscriptionsOf('a')).toEqual([]);
  expect(subscriptionsOf('b')).toHaveLength(1);
  expect(()=>saveSubscription('a',{endpoint:FCM,keys:{p256dh:'short',auth:KEYS.auth}})).toThrowError(expect.objectContaining({status:400}));
 });
 it('exposes the public key and requires a same-origin browser session to subscribe',async()=>{
  expect(await(await key(browser('GET'))).json()).toEqual({publicKey:'public-key'});
  expect((await subscribe(browser('POST',{endpoint:FCM,keys:KEYS},'https://attacker.example'))).status).toBe(403);
  expect((await subscribe(browser('POST',{endpoint:'https://evil.example/x',keys:KEYS}))).status).toBe(400);
  expect((await subscribe(browser('POST',{endpoint:FCM,keys:KEYS}))).status).toBe(201);
  expect((await unsubscribe(browser('DELETE',{endpoint:FCM}))).status).toBe(204);
  expect(subscriptionsOf('a')).toEqual([]);
  vi.mocked(getCurrentUser).mockResolvedValue(null);
  expect((await key(browser('GET'))).status).toBe(401);
 });
 it('sends a test only when a device is subscribed and keys are configured',async()=>{
  expect((await test(browser('POST',{}))).status).toBe(409);
  saveSubscription('a',{endpoint:FCM,keys:KEYS});
  expect(await(await test(browser('POST',{}))).json()).toEqual({devices:1});
  await drainPush();
  expect(push.send).toHaveBeenCalledTimes(1);
  vi.stubEnv('DAILY_WEB_VAPID_PRIVATE_KEY','');
  expect((await test(browser('POST',{}))).status).toBe(503);
 });
});

describe('agent push events',()=>{
 it('notifies when the agent finishes or fails a main task, never for subtasks or the owner own changes',async()=>{
  const s=session();
  const done=task(s.id,{title:'Ship the feature'}),failed=task(s.id,{title:'Migrate'}),mine=task(s.id),child=task(s.id,{parentTaskId:done.id});
  move(child.id,'completed',1);
  move(done.id,'working',1);move(done.id,'completed',2);
  move(failed.id,'working',1);move(failed.id,'failed',2);
  expect((await ownerTransition(new Request(`${ORIGIN}/x`,{method:'POST',headers:{'content-type':'application/json',origin:ORIGIN,'idempotency-key':`owner-${++sequence}`,'x-request-timestamp':new Date().toISOString()},body:JSON.stringify({status:'completed',expectedVersion:1})}),{params:Promise.resolve({id:mine.id})})).status).toBe(200);
  expect(outbox().map(event=>[event.kind,JSON.parse(event.payload).title])).toEqual([['finished','Concluída: Ship the feature'],['finished','Falhou: Migrate']]);
  expect(JSON.parse(outbox()[0].payload)).toMatchObject({body:'Claude — Linux terminou a tarefa.',url:`/agents/tasks/${done.id}`,tag:`task-${done.id}`});
 });
 it('notifies a block that needs the user, once per reason or note change',()=>{
  const s=session(),t=task(s.id),other=task(s.id);
  move(t.id,'blocked',1,{reason:'decision',note:'A ou B'});
  move(t.id,'blocked',2,{reason:'decision',note:'A ou B'});
  move(t.id,'blocked',3,{reason:'decision',note:'C ou D'});
  move(other.id,'blocked',1,{reason:'dependency',note:'Outra equipe'});
  expect(outbox().map(event=>JSON.parse(event.payload).body)).toEqual(['Decisão do usuário — A ou B','Decisão do usuário — C ou D']);
 });
 it('holds back an idle signal for 30 seconds and does not repeat an unchanged kind',()=>{
  vi.useFakeTimers({toFake:['Date']});vi.setSystemTime(Date.parse('2026-10-25T10:00:00.000Z'));
  const s=session();
  ops.setSessionAttention('a',s.id,{attention:{kind:'input'}},mutation());
  ops.setSessionAttention('a',s.id,{attention:{kind:'input'}},mutation());
  ops.setSessionAttention('a',s.id,{attention:{kind:'permission'}},mutation());
  ops.setSessionAttention('a',s.id,{attention:null},mutation());
  expect(outbox().map(event=>[event.kind,event.due])).toEqual([['attention','2026-10-25T10:00:30.000Z'],['attention','2026-10-25T10:00:00.000Z']]);
 });
});

describe('push dispatcher',()=>{
 beforeEach(()=>{saveSubscription('a',{endpoint:FCM,keys:KEYS});});
 it('delivers the payload to every device with the VAPID keys',async()=>{
  const s=session(),t=task(s.id);move(t.id,'completed',1);
  await drainPush();
  expect(push.send).toHaveBeenCalledWith({endpoint:FCM,keys:KEYS},expect.stringContaining('"title":"Concluída: Ship the feature"'),expect.objectContaining({vapidDetails:{publicKey:'public-key',privateKey:'private-key',subject:ORIGIN},TTL:3600}));
  expect(outbox()[0].state).toBe('sent');
  await drainPush();
  expect(push.send).toHaveBeenCalledTimes(1);
 });
 it('forgets an expired device and retries a transient failure later',async()=>{
  const s=session(),t=task(s.id);move(t.id,'completed',1);
  push.send.mockRejectedValueOnce(new (WebPushError as unknown as new(message:string,status:number)=>Error)('gone',410));
  await drainPush();
  expect(subscriptionsOf('a')).toEqual([]);
  expect(outbox()[0].state).toBe('dropped');
  saveSubscription('a',{endpoint:FCM,keys:KEYS});
  const u=task(s.id);move(u.id,'completed',1);
  push.send.mockRejectedValueOnce(new Error('network down'));
  await drainPush();
  const retry=outbox()[1];
  expect([retry.state,retry.attempts]).toEqual(['pending',1]);
  expect(Date.parse(retry.due)).toBeGreaterThan(Date.now()+30_000);
 });
 it('sends an idle signal only if it still stands and the agent is not just waiting for a process',async()=>{
  vi.useFakeTimers({toFake:['Date']});vi.setSystemTime(Date.parse('2026-10-25T10:00:00.000Z'));
  const s=session(),t=task(s.id,{title:'Review'});move(t.id,'working',1);
  ops.setSessionAttention('a',s.id,{attention:{kind:'input'}},mutation());
  await drainPush();
  expect(push.send).not.toHaveBeenCalled();
  vi.setSystemTime(Date.parse('2026-10-25T10:00:31.000Z'));
  await drainPush();
  expect(JSON.parse(push.send.mock.calls[0][1])).toMatchObject({title:'Aguardando sua resposta: Review',body:'Claude — Linux parou e está esperando você.',tag:`session-${s.id}`});
  move(t.id,'waiting',2,{reason:'build',note:'CI'});
  ops.setSessionAttention('a',s.id,{attention:null},mutation());
  ops.setSessionAttention('a',s.id,{attention:{kind:'input'}},mutation());
  vi.setSystemTime(Date.parse('2026-10-25T10:01:10.000Z'));
  await drainPush();
  expect(push.send).toHaveBeenCalledTimes(1);
  expect(outbox().at(-1)!.state).toBe('dropped');
 });
 it('drops an idle signal that cleared before it was due, and a permission request is sent at once',async()=>{
  vi.useFakeTimers({toFake:['Date']});vi.setSystemTime(Date.parse('2026-10-25T10:00:00.000Z'));
  const s=session(),t=task(s.id,{title:'Deploy'});move(t.id,'working',1);
  ops.setSessionAttention('a',s.id,{attention:{kind:'input'}},mutation());
  ops.setSessionAttention('a',s.id,{attention:null},mutation());
  vi.setSystemTime(Date.parse('2026-10-25T10:00:31.000Z'));
  await drainPush();
  expect(push.send).not.toHaveBeenCalled();
  ops.setSessionAttention('a',s.id,{attention:{kind:'permission'}},mutation());
  await drainPush();
  expect(JSON.parse(push.send.mock.calls[0][1]).title).toBe('Pedindo permissão: Deploy');
 });
 it('drops an idle signal while the terminal shows the agent running something in the background',async()=>{
  vi.useFakeTimers({toFake:['Date']});vi.setSystemTime(Date.parse('2026-10-25T10:00:00.000Z'));
  vi.stubEnv('DAILY_WEB_AGENT_DECK_OWNER','a');
  vi.stubEnv('AGENT_DECK_BIN',path.resolve('tests/fixtures/agent-deck/fake-agent-deck.mjs'));
  vi.stubEnv('FAKE_DECK_DIR',dir);
  delete (globalThis as {__agentDeckListings?:unknown}).__agentDeckListings;
  const agent=ops.registerAgent('a',{externalId:`agent-${++sequence}`,provider:'claude',displayName:'Claude'},mutation());
  const s=ops.createSession('a',{agentId:agent.id,externalId:sessionKey('claude','960b1dad-1792822461')},mutation());
  const t=task(s.id);move(t.id,'working',1);
  ops.setSessionAttention('a',s.id,{attention:{kind:'input'}},mutation());
  vi.setSystemTime(Date.parse('2026-10-25T10:00:31.000Z'));
  await drainPush();
  expect(push.send).not.toHaveBeenCalled();
  expect(outbox().at(-1)!.state).toBe('dropped');
 });
 it('drops events when nobody is subscribed or the server has no keys',async()=>{
  const s=session(),t=task(s.id);
  vi.stubEnv('DAILY_WEB_VAPID_PRIVATE_KEY','');
  move(t.id,'completed',1);
  await drainPush();
  expect(outbox()[0].state).toBe('dropped');
  expect(push.send).not.toHaveBeenCalled();
 });
});
