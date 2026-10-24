import {beforeEach,afterEach,it,expect,vi} from 'vitest';
import {mkdtempSync,rmSync} from 'node:fs';
import path from 'node:path';
import {tmpdir} from 'node:os';
import {getDb} from '@/lib/db';
import {createCredential} from '@/lib/access/credentials';
import {GET,POST} from '@/app/api/v1/agents/tasks/route';
import {GET as detail,PATCH,DELETE} from '@/app/api/v1/agents/tasks/[id]/route';
import {POST as transition} from '@/app/api/v1/agents/tasks/[id]/transitions/route';
import {POST as report,GET as activity} from '@/app/api/v1/agents/tasks/[id]/activity/route';
import {POST as register} from '@/app/api/v1/agents/register/route';
import {POST as session,GET as sessions} from '@/app/api/v1/agents/sessions/route';
import {POST as heartbeat} from '@/app/api/v1/agents/sessions/[id]/heartbeat/route';
import {GET as sessionDetail} from '@/app/api/v1/agents/sessions/[id]/route';
let dir:string,secret:string;let seq=0;
const headers=(token=secret)=>({'content-type':'application/json',authorization:'Bearer '+token,'idempotency-key':`api-operation-${++seq}`,'x-request-timestamp':new Date().toISOString()});
const req=(value:unknown,method='POST',token=secret)=>new Request('http://localhost/api/v1/agents/tasks',{method,headers:headers(token),body:JSON.stringify(value)});
const params=(id:string)=>({params:Promise.resolve({id})});
beforeEach(()=>{dir=mkdtempSync(path.join(tmpdir(),'daily-reporting-'));process.env.DAILY_WEB_DB_PATH=path.join(dir,'test.db');for(const u of ['a','b'])getDb().prepare('INSERT INTO users(id,username,password_hash,is_admin,created_at) VALUES(?,?,?,?,?)').run(u,u,'unused',1,new Date().toISOString());secret=createCredential('a',{label:'api',scopes:['agents:read','agents:write']}).secret;});
afterEach(()=>{vi.useRealTimers();rmSync(dir,{force:true,recursive:true});});
it('executes every reporting route with scoped persisted identity',async()=>{const a=await (await register(req({externalId:'agent',provider:'codex',displayName:'Codex'}))).json();const s=await(await session(req({agentId:a.id,externalId:'session'}))).json();expect((await sessions(new Request('http://localhost/api/v1/agents/sessions',{headers:headers()}))).status).toBe(200);expect((await sessionDetail(new Request('http://localhost/x',{headers:headers()}),params(s.id))).status).toBe(200);expect((await heartbeat(req({}),params(s.id))).status).toBe(200);const created=await POST(req({externalId:'task',title:'Ship',assignment:{sessionId:s.id}}));expect(created.status).toBe(201);const t=await created.json();expect((await GET(new Request('http://localhost/api/v1/agents/tasks',{headers:headers()}))).status).toBe(200);expect((await detail(new Request('http://localhost/x',{headers:headers()}),params(t.id))).status).toBe(200);expect((await PATCH(req({expectedVersion:1,title:'Shipped'},'PATCH'),params(t.id))).status).toBe(200);expect((await transition(req({expectedVersion:2,status:'working'}),params(t.id))).status).toBe(200);expect((await report(req({kind:'progress',summary:'Testing'}),params(t.id))).status).toBe(200);expect((await activity(new Request('http://localhost/x',{headers:headers()}),params(t.id))).status).toBe(200);const del=new Request('http://localhost/x',{method:'DELETE',headers:headers()});expect((await DELETE(del,params(t.id))).status).toBe(204);expect((await DELETE(new Request(del),params(t.id))).status).toBe(204);});
it('rejects missing authentication, scopes, other users and unknown input',async()=>{expect((await GET(new Request('http://localhost/x'))).status).toBe(401);const read=createCredential('a',{label:'read',scopes:['agents:read']}).secret;expect((await POST(req({externalId:'t',title:'X'},'POST',read))).status).toBe(403);expect((await POST(req({externalId:'t',title:'X',owner:'b'}))).status).toBe(400);const t=await(await POST(req({externalId:'t',title:'X'}))).json();const other=createCredential('b',{label:'other',scopes:['agents:read']}).secret;const response=await detail(new Request('http://localhost/x',{headers:headers(other)}),params(t.id));expect(response.status).toBe(404);expect(response.headers.get('cache-control')).toBe('no-store');});
it('rejects bad JSON, oversized content, old timestamps and state races',async()=>{expect((await POST(new Request('http://localhost/x',{method:'POST',headers:headers(),body:'invalid'}))).status).toBe(400);expect((await POST(req({externalId:'t',title:'x'.repeat(70000)}))).status).toBe(413);const old=headers();old['x-request-timestamp']='2000-01-01';expect((await POST(new Request('http://localhost/x',{method:'POST',headers:old,body:JSON.stringify({externalId:'t',title:'X'})}))).status).toBe(400);const t=await(await POST(req({externalId:'t',title:'X'}))).json();expect((await transition(req({expectedVersion:4,status:'working'}),params(t.id))).status).toBe(409);expect((await transition(req({expectedVersion:1,status:'surprise'}),params(t.id))).status).toBe(400);});

it('exposes children as independent versioned reporting resources and roots as an explicit list scope',async()=>{
 const parentResponse=await POST(req({externalId:'subtask-parent',title:'Parent'}));expect(parentResponse.status).toBe(201);
 const parent=await parentResponse.json();expect(parent.parentTaskId).toBeNull();
 const childResponse=await POST(req({externalId:'subtask-child',title:'Child',parentTaskId:parent.id}));expect(childResponse.status).toBe(201);
 const child=await childResponse.json();expect(child.parentTaskId).toBe(parent.id);
 const roots=await GET(new Request('http://localhost/api/v1/agents/tasks?scope=roots',{headers:headers()}));expect(roots.status).toBe(200);expect((await roots.json()).items.map((item:{id:string})=>item.id)).toEqual([parent.id]);
 const children=await GET(new Request(`http://localhost/api/v1/agents/tasks?parentTaskId=${parent.id}`,{headers:headers()}));expect(children.status).toBe(200);expect((await children.json()).items.map((item:{id:string})=>item.id)).toEqual([child.id]);
 const working=await transition(req({status:'working',expectedVersion:1}),params(child.id));expect(working.status).toBe(200);expect((await working.json()).version).toBe(2);
 const progress=await report(req({kind:'progress',summary:'Child progress'}),params(child.id));expect(progress.status).toBe(200);
 const unchangedParent=await(await detail(new Request('http://localhost/x',{headers:headers()}),params(parent.id))).json();expect(unchangedParent.version).toBe(1);expect(unchangedParent.status).toBe('queued');
 const immutable=await PATCH(req({expectedVersion:2,parentTaskId:parent.id},'PATCH'),params(child.id));expect(immutable.status).toBe(400);
 const blocked=await DELETE(new Request('http://localhost/x',{method:'DELETE',headers:headers()}),params(parent.id));expect(blocked.status).toBe(409);expect((await blocked.json()).error.code).toBe('task_has_subtasks');
 expect((await DELETE(new Request('http://localhost/x',{method:'DELETE',headers:headers()}),params(child.id))).status).toBe(204);
 expect((await DELETE(new Request('http://localhost/x',{method:'DELETE',headers:headers()}),params(parent.id))).status).toBe(204);
});

it('denies unauthorized parent use and child access without leaking parent existence',async()=>{
 const parent=await(await POST(req({externalId:'private-parent',title:'Parent'}))).json();
 const child=await(await POST(req({externalId:'private-child',title:'Child',parentTaskId:parent.id}))).json();
 const other=createCredential('b',{label:'other-writer',scopes:['agents:read','agents:write']}).secret;
 const foreign=await POST(req({externalId:'foreign-child',title:'Forbidden',parentTaskId:parent.id},'POST',other));expect(foreign.status).toBe(404);
 const foreignList=await GET(new Request(`http://localhost/api/v1/agents/tasks?parentTaskId=${parent.id}`,{headers:headers(other)}));expect(foreignList.status).toBe(404);expect(foreignList.headers.get('cache-control')).toBe('no-store');
 expect((await PATCH(req({expectedVersion:1,title:'Foreign edit'},'PATCH',other),params(child.id))).status).toBe(404);
 expect((await transition(req({expectedVersion:1,status:'working'},'POST',other),params(child.id))).status).toBe(404);
 expect((await report(req({kind:'progress',summary:'Foreign report'},'POST',other),params(child.id))).status).toBe(404);
 expect((await DELETE(new Request('http://localhost/x',{method:'DELETE',headers:headers(other)}),params(child.id))).status).toBe(404);
 const nested=await POST(req({externalId:'grandchild',title:'Forbidden depth',parentTaskId:child.id}));expect(nested.status).toBe(400);expect((await nested.json()).error.code).toBe('invalid_parent');
 const readOnly=createCredential('a',{label:'read-only-child',scopes:['agents:read']}).secret;expect((await POST(req({externalId:'read-only-child',title:'Denied',parentTaskId:parent.id},'POST',readOnly))).status).toBe(403);
});

it('replays a child create without duplicates and rejects changing its parent under the same operation key',async()=>{
 const parent=await(await POST(req({externalId:'replay-parent',title:'Parent'}))).json();
 const other=await(await POST(req({externalId:'replay-other-parent',title:'Other'}))).json();
 const identity=headers(),input={externalId:'replayed-child',title:'Child',parentTaskId:parent.id};
 const create=()=>new Request('http://localhost/api/v1/agents/tasks',{method:'POST',headers:identity,body:JSON.stringify(input)});
 const first=await(await POST(create())).json(),second=await(await POST(create())).json();expect(second.id).toBe(first.id);
 const changed=await POST(new Request('http://localhost/api/v1/agents/tasks',{method:'POST',headers:identity,body:JSON.stringify({...input,parentTaskId:other.id})}));expect(changed.status).toBe(409);
 const children=await(await GET(new Request(`http://localhost/api/v1/agents/tasks?parentTaskId=${parent.id}`,{headers:headers()}))).json();expect(children.items).toHaveLength(1);
});


it('returns 404 for an expired parent without creating a child and rejects contradictory list filters',async()=>{
 const parent=await(await POST(req({externalId:'expiring-parent',title:'Parent'}))).json();
 const contradictory=await GET(new Request(`http://localhost/api/v1/agents/tasks?scope=roots&parentTaskId=${parent.id}`,{headers:headers()}));expect(contradictory.status).toBe(400);
 getDb().prepare('UPDATE main.tb_agent_task SET tsz_update=? WHERE uid_task=?').run(new Date(Date.now()-31*86400000).toISOString(),parent.id);
 const denied=await POST(req({externalId:'expired-parent-child',title:'Child',parentTaskId:parent.id}));expect(denied.status).toBe(404);expect((await denied.json()).error.code).toBe('not_found');
 expect((await GET(new Request(`http://localhost/api/v1/agents/tasks?parentTaskId=${parent.id}`,{headers:headers()}))).status).toBe(404);
 expect(getDb().prepare('SELECT COUNT(*) AS count FROM main.tb_agent_task WHERE uid_parent_task=?').get(parent.id)).toEqual({count:0});
});
it('accepts a waiting hold over HTTP, returns it, and rejects a reason that does not match the status',async()=>{const t=await(await POST(req({externalId:'held',title:'Ship'}))).json();const working=await(await transition(req({expectedVersion:1,status:'working'}),params(t.id))).json();expect((await transition(req({expectedVersion:working.version,status:'blocked',hold:{reason:'deploy'}}),params(t.id))).status).toBe(400);const waiting=await transition(req({expectedVersion:working.version,status:'waiting',hold:{reason:'pull_request',note:'PR #81'}}),params(t.id));expect(waiting.status).toBe(200);expect(await waiting.json()).toMatchObject({status:'waiting',hold:{reason:'pull_request',note:'PR #81'}});expect(await(await detail(new Request('http://localhost/x',{headers:headers()}),params(t.id))).json()).toMatchObject({hold:{reason:'pull_request',note:'PR #81'}});});
