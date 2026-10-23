import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { randomBytes } from 'node:crypto';
import { getDb } from '@/lib/db';
import { saveConnection, setModuleEnabled, findConnection } from '@/lib/vault/connections';
import { integrationOperations } from '@/lib/mcp/tools/integrations';
import type { Principal } from '@/lib/access/principal';
import * as github from '@/lib/integrations/githubApi';
import * as actions from '@/lib/integrations/github/actions';
import * as jira from '@/lib/integrations/jiraApi';
import * as edits from '@/lib/integrations/jira/edits';
import * as transitions from '@/lib/integrations/jira/transitions';
import { ProviderRefusal } from '@/lib/integrations/refusal';
import { listTasks } from '@/lib/tasks/local';

let dir:string;
let githubId:string;
let jiraId:string;
const scopes=['github:read','github:write','jira:read','jira:write','tasks:read','tasks:write','connections:read','connections:write','agenda:focus'];
const owner:Principal={userId:'owner',scopes,kind:'oauth'};
const other:Principal={userId:'other',scopes,kind:'oauth'};
const denied:Principal={...owner,scopes:[]};
const run=(name:string,p:Principal,input:unknown)=>integrationOperations.find(op=>op.name===name)!.run(p,input);
const mutation=()=>({operationId:randomBytes(12).toString('hex'),requestedAt:new Date().toISOString()});
beforeEach(()=>{
 dir=mkdtempSync(path.join(tmpdir(),'daily-ops-'));vi.stubEnv('DAILY_WEB_DB_PATH',path.join(dir,'db.sqlite'));vi.stubEnv('DAILY_WEB_SECRET_KEY',randomBytes(32).toString('base64'));
 const db=getDb();for(const id of ['owner','other'])db.prepare('INSERT INTO users(id,username,password_hash,is_admin,created_at) VALUES(?,?,?,?,?)').run(id,id,'unused',0,new Date().toISOString());
 githubId=saveConnection('owner','pulls','GitHub',{token:randomBytes(32).toString('hex'),repos:'acme/app'});
 jiraId=saveConnection('owner','jira','Jira',{cloud:'example.invalid',email:'test@example.invalid',token:randomBytes(32).toString('hex')});
});
afterEach(()=>{vi.restoreAllMocks();vi.unstubAllEnvs();rmSync(dir,{recursive:true,force:true});});
describe('MCP integration boundaries',()=>{
 it('classifies stale reruns and Jira edit/story refusals as not submitted',async()=>{
  vi.spyOn(actions,'rerunFailedRuns').mockRejectedValue(new actions.PullStateRefusal('head changed'));
  vi.spyOn(edits,'applyEdit').mockRejectedValue(new edits.InvalidEdit('unknown priority'));
  vi.spyOn(edits,'createStoryInEpic').mockRejectedValueOnce(new edits.InvalidEdit('not an epic')).mockRejectedValueOnce(new edits.StoryTypeUnavailable('no story type'));
  const cases=[
   ['github_rerun',{connectionId:githubId,owner:'acme',repo:'app',number:1,headSha:'a'.repeat(40)}],
   ['jira_edit',{connectionId:jiraId,key:'TT-1',change:'priority',priorityId:'1'}],
   ['jira_story_create',{connectionId:jiraId,key:'TT-1',summary:'Story'}],
   ['jira_story_create',{connectionId:jiraId,key:'TT-1',summary:'Unsupported story type'}],
  ] as const;
  for(const [name,input] of cases){
   const request={...input,...mutation()};
   await expect(run(name,owner,request)).rejects.toMatchObject({status:409,code:'state_changed'});
   expect(getDb().prepare('SELECT typ_state AS state FROM main.tb_mutation_receipt WHERE ref_key=?').get(request.operationId)).toEqual({state:'not_submitted'});
  }
 });
 it('keeps deterministic parent and missing start-field refusals retryable without marking them uncertain',async()=>{
  vi.spyOn(jira,'setEpic').mockRejectedValue(new ProviderRefusal('not an epic or wrong project'));
  vi.spyOn(jira,'setStartDate').mockRejectedValue(new ProviderRefusal('Start date field unavailable'));
  for(const [name,values] of [
   ['jira_parent',{connectionId:jiraId,key:'TT-1',epicKey:'OTHER-2'}],
   ['jira_start_apply',{connectionId:jiraId,items:[{key:'TT-1',date:'2020-01-01'}]}],
  ] as const){
   const input={...values,...mutation()};
   await expect(run(name,owner,input)).rejects.toMatchObject({status:409,code:'state_changed'});
   await expect(run(name,owner,input)).rejects.toMatchObject({status:409,code:'state_changed'});
  }
  const rows=getDb().prepare('SELECT typ_state AS state FROM main.tb_mutation_receipt').all();
  expect(rows).toEqual([{state:'not_submitted'},{state:'not_submitted'}]);
 });
 it('classifies a Jira sync transition that disappears before submission as not submitted',async()=>{
  vi.spyOn(transitions,'fetchTransitions').mockResolvedValue([{id:'7',name:'Code Review',to:{name:'Code Review',category:'indeterminate'},requires:'nothing'}]);
  vi.spyOn(transitions,'applyTransition').mockRejectedValue(new transitions.TransitionUnavailable());
  const input={...mutation(),connectionId:githubId,jiraConnectionId:jiraId,key:'TT-1',intent:'review',action:'apply',expectedTransitionId:'7'};
  await expect(run('github_jira_sync',owner,input)).rejects.toMatchObject({status:409,code:'state_changed'});
  expect(getDb().prepare('SELECT typ_state AS state FROM main.tb_mutation_receipt WHERE ref_key=?').get(input.operationId)).toEqual({state:'not_submitted'});
 });
 for(const op of integrationOperations){it(`denies missing scope before validating or calling ${op.name}`,async()=>{await expect(op.run(denied,{})).rejects.toMatchObject({status:403,code:'insufficient_scope'});});}
 it('denies removed users even with a formerly valid principal',async()=>{getDb().prepare('DELETE FROM users WHERE id=?').run('owner');await expect(run('connections_list',owner,{})).rejects.toMatchObject({status:401});});
 it('never falls back to another user or first connection',async()=>{const fetch=vi.spyOn(github,'fetchPulls');await expect(run('github_work',other,{connectionId:githubId})).rejects.toMatchObject({status:404});await expect(run('github_work',owner,{})).rejects.toMatchObject({status:400});await expect(run('github_work',owner,{connectionId:jiraId})).rejects.toMatchObject({status:404});expect(fetch).not.toHaveBeenCalled();});
 it('does not run a disabled module',async()=>{setModuleEnabled('owner','pulls',false);await expect(run('github_work',owner,{connectionId:githubId})).rejects.toMatchObject({code:'module_disabled'});});
 it('rejects credentials in tool input and returns metadata only',async()=>{const secret=findConnection('owner',githubId)!.values.token;await expect(run('connections_update',owner,{connectionId:githubId,label:'new',token:secret})).rejects.toMatchObject({status:400});const result=await run('connections_list',owner,{});expect(JSON.stringify(result)).not.toContain(secret);});
 it('updates declared non-secret settings while preserving credentials and rejecting hidden, foreign-module and secret fields',async()=>{
  const original=findConnection('owner',githubId)!;
  await run('connections_update',owner,{connectionId:githubId,values:{repos:'acme/second'}});
  expect(findConnection('owner',githubId)).toMatchObject({label:original.label,values:{repos:'acme/second',token:original.values.token}});
  for(const values of [{token:'forbidden'},{refreshToken:'forbidden'},{email:'other@example.invalid'}]){
   await expect(run('connections_update',owner,{connectionId:githubId,values})).rejects.toMatchObject({status:400});
  }
  await expect(run('connections_update',other,{connectionId:githubId,values:{repos:'acme/foreign'}})).rejects.toMatchObject({status:404});
  expect(findConnection('owner',githubId)!.values.repos).toBe('acme/second');
  await expect(run('connections_update',owner,{connectionId:jiraId,values:{cloud:'https://attacker.invalid'}})).rejects.toMatchObject({code:'browser_setup_required'});
  expect(findConnection('owner',jiraId)!.values.cloud).toBe('example.invalid');
 });
 it('toggles only the principal user module',async()=>{await run('connections_toggle',owner,{module:'jira',state:'disabled'});await expect(run('jira_work',owner,{connectionId:jiraId})).rejects.toMatchObject({code:'module_disabled'});});
 it('deduplicates a confirmed external comment and rejects changed input under the same key',async()=>{const call=vi.spyOn(actions,'addComment').mockResolvedValue({id:19,url:'https://github.com/acme/app/issues/1#issuecomment-19'});const input={...mutation(),connectionId:githubId,owner:'acme',repo:'app',number:1,body:'A comment'};expect(await run('github_comment',owner,input)).toEqual({ok:true,id:19});expect(await run('github_comment',owner,input)).toEqual({ok:true,id:19});expect(call).toHaveBeenCalledTimes(1);await expect(run('github_comment',owner,{...input,body:'changed'})).rejects.toMatchObject({status:409,code:'idempotency_conflict'});});
 it('does not retry an uncertain provider write or leak its sensitive error text',async()=>{const call=vi.spyOn(actions,'addComment').mockRejectedValue(new Error('sensitive upstream body'));const input={...mutation(),connectionId:githubId,owner:'acme',repo:'app',number:1,body:'hello'};await expect(run('github_comment',owner,input)).rejects.toMatchObject({code:'uncertain_outcome'});await expect(run('github_comment',owner,input)).rejects.toMatchObject({code:'uncertain_outcome'});expect(call).toHaveBeenCalledTimes(1);});
 it('preserves incomplete upstream GitHub results',async()=>{vi.spyOn(github,'fetchPulls').mockResolvedValue({items:[],errors:['one repository was unavailable'],truncated:[],defaultBranches:[]});await expect(run('github_work',owner,{connectionId:githubId})).resolves.toMatchObject({complete:false});});
 it('requires following a person before reading their Jira work',async()=>{const call=vi.spyOn(jira,'fetchIssues');await expect(run('jira_work',owner,{connectionId:jiraId,accountId:'abc-123'})).rejects.toMatchObject({code:'person_not_followed'});expect(call).not.toHaveBeenCalled();});
 it('keeps local personal tasks owner-scoped through creation and lifecycle',async()=>{const created=await run('tasks_create',owner,{provider:'local',...mutation(),title:'Review work'}) as {id:string};expect(listTasks('owner')).toHaveLength(1);expect(listTasks('other')).toHaveLength(0);await expect(run('tasks_get',other,{provider:'local',id:created.id})).rejects.toMatchObject({status:404});await run('tasks_transition',owner,{provider:'local',id:created.id,status:'done',...mutation()});expect(listTasks('owner')[0].completed).toBe(true);});
 it('returns a deterministic missing-resource error without reserving uncertain local work',async()=>{
  const input={provider:'local',id:'missing',title:'Edited',...mutation()};
  await expect(run('tasks_edit',owner,input)).rejects.toMatchObject({status:404,code:'not_found'});
  expect(getDb().prepare('SELECT typ_state FROM main.tb_mutation_receipt WHERE ref_key=?').get(input.operationId)).toBeUndefined();
 });
 it('requires an explicit Microsoft To Do connection',async()=>{await expect(run('tasks_list',owner,{provider:'mstodo'})).rejects.toMatchObject({code:'connection_required'});});
 it('rejects unsupported status or path traversal before side effects',async()=>{const call=vi.spyOn(actions,'mergePull');await expect(run('github_merge',owner,{...mutation(),connectionId:githubId,owner:'acme',repo:'..',number:1,method:'merge',headSha:'a'.repeat(40)})).rejects.toMatchObject({status:400});expect(call).not.toHaveBeenCalled();});
 it('rejects impossible task dates and times while preserving valid past dates',async()=>{
   const created=await run('tasks_create',owner,{provider:'local',...mutation(),title:'Dated work'}) as {id:string};
   await expect(run('tasks_edit',owner,{provider:'local',id:created.id,...mutation(),due:'2026-99-99'})).rejects.toMatchObject({status:400});
   await expect(run('tasks_edit',owner,{provider:'local',id:created.id,...mutation(),time:'99:99'})).rejects.toMatchObject({status:400});
   await run('tasks_edit',owner,{provider:'local',id:created.id,...mutation(),due:'2020-02-29'});
   expect(listTasks('owner')[0].due).toBe('2020-02-29');
 });
 it('replays a subtask deletion after the subtask no longer exists',async()=>{
   const created=await run('tasks_create',owner,{provider:'local',...mutation(),title:'Parent'}) as {id:string};
   await run('tasks_subtask_create',owner,{provider:'local',id:created.id,...mutation(),title:'Child'});
   const itemId=listTasks('owner')[0].subtasks[0].id;
   const input={provider:'local',id:created.id,itemId,action:'delete',...mutation()};
   await expect(run('tasks_subtask_edit',owner,input)).resolves.toEqual({ok:true});
   await expect(run('tasks_subtask_edit',owner,input)).resolves.toEqual({ok:true});
   expect(listTasks('owner')[0].subtasks).toHaveLength(0);
 });
 it('returns task due-window groups without inventing a due date',async()=>{
   await run('tasks_create',owner,{provider:'local',...mutation(),title:'No date'});
   const response=await run('tasks_list',owner,{provider:'local',dueWindow:'noDate',groupBy:'due'}) as {groups:{key:string}[]};
   expect(response.groups.map(g=>g.key)).toEqual(['noDate']);
 });
 it('rejects unrecognized provider enum values at the result boundary',async()=>{
   vi.spyOn(github,'fetchPulls').mockResolvedValue({items:[{id:'x',repo:'acme/app',number:1,title:'X',url:'https://example.invalid',author:'owner',draft:false,awaitingYou:false,mine:true,isPullRequest:true,updatedAt:'2026-01-01',createdAt:'2026-01-01',ci:'new-state',review:'none',merge:'unknown',reviewers:[]}],errors:[],truncated:[],defaultBranches:[]} as never);
   await expect(run('github_work',owner,{connectionId:githubId})).rejects.toMatchObject({status:502,code:'invalid_result'});
 });

});
