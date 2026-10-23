import { beforeEach,afterEach,describe,it,expect,vi } from 'vitest';
import { mkdtempSync,rmSync,existsSync,statSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import Database from 'better-sqlite3';
import { getDb } from '@/lib/db';
import * as ops from '@/lib/agents/operations';
import { cleanupAgents } from '@/lib/agents/retention';
import { RETENTION_MS } from '@/lib/agents/model';
import { logicalBackup,restoreBackup } from '@/lib/agents/backup';
import { createCredential } from '@/lib/access/credentials';
let dir:string;let seq=0;
const mutation=()=>({key:`operation-${++seq}`,requestedAt:new Date().toISOString()});
function task(externalId='task-1'){return ops.createTask('a',{externalId,title:'Work'},mutation());}
beforeEach(()=>{dir=mkdtempSync(path.join(tmpdir(),'daily-agents-'));process.env.DAILY_WEB_DB_PATH=path.join(dir,'source.db');const db=getDb();for(const id of ['a','b'])db.prepare('INSERT INTO users(id,username,password_hash,is_admin,created_at) VALUES(?,?,?,?,?)').run(id,id,'unused',1,new Date().toISOString());});
afterEach(()=>{vi.useRealTimers();rmSync(dir,{recursive:true,force:true});});
describe('agent persistence',()=>{
 it('isolates users, rejects unknown ownership and validates lifecycle versions',()=>{const t=task();expect(()=>ops.getTask('b',t.id)).toThrow('not found');expect(()=>ops.createTask('a',{externalId:'task-b',title:'X',owner:'b'} as never,mutation())).toThrow('forbidden');expect(()=>ops.transitionTask('a',t.id,{status:'completed',expectedVersion:1},mutation())).toThrow('not allowed');const work=ops.transitionTask('a',t.id,{status:'working',expectedVersion:1},mutation());expect(work.version).toBe(2);expect(()=>ops.updateTask('a',t.id,{expectedVersion:1,title:'wrong'},mutation())).toThrow('changed');expect(ops.getTask('a',t.id).title).toBe('Work');});
 it('deduplicates create and progress without extending retention or changing metadata version',()=>{const m=mutation(),input={externalId:'repeat',title:'Title'};const t=ops.createTask('a',input,m);const event=mutation();ops.reportActivity('a',t.id,{kind:'progress',summary:'Started'},event);const before=ops.getTask('a',t.id);vi.setSystemTime(Date.now()+1000);expect(ops.createTask('a',input,m).id).toBe(t.id);ops.reportActivity('a',t.id,{kind:'progress',summary:'Started'},event);expect(ops.getTask('a',t.id).lastActivityAt).toBe(before.lastActivityAt);expect(ops.getTask('a',t.id).version).toBe(1);expect(ops.listActivity('a',t.id).items).toHaveLength(2);expect(()=>ops.createTask('a',{...input,title:'Changed'},m)).toThrow('different request');});
 it('supports multiple tasks per session and separates heartbeat from task activity',()=>{const a=ops.registerAgent('a',{externalId:'agent',provider:'claude',displayName:'Claude'},mutation());const s=ops.createSession('a',{agentId:a.id,externalId:'session'},mutation());const t=ops.createTask('a',{externalId:'one',title:'One',assignment:{sessionId:s.id}},mutation());ops.createTask('a',{externalId:'two',title:'Two',assignment:{sessionId:s.id}},mutation());vi.setSystemTime(Date.now()+180000);ops.heartbeatSession('a',s.id,{},mutation());expect(ops.getTask('a',t.id).lastActivityAt).toBe(t.lastActivityAt);expect(ops.listTasks('a',{sessionId:s.id}).items).toHaveLength(2);expect(ops.getTask('a',t.id).assignment?.freshness).toBe('fresh');});
 it('enforces exact expiry and atomically replaces expired external identifiers',()=>{const t=task();vi.setSystemTime(Date.parse(t.lastActivityAt)+RETENTION_MS-1);expect(ops.getTask('a',t.id).id).toBe(t.id);vi.setSystemTime(Date.parse(t.lastActivityAt)+RETENTION_MS);expect(()=>ops.getTask('a',t.id)).toThrow('not found');expect(ops.listTasks('a').items).toHaveLength(0);const replacement=task();expect(replacement.id).not.toBe(t.id);expect(getDb().prepare('SELECT COUNT(*) AS count FROM main.tb_agent_activity WHERE uid_task=?').get(t.id)).toEqual({count:0});});
 it('expires event history under active tasks and preserves unresolved external receipts',()=>{const t=task();const old=new Date(Date.now()-RETENTION_MS).toISOString();getDb().prepare('UPDATE main.tb_agent_activity SET tsz_insert=?').run(old);getDb().prepare("INSERT INTO main.tb_mutation_receipt(uid_receipt,uid_user,nam_capability,ref_key,txt_digest,typ_class,typ_state,tsz_insert) VALUES('r','a','github.comment','key','digest','external','unknown',?)").run(old);cleanupAgents();expect(ops.listActivity('a',t.id).items).toHaveLength(0);expect(getDb().prepare("SELECT typ_state AS state FROM main.tb_mutation_receipt WHERE uid_receipt='r'").get()).toEqual({state:'unknown'});});
 it('supports stable cursor pagination and escaped text search',()=>{for(let i=0;i<5;i++)task(`task-${i}`);const first=ops.listTasks('a',{limit:2});const second=ops.listTasks('a',{limit:2,cursor:first.nextCursor!});expect(first.items.map(x=>x.id).some(id=>second.items.some(x=>x.id===id))).toBe(false);expect(ops.listTasks('a',{q:'%'}).items).toHaveLength(0);expect(()=>ops.listTasks('a',{cursor:'bad'})).toThrow('cursor');});
 it('replays deleted task outcomes and retains no deleted content',()=>{const t=task(),m=mutation();ops.deleteTask('a',t.id,m);expect(()=>ops.deleteTask('a',t.id,m)).not.toThrow();expect(getDb().prepare('SELECT COUNT(*) AS count FROM main.tb_agent_activity').get()).toEqual({count:0});expect(()=>ops.getTask('a',t.id)).toThrow();});
 it('omits agent work, revokes restored credentials and invalidates OAuth records',()=>{task();createCredential('a',{label:'key',scopes:['agents:read']});getDb().prepare("INSERT INTO main.tb_oauth_record(typ_kind,uid_record,jsn_payload,uid_user) VALUES('Grant','g','encrypted','a')").run();getDb().prepare("INSERT INTO tasks(id,user_id,title,position,created_at) VALUES('personal','a','Keep',1,?)").run(new Date().toISOString());const backup=path.join(dir,'backup.db'),restored=path.join(dir,'restored.db');logicalBackup(process.env.DAILY_WEB_DB_PATH!,backup);restoreBackup(backup,restored);const db=new Database(restored);expect(db.prepare('SELECT COUNT(*) AS count FROM tb_agent_task').get()).toEqual({count:0});expect(db.prepare('SELECT COUNT(*) AS count FROM tb_oauth_record').get()).toEqual({count:0});expect(db.prepare('SELECT typ_state AS state FROM tb_api_credential').get()).toEqual({state:'revoked'});expect(db.prepare('SELECT title FROM tasks').get()).toEqual({title:'Keep'});db.close();});
});
it('cleans new private tables when deleting an account',async()=>{
 const {removeUser}=await import('@/lib/auth/users');task();const a=ops.registerAgent('a',{externalId:'agent',provider:'gemini',displayName:'Gemini'},mutation());ops.createSession('a',{agentId:a.id,externalId:'session'},mutation());createCredential('a',{label:'key',scopes:['agents:read']});getDb().prepare("INSERT INTO main.tb_oauth_record(typ_kind,uid_record,jsn_payload,uid_user) VALUES('Grant','g','encrypted','a')").run();expect(removeUser('a')).toBe(true);for(const table of ['tb_agent','tb_agent_task','tb_agent_session','tb_agent_activity','tb_api_credential','tb_mutation_receipt','tb_oauth_record'])expect(getDb().prepare(`SELECT COUNT(*) AS count FROM main.${table} WHERE uid_user=?`).get('a')).toEqual({count:0});
});
it('uses indexed bounded reads for a realistic retained dataset',()=>{
 const db=getDb(),at=new Date().toISOString();const insert=db.prepare("INSERT INTO main.tb_agent_task(uid_task,uid_user,ref_external,nam_title,txt_description,typ_status,num_version,tsz_insert,tsz_update) VALUES(?,?,?,?,'','queued',1,?,?)");db.transaction(()=>{for(let i=0;i<10000;i++)insert.run('task-'+String(i).padStart(5,'0'),'a','ext-'+i,'Task '+i,at,at);})();
 const plan=db.prepare('EXPLAIN QUERY PLAN SELECT uid_task FROM main.tb_agent_task WHERE uid_user=? AND typ_status=? AND tsz_update>? ORDER BY tsz_update DESC,uid_task DESC LIMIT ?').all('a','queued',new Date(Date.now()-RETENTION_MS).toISOString(),100) as {detail:string}[];
 expect(plan.some(row=>row.detail.includes('tb_agent_task_ix2'))).toBe(true);expect(ops.listTasks('a',{status:'queued',limit:100}).items).toHaveLength(100);
});
it('bounds all cleanup rows even when one expired task has a large history',()=>{
 const t=task();const at=new Date().toISOString();
 const insert=getDb().prepare("INSERT INTO main.tb_agent_activity(uid_activity,uid_user,uid_task,typ_kind,txt_summary,tsz_insert) VALUES(?,?,?,'progress','Synthetic history',?)");
 getDb().transaction(()=>{for(let i=0;i<1200;i++)insert.run('event-'+i,'a',t.id,at);})();
 vi.setSystemTime(Date.parse(at)+RETENTION_MS+1);
 for(let i=0;i<20;i++){
  expect(()=>ops.getTask('a',t.id)).toThrow('not found');
  const counts=cleanupAgents(Date.now(),100);
  const deleted=Object.values(counts).reduce((sum,value)=>sum+value,0);
  expect(deleted).toBeLessThanOrEqual(100);
  if(deleted===0)break;
 }
 expect(getDb().prepare('SELECT COUNT(*) AS count FROM main.tb_agent_activity WHERE uid_task=?').get(t.id)).toEqual({count:0});
 expect(getDb().prepare('SELECT COUNT(*) AS count FROM main.tb_agent_task WHERE uid_task=?').get(t.id)).toEqual({count:0});
});
it('does not resurrect a deleted task by replaying its original create',()=>{
 const input={externalId:'deleted-create',title:'Do not resurrect'},m=mutation();
 const t=ops.createTask('a',input,m);const deletion=mutation();ops.deleteTask('a',t.id,deletion);
 expect(()=>ops.createTask('a',input,m)).toThrow('not found');
 expect(()=>ops.deleteTask('a',t.id,deletion)).not.toThrow();
 const receipt=getDb().prepare("SELECT typ_state AS state,jsn_outcome AS outcome FROM main.tb_mutation_receipt WHERE uid_user=? AND nam_capability='tasks.create' AND ref_key=?").get('a',m.key);
 expect(receipt).toEqual({state:'deleted',outcome:null});expect(ops.listTasks('a').items).toHaveLength(0);
});
it('enables secure deletion and reclaims the WAL after cleanup',()=>{
 expect(getDb().pragma('secure_delete',{simple:true})).toBe(1);
 expect(getDb().pragma('journal_size_limit',{simple:true})).toBe(0);
 const t=task();vi.setSystemTime(Date.parse(t.lastActivityAt)+RETENTION_MS+1);cleanupAgents();
 expect(getDb().prepare('SELECT COUNT(*) AS count FROM main.tb_agent_task WHERE uid_task=?').get(t.id)).toEqual({count:0});
 const wal=process.env.DAILY_WEB_DB_PATH!+'-wal';expect(existsSync(wal)?statSync(wal).size:0).toBe(0);
});
it('does not retain expired task bodies behind a recent no-op receipt',()=>{
 const t=task();vi.setSystemTime(Date.parse(t.lastActivityAt)+RETENTION_MS-86400000);
 ops.updateTask('a',t.id,{expectedVersion:1,title:t.title},mutation());
 vi.setSystemTime(Date.parse(t.lastActivityAt)+RETENTION_MS+1);cleanupAgents();
 expect(getDb().prepare('SELECT COUNT(*) AS count FROM main.tb_agent_task WHERE uid_task=?').get(t.id)).toEqual({count:0});
});
