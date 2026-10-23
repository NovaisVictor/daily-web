import {afterEach,beforeEach,describe,it,expect,vi} from 'vitest';
import {mkdtempSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {randomBytes,randomUUID} from 'node:crypto';
import {getDb} from '@/lib/db';
import {saveConnection,findConnection} from '@/lib/vault/connections';
import {taskOperations} from '@/lib/operations/tasks';
import {connectionOperations} from '@/lib/operations/connections';
import {focusOperations} from '@/lib/operations/focus';
import * as mstodo from '@/lib/cli/mstodo';
import {parseTasks} from '@/lib/parsers/mstodo';
import * as jira from '@/lib/integrations/jiraApi';
import * as github from '@/lib/integrations/githubApi';
import * as calendar from '@/lib/integrations/google/calendar';
import {CALENDAR_EVENTS_SCOPE} from '@/lib/integrations/google/oauth';
import type {Principal} from '@/lib/access/principal';
import taskFixture from '../../fixtures/mstodo-tasks.json';
const p:Principal={userId:'owner',kind:'oauth',scopes:['tasks:read','tasks:write','connections:read','connections:write','agenda:focus','jira:read','github:read']};
let directory:string,connectionId:string,agendaId:string,jiraId:string;
const mutation=()=>({operationId:randomUUID(),requestedAt:new Date().toISOString()});
const all=[...taskOperations,...connectionOperations,...focusOperations];
const run=(name:string,input:unknown,principal=p)=>all.find(op=>op.name===name)!.run(principal,input);
beforeEach(()=>{
 directory=mkdtempSync(path.join(tmpdir(),'daily-personal-parity-'));
 vi.stubEnv('DAILY_WEB_DB_PATH',path.join(directory,'db'));vi.stubEnv('DAILY_WEB_SECRET_KEY',randomBytes(32).toString('base64'));vi.stubEnv('PUBLIC_ORIGIN','https://daily.example');
 for(const id of ['owner','other'])getDb().prepare('INSERT INTO users(id,username,password_hash,is_admin,created_at) VALUES(?,?,?,?,?)').run(id,id,'unused',0,new Date().toISOString());
 connectionId=saveConnection('owner','tasks','Microsoft',{provider:'mstodo',clientId:'application',list:'Inbox'});
 agendaId=saveConnection('owner','agenda','Calendar',{provider:'google',refreshToken:randomBytes(12).toString('hex'),scope:CALENDAR_EVENTS_SCOPE});
 jiraId=saveConnection('owner','jira','Jira',{cloud:'example',email:'fixture@example.invalid',token:randomBytes(12).toString('hex')});
 vi.spyOn(mstodo,'fetchTasks').mockResolvedValue(parseTasks(JSON.stringify(taskFixture)));
});
afterEach(()=>{vi.restoreAllMocks();vi.unstubAllEnvs();rmSync(directory,{recursive:true,force:true});});
describe('personal task operation parity',()=>{
 it('reads captured provider tasks with filters, pagination and details',async()=>{
  const result=await run('tasks_list',{provider:'mstodo',connectionId,priority:'high',limit:1}) as {items:{id:string}[]};
  expect(result.items.map(item=>item.id)).toEqual(['T1']);
  expect(await run('tasks_get',{provider:'mstodo',connectionId,id:'T1'})).toMatchObject({task:{id:'T1',subtasks:[{id:'S1'},{id:'S2'}]}});
 });
 it('executes all local writes and subtask variants without crossing owners',async()=>{
  const task=await run('tasks_create',{provider:'local',title:'Parent',...mutation()}) as {id:string};
  const input={provider:'local',id:task.id};
  await run('tasks_edit',{...input,title:'Edited',due:'2030-01-01',time:'12:00',priority:'high',...mutation()});
  for(const status of ['doing','done','todo'])await run('tasks_transition',{...input,status,...mutation()});
  await run('tasks_subtask_create',{...input,title:'Child',...mutation()});
  const value=await run('tasks_get',input) as {task:{subtasks:{id:string}[]}};
  const itemId=value.task.subtasks[0].id;
  for(const action of ['edit','complete','reopen','delete'])await run('tasks_subtask_edit',{...input,itemId,action,title:'Edited child',...mutation()});
  await expect(run('tasks_get',input,{...p,userId:'other'})).rejects.toMatchObject({status:404});
  const remove={...input,...mutation()};await run('tasks_delete',remove);await run('tasks_delete',remove);
  await expect(run('tasks_get',input)).rejects.toMatchObject({status:404});
 });
 for(const [name,method,values] of [
  ['tasks_create','addTask',{title:'Created'}],['tasks_edit','editTask',{id:'T1',title:'Edited'}],
  ['tasks_transition','completeTask',{id:'T1',status:'done'}],['tasks_delete','deleteTask',{id:'T1'}],
  ['tasks_subtask_create','addSubtask',{id:'T1',title:'Created child'}],['tasks_subtask_edit','deleteSubtask',{id:'T1',itemId:'S1',action:'delete'}],
 ] as const){
  it(`executes ${name} once against its selected provider and replays`,async()=>{
   const call=vi.spyOn(mstodo,method).mockResolvedValue('created' as never);
   const input={provider:'mstodo',connectionId,...values,...mutation()};
   await run(name,input);await run(name,input);expect(call).toHaveBeenCalledTimes(1);
  });
  it(`fails safely on uncertain ${name} and does not retry`,async()=>{
   const call=vi.spyOn(mstodo,method).mockRejectedValue(new Error('sensitive provider response'));
   const input={provider:'mstodo',connectionId,...values,...mutation()};
   for(let attempt=0;attempt<2;attempt++)await expect(run(name,input)).rejects.toMatchObject({code:'uncertain_outcome'});
   expect(call).toHaveBeenCalledTimes(1);
  });
 }
 for(const action of ['edit','complete','reopen'] as const){
  it(`executes remote subtask ${action} and preserves replay`,async()=>{
   const call=action==='edit'?vi.spyOn(mstodo,'editSubtask').mockResolvedValue(undefined):vi.spyOn(mstodo,'checkSubtask').mockResolvedValue(undefined);
   const input={provider:'mstodo',connectionId,id:'T1',itemId:'S1',action,...(action==='edit'?{title:'Renamed'}:{}),...mutation()};
   await run('tasks_subtask_edit',input);await run('tasks_subtask_edit',input);expect(call).toHaveBeenCalledTimes(1);
  });
 }
 it('reopens a remote task and moves its board status without repeating provider effects',async()=>{
  vi.mocked(mstodo.fetchTasks).mockResolvedValue([{...parseTasks(JSON.stringify(taskFixture))[0],completed:true}]);
  const reopen=vi.spyOn(mstodo,'reopenTask').mockResolvedValue(undefined);
  const input={provider:'mstodo',connectionId,id:'T1',status:'doing',...mutation()};
  await run('tasks_transition',input);await run('tasks_transition',input);expect(reopen).toHaveBeenCalledTimes(1);
 });
 it('enforces source ownership before touching the provider',async()=>{
  const read=vi.mocked(mstodo.fetchTasks);
  await expect(run('tasks_get',{provider:'mstodo',connectionId,id:'T1'},{...p,userId:'other'})).rejects.toMatchObject({status:404});
  expect(read).not.toHaveBeenCalled();
 });
 it('surfaces invalid provider output and read failures',async()=>{
  vi.mocked(mstodo.fetchTasks).mockRejectedValueOnce(new Error('sensitive'));
  await expect(run('tasks_list',{provider:'mstodo',connectionId})).rejects.toMatchObject({code:'upstream_failed'});
  vi.mocked(mstodo.fetchTasks).mockResolvedValueOnce([{...parseTasks(JSON.stringify(taskFixture))[0],priority:'unknown'}] as never);
  await expect(run('tasks_get',{provider:'mstodo',connectionId,id:'T1'})).rejects.toMatchObject({code:'invalid_result'});
 });
});
describe('connection and focus operation parity',()=>{
 it('provides secure setup, validates edits, tests and removes owned connections',async()=>{
  const test=vi.spyOn(jira,'testConnection').mockResolvedValue('Connected' as never);
  expect(await run('connections_setup',{module:'jira'})).toMatchObject({url:'https://daily.example/config?module=jira'});
  await run('connections_update',{connectionId:jiraId,label:'Renamed',values:{email:'new@example.invalid'}});
  expect(findConnection('owner',jiraId)?.label).toBe('Renamed');
  expect(await run('connections_test',{connectionId:jiraId})).toEqual({ok:true});expect(test).toHaveBeenCalledTimes(1);
  expect(await run('connections_test',{connectionId})).toMatchObject({state:'not_applicable'});
  await run('connections_remove',{connectionId:jiraId});expect(findConnection('owner',jiraId)).toBeNull();
 });
 it('never exposes foreign metadata or tests a foreign connection',async()=>{
  const test=vi.spyOn(jira,'testConnection');
  expect(await run('connections_list',{}, {...p,userId:'other'})).not.toEqual(await run('connections_list',{}));
  for(const name of ['connections_test','connections_remove','connections_update'])await expect(run(name,{connectionId:jiraId,...(name==='connections_update'?{label:'Foreign'}:{})}, {...p,userId:'other'})).rejects.toMatchObject({status:404});
  expect(test).not.toHaveBeenCalled();
 });
 it('sanitizes provider test errors',async()=>{
  vi.spyOn(jira,'testConnection').mockRejectedValue(new Error('provider token content'));
  await expect(run('connections_test',{connectionId:jiraId})).rejects.toMatchObject({code:'upstream_failed',message:'The provider operation failed; no success was confirmed'});
 });
 it('creates focus only for authorized sources and replays without duplicating the event',async()=>{
  const task=await run('tasks_create',{provider:'local',title:'Focus work',...mutation()}) as {id:string};
  const create=vi.spyOn(calendar,'createFocusBlock').mockResolvedValue({} as never);
  expect(await run('focus_targets',{})).toMatchObject({targets:[{id:agendaId}]});
  const input={connectionId:agendaId,kind:'task',taskProvider:'local',ref:task.id,start:new Date(Date.now()+60000).toISOString(),minutes:25,...mutation()};
  expect(await run('focus_create',input)).toEqual({ok:true});expect(await run('focus_create',input)).toEqual({ok:true});expect(create).toHaveBeenCalledTimes(1);
  await expect(run('focus_create',{...input,...mutation()}, {...p,scopes:['agenda:focus']})).rejects.toMatchObject({status:403});
 });
 it('denies foreign focus targets before provider calls and preserves uncertain outcomes',async()=>{
  const create=vi.spyOn(calendar,'createFocusBlock').mockRejectedValue(new Error('sensitive'));
  const task=await run('tasks_create',{provider:'local',title:'Focus work',...mutation()}) as {id:string};
  const input={connectionId:agendaId,kind:'task',taskProvider:'local',ref:task.id,start:new Date(Date.now()+60000).toISOString(),minutes:25,...mutation()};
  await expect(run('focus_create',input,{...p,userId:'other'})).rejects.toMatchObject({status:404});expect(create).not.toHaveBeenCalled();
  for(let attempt=0;attempt<2;attempt++)await expect(run('focus_create',input)).rejects.toMatchObject({code:'uncertain_outcome'});
  expect(create).toHaveBeenCalledTimes(1);
 });
 it('creates focus from authorized Jira and GitHub sources and lists only writable targets',async()=>{
  const create=vi.spyOn(calendar,'createFocusBlock').mockResolvedValue({} as never);
  vi.spyOn(jira,'fetchByKeys').mockResolvedValue([{key:'DEV-1',summary:'Selected issue'}] as never);
  vi.spyOn(github,'githubRequest').mockResolvedValue({title:'Selected pull'});
  vi.spyOn(github,'githubToken').mockReturnValue('disposable-fixture-value');
  const pullsId=saveConnection('owner','pulls','GitHub',{token:randomBytes(12).toString('hex')});
  expect(await run('focus_targets',{})).toEqual({targets:[{id:agendaId,label:'Calendar'}]});
  for(const [kind,ref,sourceConnectionId] of [['jira','DEV-1',jiraId],['pull','acme/app#1',pullsId]]){
   await run('focus_create',{connectionId:agendaId,kind,ref,sourceConnectionId,start:new Date(Date.now()+60000).toISOString(),minutes:25,...mutation()});
  }
  expect(create).toHaveBeenCalledTimes(2);
 });

});
