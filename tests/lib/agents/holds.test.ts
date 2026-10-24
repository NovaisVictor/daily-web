import {afterEach,beforeEach,describe,expect,it,vi} from 'vitest';
import {mkdtempSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {getDb} from '@/lib/db';
import * as ops from '@/lib/agents/operations';
import {holdReasons} from '@/lib/agents/model';
let directory:string,sequence=0;
const mutation=()=>({key:`hold-operation-${++sequence}`,requestedAt:new Date().toISOString()});
const task=()=>ops.createTask('a',{externalId:`hold-task-${++sequence}`,title:'Ship it'},mutation());
const move=(t:ops.AgentTask,status:ops.AgentTask['status'],hold?:unknown)=>ops.transitionTask('a',t.id,{status,expectedVersion:t.version,...(hold===undefined?{}:{hold})},mutation());
beforeEach(()=>{
 directory=mkdtempSync(path.join(tmpdir(),'daily-agent-holds-'));
 vi.stubEnv('DAILY_WEB_DB_PATH',path.join(directory,'db'));
 getDb().prepare('INSERT INTO users(id,username,password_hash,is_admin,created_at) VALUES(?,?,?,?,?)').run('a','a','unused',0,new Date().toISOString());
});
afterEach(()=>{vi.unstubAllEnvs();rmSync(directory,{recursive:true,force:true});});

describe('waiting status and hold reasons',()=>{
 it('moves working work to waiting with a reason and note, records it, and clears it on completion',()=>{
  const waiting=move(move(task(),'working'),'waiting',{reason:'pull_request',note:'PR #81'});
  expect(waiting).toMatchObject({status:'waiting',hold:{reason:'pull_request',note:'PR #81'}});
  expect(ops.getTask('a',waiting.id).hold).toEqual({reason:'pull_request',note:'PR #81'});
  expect(ops.listActivity('a',waiting.id).items.map(item=>item.summary)).toContain('waiting: pull_request — PR #81');
  const done=move(waiting,'completed');
  expect(done).toMatchObject({status:'completed',hold:null});
 });
 it('replaces the reason with a same-status transition and accepts every reason of each held status',()=>{
  let t=move(move(task(),'working'),'waiting',{reason:'pull_request'});
  t=move(t,'waiting',{reason:'deploy',note:'production'});
  expect(t.hold).toEqual({reason:'deploy',note:'production'});
  for(const status of ['waiting','blocked'] as const)for(const reason of holdReasons[status]){
   t=move(t,status,{reason,note:'detail'});
   expect(t).toMatchObject({status,hold:{reason,note:'detail'}});
  }
  expect(move(t,'working').hold).toBeNull();
 });
 it('keeps holds optional so existing blocked reports still work',()=>{
  expect(move(task(),'blocked')).toMatchObject({status:'blocked',hold:null});
 });
 it('rejects reasons of the other status, unknown reasons, holds on other statuses, notes without other text and long notes',()=>{
  const t=move(task(),'working');
  for(const [status,hold] of [['waiting',{reason:'decision'}],['blocked',{reason:'pull_request'}],['waiting',{reason:'surprise'}],['completed',{reason:'deploy'}],['waiting',{reason:'other'}],['waiting',{reason:'other',note:'  '}],['waiting',{reason:'build',note:'x'.repeat(141)}],['waiting',{reason:'build',extra:true}],['waiting','pull_request']] as const)
   expect(()=>move(t,status,hold)).toThrowError(expect.objectContaining({status:400}));
  expect(ops.getTask('a',t.id)).toMatchObject({status:'working',hold:null,version:t.version});
 });
 it('does not allow waiting before work started or self-transitions of statuses without holds',()=>{
  expect(()=>move(task(),'waiting',{reason:'build'})).toThrowError(expect.objectContaining({status:409}));
  const working=move(task(),'working');
  expect(()=>move(working,'working')).toThrowError(expect.objectContaining({status:409}));
 });
 it('filters by waiting and shows waiting children as active subtask progress',()=>{
  const parent=task();
  const child=ops.createTask('a',{externalId:`hold-child-${++sequence}`,title:'Await CI',parentTaskId:parent.id},mutation());
  move(move(child,'working'),'waiting',{reason:'build'});
  expect(ops.listTasks('a',{status:'waiting'}).items.map(item=>item.id)).toEqual([child.id]);
  expect(ops.summarizeSubtasks('a',[parent.id])[parent.id].active).toEqual([{id:child.id,title:'Await CI',status:'waiting'}]);
 });
});
