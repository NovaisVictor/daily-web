import {afterEach,beforeEach,describe,expect,it,vi} from 'vitest';
import {mkdtempSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {getDb} from '@/lib/db';
import * as ops from '@/lib/agents/operations';
import {cleanupAgents} from '@/lib/agents/retention';
import {RETENTION_MS} from '@/lib/agents/model';
let directory:string,sequence=0;
const mutation=()=>({key:`subtask-operation-${++sequence}`,requestedAt:new Date().toISOString()});
const task=(owner='a',input:Partial<ops.CreateTask>={})=>ops.createTask(owner,{externalId:`task-${++sequence}`,title:'Parent work',...input},mutation());
const child=(parentTaskId:string,input:Partial<ops.CreateTask>={})=>task('a',{parentTaskId,title:'Child work',...input});
const advance=()=>vi.setSystemTime(Date.now()+1000);
beforeEach(()=>{
 directory=mkdtempSync(path.join(tmpdir(),'daily-agent-subtasks-'));
 vi.stubEnv('DAILY_WEB_DB_PATH',path.join(directory,'db'));
 for(const id of ['a','b'])getDb().prepare('INSERT INTO users(id,username,password_hash,is_admin,created_at) VALUES(?,?,?,?,?)').run(id,id,'unused',0,new Date().toISOString());
});
afterEach(()=>{vi.useRealTimers();vi.unstubAllEnvs();rmSync(directory,{recursive:true,force:true});});

describe('agent subtask ownership and structure',()=>{
 it('returns an explicit nullable parent for roots and an immutable parent for children',()=>{
  const parent=task(),other=task(),subtask=child(parent.id);
  expect(parent.parentTaskId).toBeNull();expect(subtask.parentTaskId).toBe(parent.id);
  expect(ops.getTask('a',subtask.id).parentTaskId).toBe(parent.id);
  expect(()=>ops.updateTask('a',subtask.id,{expectedVersion:1,parentTaskId:other.id} as never,mutation())).toThrow();
  expect(ops.getTask('a',subtask.id).parentTaskId).toBe(parent.id);
 });
 it('rejects another child as a parent and conceals missing, foreign and expired parents',()=>{
  const parent=task(),subtask=child(parent.id),foreign=task('b');
  expect(()=>child(subtask.id)).toThrowError(expect.objectContaining({status:400,code:'invalid_parent'}));
  for(const id of ['missing-parent',foreign.id])expect(()=>child(id)).toThrowError(expect.objectContaining({status:404,code:'not_found'}));
  vi.setSystemTime(Date.parse(parent.lastActivityAt)+RETENTION_MS+1);
  expect(()=>child(parent.id)).toThrowError(expect.objectContaining({status:404,code:'not_found'}));
 });
 it('does not create receipts or orphan children for a rejected parent',()=>{
  const foreign=task('b'),input={externalId:'rejected-child',title:'Denied',parentTaskId:foreign.id},key=mutation();
  expect(()=>ops.createTask('a',input,key)).toThrow();
  expect(ops.listTasks('a').items).toEqual([]);
  expect(getDb().prepare('SELECT COUNT(*) AS count FROM main.tb_mutation_receipt WHERE uid_user=? AND ref_key=?').get('a',key.key)).toEqual({count:0});
 });
 it('filters roots and a particular parent without leaking another owner and keeps stable cursor pages',()=>{
  const first=task(),second=task(),foreign=task('b');
  const children=Array.from({length:5},()=>child(first.id));child(second.id);
  expect(ops.listTasks('a').items).toHaveLength(8);
  expect(new Set(ops.listTasks('a',{scope:'roots'}).items.map(item=>item.id))).toEqual(new Set([first.id,second.id]));
  const page=ops.listTasks('a',{parentTaskId:first.id,limit:2}),next=ops.listTasks('a',{parentTaskId:first.id,limit:2,cursor:page.nextCursor!});
  expect(page.items.every(item=>item.parentTaskId===first.id)).toBe(true);
  expect(next.items.map(item=>item.id).some(id=>page.items.some(item=>item.id===id))).toBe(false);
  expect(ops.listTasks('a',{parentTaskId:first.id,sort:'oldest'}).items).toHaveLength(children.length);
  expect(()=>ops.listTasks('a',{parentTaskId:foreign.id})).toThrowError(expect.objectContaining({status:404}));
  expect(()=>ops.listTasks('a',{scope:'unknown'} as never)).toThrowError(expect.objectContaining({status:400}));
 });
 it('inherits an omitted assignment, permits explicit unassignment and rejects a foreign session',()=>{
  const agent=ops.registerAgent('a',{externalId:'claude',provider:'claude',displayName:'Claude'},mutation());
  const session=ops.createSession('a',{agentId:agent.id,externalId:'session'},mutation());
  const foreignAgent=ops.registerAgent('b',{externalId:'codex',provider:'codex',displayName:'Codex'},mutation());
  const foreign=ops.createSession('b',{agentId:foreignAgent.id,externalId:'session'},mutation());
  const parent=task('a',{assignment:{sessionId:session.id}});
  expect(child(parent.id).assignment?.sessionId).toBe(session.id);
  expect(child(parent.id,{assignment:null}).assignment).toBeNull();
  expect(()=>child(parent.id,{assignment:{sessionId:foreign.id}})).toThrowError(expect.objectContaining({status:404}));
 });
});

describe('independent child lifecycle and parent activity',()=>{
 it('touches parent activity for each successful child write without changing parent status/version or creating parent events',()=>{
  const parent=task();advance();const subtask=child(parent.id);
  const expectParent=()=>{const current=ops.getTask('a',parent.id);expect(current.lastActivityAt).toBe(new Date().toISOString());expect(current.status).toBe('queued');expect(current.version).toBe(1);expect(ops.listActivity('a',parent.id).items).toHaveLength(1);};
  expectParent();advance();ops.updateTask('a',subtask.id,{expectedVersion:1,title:'Changed child'},mutation());expectParent();
  advance();ops.transitionTask('a',subtask.id,{expectedVersion:2,status:'working'},mutation());expectParent();
  advance();ops.reportActivity('a',subtask.id,{kind:'progress',summary:'Verified progress'},mutation());expectParent();
  expect(ops.getTask('a',subtask.id).version).toBe(3);
  expect(ops.getTask('a',subtask.id).status).toBe('working');
  advance();ops.reportActivity('a',subtask.id,{kind:'heartbeat'},mutation());expectParent();
 });
 it('does not touch parent activity for replayed creation/update/activity, a no-op update, or a rejected version',()=>{
  const parent=task(),input={externalId:'replayed-child',title:'Child',parentTaskId:parent.id},create=mutation();advance();
  const subtask=ops.createTask('a',input,create);const before=ops.getTask('a',parent.id).lastActivityAt;
  advance();ops.createTask('a',input,create);expect(ops.getTask('a',parent.id).lastActivityAt).toBe(before);
  ops.updateTask('a',subtask.id,{expectedVersion:1,title:'Child'},mutation());expect(ops.getTask('a',parent.id).lastActivityAt).toBe(before);
  expect(()=>ops.updateTask('a',subtask.id,{expectedVersion:99,title:'Rejected'},mutation())).toThrow();expect(ops.getTask('a',parent.id).lastActivityAt).toBe(before);
  const update=mutation(),patch={expectedVersion:1,title:'Changed'};ops.updateTask('a',subtask.id,patch,update);const written=ops.getTask('a',parent.id).lastActivityAt;
  advance();ops.updateTask('a',subtask.id,patch,update);expect(ops.getTask('a',parent.id).lastActivityAt).toBe(written);
  const report=mutation(),event={kind:'progress' as const,summary:'Once'};ops.reportActivity('a',subtask.id,event,report);const progressed=ops.getTask('a',parent.id).lastActivityAt;
  advance();ops.reportActivity('a',subtask.id,event,report);expect(ops.getTask('a',parent.id).lastActivityAt).toBe(progressed);
 });
 it('replays child transitions without touching either task again and rejects an independent version race',()=>{
  const parent=task(),subtask=child(parent.id),key=mutation(),input={expectedVersion:1,status:'working' as const};
  advance();const transitioned=ops.transitionTask('a',subtask.id,input,key);const parentAt=ops.getTask('a',parent.id).lastActivityAt;
  advance();expect(ops.transitionTask('a',subtask.id,input,key).version).toBe(transitioned.version);
  expect(ops.getTask('a',parent.id).lastActivityAt).toBe(parentAt);
  expect(()=>ops.transitionTask('a',subtask.id,{expectedVersion:1,status:'blocked'},mutation())).toThrowError(expect.objectContaining({code:'version_conflict'}));
  expect(ops.getTask('a',parent.id).version).toBe(1);
  expect(ops.listActivity('a',subtask.id).items.filter(item=>item.kind==='transition')).toHaveLength(1);
 });
 it('rejects idempotency key reuse with another parent and never reparents the child',()=>{
  const first=task(),second=task(),input={externalId:'unique-child',title:'Child',parentTaskId:first.id},key=mutation();
  const subtask=ops.createTask('a',input,key);
  expect(()=>ops.createTask('a',{...input,parentTaskId:second.id},key)).toThrowError(expect.objectContaining({status:409,code:'idempotency_conflict'}));
  expect(ops.getTask('a',subtask.id).parentTaskId).toBe(first.id);
 });
 it('touches the parent once for an explicit child deletion and never again on replay',()=>{
  const parent=task(),subtask=child(parent.id),key=mutation();advance();
  ops.deleteTask('a',subtask.id,key);const parentAfter=ops.getTask('a',parent.id);
  expect(parentAfter.lastActivityAt).toBe(new Date().toISOString());expect(parentAfter.version).toBe(1);expect(parentAfter.status).toBe('queued');
  advance();ops.deleteTask('a',subtask.id,key);expect(ops.getTask('a',parent.id).lastActivityAt).toBe(parentAfter.lastActivityAt);
 });
 it('prevents parent deletion while any child exists and leaves both resources unchanged',()=>{
  const parent=task(),first=child(parent.id),second=child(parent.id);
  expect(()=>ops.deleteTask('a',parent.id,mutation())).toThrowError(expect.objectContaining({status:409,code:'task_has_subtasks'}));
  expect(ops.getTask('a',parent.id).version).toBe(1);expect(ops.getTask('a',first.id).parentTaskId).toBe(parent.id);
  ops.deleteTask('a',first.id,mutation());expect(()=>ops.deleteTask('a',parent.id,mutation())).toThrowError(expect.objectContaining({code:'task_has_subtasks'}));
  ops.deleteTask('a',second.id,mutation());expect(()=>ops.deleteTask('a',parent.id,mutation())).not.toThrow();
 });
});

describe('subtask retention and bounded indexed reads',()=>{
 it('keeps a parent visible through child activity and expires them after thirty inactive days',()=>{
  const parent=task(),subtask=child(parent.id);vi.setSystemTime(Date.parse(parent.lastActivityAt)+RETENTION_MS-1000);
  ops.reportActivity('a',subtask.id,{kind:'progress',summary:'Still working'},mutation());const refreshed=ops.getTask('a',parent.id);
  vi.setSystemTime(Date.parse(parent.lastActivityAt)+RETENTION_MS+1);expect(ops.getTask('a',parent.id).id).toBe(parent.id);
  vi.setSystemTime(Date.parse(refreshed.lastActivityAt)+RETENTION_MS);expect(()=>ops.getTask('a',parent.id)).toThrow();expect(()=>ops.getTask('a',subtask.id)).toThrow();
  expect(()=>ops.listTasks('a',{parentTaskId:parent.id})).toThrowError(expect.objectContaining({status:404}));
 });
 it('removes expired children before parents within each cleanup batch without creating orphans',()=>{
  const parent=task(),subtask=child(parent.id);vi.setSystemTime(Date.parse(subtask.lastActivityAt)+RETENTION_MS+1);
  for(let step=0;step<20;step++){
   const result=cleanupAgents(Date.now(),1);expect(Object.values(result).reduce((sum,count)=>sum+count,0)).toBeLessThanOrEqual(1);
   const orphan=getDb().prepare('SELECT COUNT(*) AS count FROM main.tb_agent_task c LEFT JOIN main.tb_agent_task p ON p.uid_task=c.uid_parent_task AND p.uid_user=c.uid_user WHERE c.uid_parent_task IS NOT NULL AND p.uid_task IS NULL').get();expect(orphan).toEqual({count:0});
   if(Object.values(result).every(count=>count===0))break;
  }
  expect(getDb().prepare('SELECT COUNT(*) AS count FROM main.tb_agent_task').get()).toEqual({count:0});
 });
 it('keeps an expired parent stored until its live child is removed, without exposing the expired parent',()=>{
  const parent=task(),subtask=child(parent.id),old=new Date(Date.now()-RETENTION_MS-1).toISOString();
  getDb().prepare('UPDATE main.tb_agent_task SET tsz_update=? WHERE uid_task=?').run(old,parent.id);
  expect(()=>ops.getTask('a',parent.id)).toThrow();cleanupAgents();
  expect(getDb().prepare('SELECT uid_parent_task AS parent FROM main.tb_agent_task WHERE uid_task=?').get(subtask.id)).toEqual({parent:parent.id});
  expect(getDb().prepare('SELECT COUNT(*) AS count FROM main.tb_agent_task WHERE uid_task=?').get(parent.id)).toEqual({count:1});
 });
 it('uses the parent lookup index without a temporary sort at retained production volume',()=>{
  const parent=task(),db=getDb(),at=new Date().toISOString();
  const insert=db.prepare("INSERT INTO main.tb_agent_task(uid_task,uid_user,uid_parent_task,ref_external,nam_title,txt_description,typ_status,num_version,tsz_insert,tsz_update) VALUES(?,?,?,?,'Synthetic child','','queued',1,?,?)");
  db.transaction(()=>{for(let index=0;index<10000;index++)insert.run(`child-${String(index).padStart(5,'0')}`,'a',parent.id,`external-${index}`,at,at);})();
  const plan=db.prepare('EXPLAIN QUERY PLAN SELECT uid_task FROM main.tb_agent_task WHERE uid_user=? AND uid_parent_task=? AND tsz_update>? ORDER BY tsz_update DESC,uid_task DESC LIMIT ?').all('a',parent.id,new Date(Date.now()-RETENTION_MS).toISOString(),100) as {detail:string}[];
  expect(plan.some(row=>row.detail.includes('tb_agent_task_ix5'))).toBe(true);expect(plan.some(row=>row.detail.includes('TEMP B-TREE'))).toBe(false);
  expect(ops.listTasks('a',{parentTaskId:parent.id,limit:100}).items).toHaveLength(100);
  const foreignKeyLookup=db.prepare('EXPLAIN QUERY PLAN SELECT uid_task FROM main.tb_agent_task WHERE uid_parent_task=? LIMIT 1').all(parent.id) as {detail:string}[];
  expect(foreignKeyLookup.some(row=>row.detail.includes('SEARCH')&&row.detail.includes('tb_agent_task_ix5'))).toBe(true);
  expect(foreignKeyLookup.some(row=>row.detail.includes('SCAN'))).toBe(false);
 });
});

it('deletes a live parent with expired children without deleting their pending cleanup history or resurrecting a replayed create',()=>{
 const parent=task(),input={externalId:'expired-child',title:'Expired child',parentTaskId:parent.id},creation=mutation();
 const subtask=ops.createTask('a',input,creation);
 ops.reportActivity('a',subtask.id,{kind:'progress',summary:'Retained until bounded cleanup'},mutation());
 const childAt=ops.getTask('a',subtask.id).lastActivityAt;
 const history=getDb().prepare('SELECT COUNT(*) AS count FROM main.tb_agent_activity WHERE uid_task=?').get(subtask.id);
 const receipts=getDb().prepare('SELECT COUNT(*) AS count FROM main.tb_mutation_receipt WHERE ref_resource=?').get(subtask.id);
 expect(history).toEqual({count:2});expect(receipts).toEqual({count:2});
 vi.setSystemTime(Date.parse(childAt)+RETENTION_MS-1000);
 ops.updateTask('a',parent.id,{expectedVersion:1,title:'Parent still active'},mutation());
 vi.setSystemTime(Date.parse(childAt)+RETENTION_MS+1);
 expect(ops.listTasks('a',{parentTaskId:parent.id}).items).toEqual([]);
 expect(()=>ops.deleteTask('a',subtask.id,mutation())).toThrowError(expect.objectContaining({status:404}));
 const childBefore=getDb().prepare('SELECT tsz_update AS updated FROM main.tb_agent_task WHERE uid_task=?').get(subtask.id);
 expect(()=>ops.deleteTask('a',parent.id,mutation())).not.toThrow();
 expect(getDb().prepare('SELECT uid_parent_task AS parent,tsz_update AS updated FROM main.tb_agent_task WHERE uid_task=?').get(subtask.id)).toEqual({parent:null,...childBefore as {updated:string}});
 expect(getDb().prepare('SELECT COUNT(*) AS count FROM main.tb_agent_activity WHERE uid_task=?').get(subtask.id)).toEqual(history);
 expect(getDb().prepare('SELECT COUNT(*) AS count FROM main.tb_mutation_receipt WHERE ref_resource=?').get(subtask.id)).toEqual(receipts);
 expect(()=>ops.createTask('a',input,{...creation,requestedAt:new Date().toISOString()})).toThrowError(expect.objectContaining({status:409,code:'receipt_expired'}));
 expect(()=>ops.createTask('a',input,mutation())).toThrowError(expect.objectContaining({status:404,code:'not_found'}));
 expect(ops.listTasks('a').items).toEqual([]);
});

it('replaces an expired parent external identity even while its expired children await cleanup',()=>{
 const parent=task('a',{externalId:'replaceable-parent'}),subtask=child(parent.id);
 ops.reportActivity('a',subtask.id,{kind:'progress',summary:'Expired work history'},mutation());
 const childAt=ops.getTask('a',subtask.id).lastActivityAt;
 const history=getDb().prepare('SELECT COUNT(*) AS count FROM main.tb_agent_activity WHERE uid_task=?').get(subtask.id);
 vi.setSystemTime(Date.parse(childAt)+RETENTION_MS+1);
 const replacement=task('a',{externalId:parent.externalId,title:'New parent'});
 expect(replacement.id).not.toBe(parent.id);expect(replacement.parentTaskId).toBeNull();expect(replacement.version).toBe(1);
 expect(getDb().prepare('SELECT uid_parent_task AS parent,tsz_update AS updated FROM main.tb_agent_task WHERE uid_task=?').get(subtask.id)).toEqual({parent:null,updated:childAt});
 expect(getDb().prepare('SELECT COUNT(*) AS count FROM main.tb_agent_activity WHERE uid_task=?').get(subtask.id)).toEqual(history);
 expect(()=>ops.getTask('a',subtask.id)).toThrowError(expect.objectContaining({status:404}));
 expect(ops.listTasks('a',{scope:'roots'}).items.map(item=>item.id)).toEqual([replacement.id]);
});

it('preserves child content and activity when a version 16 writer deletes its parent with foreign keys enabled',()=>{
 const parent=task(),subtask=child(parent.id),db=getDb();
 expect(db.pragma('foreign_keys',{simple:true})).toBe(1);
 const before=db.prepare('SELECT nam_title AS title,txt_description AS description,tsz_insert AS created,tsz_update AS updated,num_version AS version FROM main.tb_agent_task WHERE uid_task=?').get(subtask.id);
 expect(()=>db.prepare('DELETE FROM main.tb_agent_task WHERE uid_user=? AND uid_task=?').run('a',parent.id)).not.toThrow();
 const after=db.prepare('SELECT nam_title AS title,txt_description AS description,tsz_insert AS created,tsz_update AS updated,num_version AS version,uid_parent_task AS parent FROM main.tb_agent_task WHERE uid_task=?').get(subtask.id);
 expect(after).toEqual({...before as Record<string,unknown>,parent:null});
 expect(ops.getTask('a',subtask.id).parentTaskId).toBeNull();
 expect(ops.listTasks('a',{scope:'roots'}).items.map(item=>item.id)).toEqual([subtask.id]);
});

it('permits version 16 cleanup to delete an expired parent first without extending its expired child retention',()=>{
 const parent=task(),subtask=child(parent.id),db=getDb();
 const childAt=ops.getTask('a',subtask.id).lastActivityAt;
 vi.setSystemTime(Date.parse(childAt)+RETENTION_MS+1);
 const before=db.prepare('SELECT nam_title AS title,tsz_insert AS created,tsz_update AS updated,num_version AS version FROM main.tb_agent_task WHERE uid_task=?').get(subtask.id);
 const oldCutoff=new Date(Date.now()-RETENTION_MS).toISOString();
 expect(()=>db.prepare('DELETE FROM main.tb_agent_task WHERE uid_task IN (SELECT uid_task FROM main.tb_agent_task WHERE uid_user=? AND uid_task=? AND tsz_update<=? LIMIT 1)').run('a',parent.id,oldCutoff)).not.toThrow();
 expect(db.prepare('SELECT nam_title AS title,tsz_insert AS created,tsz_update AS updated,num_version AS version,uid_parent_task AS parent FROM main.tb_agent_task WHERE uid_task=?').get(subtask.id)).toEqual({...before as Record<string,unknown>,parent:null});
 expect(()=>ops.getTask('a',subtask.id)).toThrowError(expect.objectContaining({status:404}));
 expect(ops.listTasks('a').items).toEqual([]);
});

describe('agent subtask progress summary',()=>{
 it('counts children per root and lists only the latest active ones for the owner',()=>{
  vi.useFakeTimers();
  const parent=task(),empty=task(),foreign=task('b');
  const done=child(parent.id,{title:'Done step'});advance();
  ops.transitionTask('a',done.id,{status:'working',expectedVersion:1},mutation());advance();
  ops.transitionTask('a',done.id,{status:'completed',expectedVersion:2},mutation());advance();
  const steps=Array.from({length:4},(_,index)=>{advance();return child(parent.id,{title:`Step ${index}`});});
  advance();ops.transitionTask('a',steps[0].id,{status:'working',expectedVersion:1},mutation());
  task('b',{parentTaskId:foreign.id});
  const summary=ops.summarizeSubtasks('a',[parent.id,empty.id,foreign.id]);
  expect(Object.keys(summary)).toEqual([parent.id]);
  expect(summary[parent.id]).toMatchObject({total:5,completed:1});
  expect(summary[parent.id].active.map(item=>item.title)).toEqual(['Step 0','Step 3','Step 2']);
  expect(summary[parent.id].active[0].status).toBe('working');
  expect(ops.summarizeSubtasks('a',[])).toEqual({});
 });
});
