import {afterEach,beforeEach,describe,expect,it,vi} from 'vitest';
import {mkdtempSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {randomBytes} from 'node:crypto';
import {getDb} from '@/lib/db';
import {saveConnection} from '@/lib/vault/connections';
import {jiraOperations} from '@/lib/operations/jira';
import * as jira from '@/lib/integrations/jiraApi';
import * as github from '@/lib/integrations/githubApi';
import * as approvals from '@/lib/integrations/jira/approvals';
import * as startDates from '@/lib/integrations/jira/startDates';
import {jiraFollowedPeople,jiraWatchedKeys} from '@/lib/preferences';
import type {Principal} from '@/lib/access/principal';
import type {JiraDatedItem,PullRequestItem} from '@/lib/types';
import approvalFixture from '../../fixtures/jira-write/approvals-pending.json';
import commentFixture from '../../fixtures/jira-write/comments-resource.json';
import priorityFixture from '../../fixtures/jira-write/priorities.json';
import myselfFixture from '../../fixtures/jira-write/myself.json';
let dir:string,connectionId:string,githubId:string;
const p:Principal={userId:'owner',kind:'oauth',scopes:['jira:read','jira:write','github:read']};
const mutation=()=>({operationId:randomBytes(12).toString('hex'),requestedAt:new Date().toISOString()});
const run=(name:string,input:unknown)=>jiraOperations.find(op=>op.name===name)!.run(p,input);
beforeEach(()=>{dir=mkdtempSync(path.join(tmpdir(),'daily-jira-parity-'));vi.stubEnv('DAILY_WEB_DB_PATH',path.join(dir,'db'));vi.stubEnv('DAILY_WEB_SECRET_KEY',randomBytes(32).toString('base64'));getDb().prepare("INSERT INTO users(id,username,password_hash,is_admin,created_at) VALUES('owner','owner','unused',0,'2026-01-01')").run();connectionId=saveConnection('owner','jira','Jira',{cloud:'example.invalid',email:'test@example.invalid',token:randomBytes(12).toString('hex')});githubId=saveConnection('owner','pulls','GitHub',{token:randomBytes(12).toString('hex')});});
afterEach(()=>{vi.restoreAllMocks();vi.unstubAllEnvs();rmSync(dir,{recursive:true,force:true});});
describe('Jira operation parity',()=>{
 it('keeps bulk item receipt keys bounded for the longest accepted operation id',async()=>{
  const write=vi.spyOn(jira,'setStartDate').mockResolvedValue();
  const input={connectionId,operationId:'a'.repeat(160),requestedAt:new Date().toISOString(),items:[{key:'TT-1',date:'2020-01-01'},{key:'TT-123456789',date:'2020-01-01'}]};
  expect(await run('jira_start_apply',input)).toEqual({results:[{ok:true,id:'TT-1'},{ok:true,id:'TT-123456789'}]});
  await run('jira_start_apply',input);expect(write).toHaveBeenCalledTimes(2);
 });
 it('replays confirmed approval without consulting its now-changed state',async()=>{const captured=approvalFixture.decidedRequest.response.values[0];const pending=vi.spyOn(approvals,'fetchPendingApprovals').mockResolvedValueOnce([{id:captured.id,name:captured.name}]).mockResolvedValue([]);const answer=vi.spyOn(approvals,'answerApproval').mockResolvedValue();const input={connectionId,key:'PDS-2763',approvalId:captured.id,decision:'approve',...mutation()};expect(await run('jira_approval',input)).toEqual({ok:true});expect(await run('jira_approval',input)).toEqual({ok:true});expect(answer).toHaveBeenCalledTimes(1);expect(pending).toHaveBeenCalledTimes(1);});
 it('merges concurrent follows after provider lookups and replays without refetch',async()=>{let resolveFirst!:(p:{accountId:string;displayName:string})=>void;const lookup=vi.spyOn(jira,'fetchPerson').mockImplementation(async(_c,id)=>id==='first'?await new Promise(resolve=>{resolveFirst=resolve;}):{accountId:id,displayName:id});const first={connectionId,accountId:'first',action:'follow',...mutation()};const a=run('jira_people_follow',first);await run('jira_people_follow',{connectionId,accountId:'second',action:'follow',...mutation()});resolveFirst({accountId:'first',displayName:'First'});await a;expect(jiraFollowedPeople('owner').map(v=>v.accountId).sort()).toEqual(['first','second']);await run('jira_people_follow',first);expect(lookup).toHaveBeenCalledTimes(2);await expect(run('jira_people_follow',{...first,action:'unfollow'})).rejects.toMatchObject({code:'idempotency_conflict'});});
 it('persists watch retries and rejects key reuse with another action',async()=>{const fetch=vi.spyOn(jira,'fetchByKeys').mockResolvedValue([{key:'TT-1'}] as never);const input={connectionId,key:'TT-1',action:'watch',...mutation()};await run('jira_watch',input);await run('jira_watch',input);expect(fetch).toHaveBeenCalledTimes(1);expect(jiraWatchedKeys('owner')).toEqual(['TT-1']);await expect(run('jira_watch',{...input,action:'unwatch'})).rejects.toMatchObject({code:'idempotency_conflict'});});
 it('applies the panel today window and priority order',async()=>{const item=(key:string,today:boolean,rank:number):JiraDatedItem=>({key,summary:key,status:'Done',statusCategory:'done',project:'TT',url:'https://example.invalid/'+key,parent:null,role:'assignee',awaitingApproval:false,kind:'Story',subtask:false,hierarchyLevel:0,updatedAt:'2026-10-23T12:00:00Z',dueDate:'',priority:{name:'Priority',rank},flag:'none',today});vi.spyOn(jira,'fetchDelivered').mockResolvedValue([item('TT-1',false,1),item('TT-2',true,3),item('TT-3',true,2)]);vi.spyOn(jira,'fetchAncestors').mockResolvedValue([]);const result=await run('jira_work',{connectionId,view:'delivered',period:'today',order:'prioridade'}) as {items:JiraDatedItem[]};expect(result.items.map(v=>v.key)).toEqual(['TT-3','TT-2']);const week=await run('jira_work',{connectionId,view:'delivered',period:'week'}) as {items:JiraDatedItem[]};expect(week.items).toHaveLength(3);});
 it('includes only explicitly authorized GitHub sources and reports incompleteness',async()=>{vi.spyOn(jira,'fetchIssues').mockResolvedValue([]);vi.spyOn(jira,'fetchDelivered').mockResolvedValue([]);vi.spyOn(jira,'fetchApproved').mockResolvedValue([]);const pull={id:'1',repo:'acme/app',number:1,title:'Review blocker',url:'https://github.com/acme/app/pull/1',author:'me',draft:false,awaitingYou:false,mine:true,isPullRequest:true,updatedAt:new Date().toISOString(),createdAt:new Date().toISOString(),ci:'failing',review:'changes-requested',merge:'clean',reviewers:[],failedChecks:[],pendingReviewers:[],reviewRequestedAt:null,size:null,headRef:'feature',baseRef:'main',headSha:'a'.repeat(40)} satisfies PullRequestItem;const load=vi.spyOn(github,'fetchMyPulls').mockResolvedValue({items:[pull],total:1,truncated:true});const result=await run('jira_summary',{connectionId,period:'daily',githubConnectionIds:[githubId]}) as {text:string;complete:boolean;githubIncluded:boolean};expect(result.text).toContain('Review blocker');expect(result.complete).toBe(false);expect(result.githubIncluded).toBe(true);const omitted=await run('jira_summary',{connectionId,period:'daily'}) as {githubIncluded:boolean};expect(omitted.githubIncluded).toBe(false);expect(load).toHaveBeenCalledTimes(1);});
});

it('does not expose provider error text in start-date suggestions',async()=>{
 vi.spyOn(startDates,'suggestStartDates').mockResolvedValue([{status:'failed',key:'TT-1',error:'sensitive provider response'}]);
 const result=await run('jira_start_suggest',{connectionId,keys:['TT-1']});
 expect(result).toEqual({suggestions:[{status:'failed',key:'TT-1',error:'Jira could not suggest a start date'}]});
 expect(JSON.stringify(result)).not.toContain('sensitive');
});

const jiraInputs = () => [
 ['jira_work', {connectionId}],
 ['jira_transitions', {connectionId,key:'TT-1'}],
 ['jira_transition', {connectionId,key:'TT-1',transitionId:'1',...mutation()}],
 ['jira_approvals', {connectionId,key:'TT-1'}],
 ['jira_approval', {connectionId,key:'TT-1',approvalId:'1',decision:'approve',...mutation()}],
 ['jira_comment', {connectionId,key:'TT-1',text:'Comment',...mutation()}],
 ['jira_flag', {connectionId,key:'TT-1',action:'flag',reason:'Blocked',...mutation()}],
 ['jira_priorities', {connectionId,key:'TT-1'}],
 ['jira_edit', {connectionId,key:'TT-1',change:'assign-self',...mutation()}],
 ['jira_story_create', {connectionId,key:'TT-1',summary:'Story',...mutation()}],
 ['jira_epics', {connectionId,project:'TT'}],
 ['jira_parent', {connectionId,key:'TT-1',epicKey:'TT-2',...mutation()}],
 ['jira_start_suggest', {connectionId,keys:['TT-1']}],
 ['jira_start_apply', {connectionId,items:[{key:'TT-1',date:'2020-01-01'}],...mutation()}],
 ['jira_people', {connectionId}],
 ['jira_people_search', {connectionId,query:'Person'}],
 ['jira_people_follow', {connectionId,accountId:'person',action:'follow',...mutation()}],
 ['jira_watch', {connectionId,key:'TT-1',action:'watch',...mutation()}],
 ['jira_summary', {connectionId,period:'daily'}],
] as const;

describe('every Jira operation authorization and input boundary',()=>{
 for(const name of jiraOperations.map(operation=>operation.name)) {
  it(`${name}: denies missing scope, foreign connection and malformed input before provider access`,async()=>{
   const operation=jiraOperations.find(operation=>operation.name===name)!;
   const input=jiraInputs().find(([operation])=>operation===name)![1];
   await expect(operation.run({...p,scopes:[]},input)).rejects.toMatchObject({status:403,code:'insufficient_scope'});
   const foreign=saveConnection('other','jira','Other Jira',{cloud:'other.invalid',email:'test@example.invalid',token:randomBytes(12).toString('hex')});
   await expect(operation.run(p,{...input,connectionId:foreign})).rejects.toMatchObject({status:404});
   await expect(operation.run(p,{...input,unexpected:'field'})).rejects.toMatchObject({status:400,code:'invalid_input'});
   await expect(operation.run({...p,userId:'deleted'},input)).rejects.toMatchObject({status:401});
  });
 }
});

it('continues bulk dates after refusal and uncertainty, and never resubmits uncertain items',async()=>{
 const {ProviderRefusal}=await import('@/lib/integrations/refusal');
 const write=vi.spyOn(jira,'setStartDate').mockRejectedValueOnce(new ProviderRefusal('refused')).mockRejectedValueOnce(new Error('network interrupted')).mockResolvedValue();
 const input={connectionId,items:[{key:'TT-1',date:'2020-01-01'},{key:'TT-2',date:'2020-01-01'},{key:'TT-3',date:'2020-01-01'}],...mutation()};
 expect(await run('jira_start_apply',input)).toEqual({results:[{id:'TT-1',status:'refused',code:'state_changed'},{id:'TT-2',status:'uncertain',code:'uncertain_outcome'},{id:'TT-3',ok:true}]});
 const replay=await run('jira_start_apply',input) as {results:unknown[]};
 expect(replay.results[1]).toEqual({id:'TT-2',status:'uncertain',code:'uncertain_outcome'});
 expect(write).toHaveBeenCalledTimes(4);
});

it('persists flag partial outcome without exposing provider text or repeating a changed flag',async()=>{
 const {FlagCommentFailed}=await import('@/lib/integrations/jira/flag');
 const flags=await import('@/lib/integrations/jira/flag');
 const change=vi.spyOn(flags,'changeFlag').mockRejectedValue(new FlagCommentFailed('flag',new Error('private vendor body')));
 const input={connectionId,key:'TT-1',action:'flag',reason:'Blocking reason',...mutation()};
 for(let attempt=0;attempt<2;attempt++)await expect(run('jira_flag',input)).rejects.toMatchObject({code:'uncertain_outcome',cause:{outcome:{id:'TT-1',code:'flag_changed_comment_unconfirmed'}}});
 expect(change).toHaveBeenCalledTimes(1);
 const receipts=getDb().prepare('SELECT jsn_outcome AS outcome FROM main.tb_mutation_receipt').all();
 expect(JSON.stringify(receipts)).not.toContain('private');expect(JSON.stringify(receipts)).not.toContain('Blocking');
});

async function stubJiraProviders() {
 const transitions=await import('@/lib/integrations/jira/transitions');
 const comments=await import('@/lib/integrations/jira/comments');
 const flags=await import('@/lib/integrations/jira/flag');
 const edits=await import('@/lib/integrations/jira/edits');
 const fixture=await import('../../fixtures/jira-write/transitions-story.json');
 const raw=fixture.default as {transitions:unknown[]};
 const parsed=transitions.parseTransitions(raw,'unrelated-status');
 const mocks={
  jira_work:vi.spyOn(jira,'fetchIssues').mockResolvedValue([]),
  jira_transitions:vi.spyOn(transitions,'fetchTransitions').mockResolvedValue(parsed),
  jira_transition:vi.spyOn(transitions,'applyTransition').mockResolvedValue(),
  jira_approvals:vi.spyOn(approvals,'fetchPendingApprovals').mockResolvedValue([{id:'1',name:'Approval'}]),
  jira_approval:vi.spyOn(approvals,'answerApproval').mockResolvedValue(),
  jira_comment:vi.spyOn(comments,'addComment').mockResolvedValue({id:commentFixture.response.comments[0].id}),
  jira_flag:vi.spyOn(flags,'changeFlag').mockResolvedValue(),
  jira_priorities:vi.spyOn(edits,'fetchPriorityOptions').mockResolvedValue({priorities:priorityFixture.map(({id,name})=>({id,name})),current:null}),
  jira_edit:vi.spyOn(edits,'applyEdit').mockResolvedValue(),
  jira_story_create:vi.spyOn(edits,'createStoryInEpic').mockResolvedValue({key:'TT-2',url:'https://example.invalid/browse/TT-2'}),
  jira_epics:vi.spyOn(jira,'fetchOpenEpics').mockResolvedValue([]),
  jira_parent:vi.spyOn(jira,'setEpic').mockResolvedValue(),
  jira_start_suggest:vi.spyOn(startDates,'suggestStartDates').mockResolvedValue([{key:'TT-1',status:'suggested',date:'2020-01-01',basis:'started'}]),
  jira_start_apply:vi.spyOn(jira,'setStartDate').mockResolvedValue(),
  jira_people_search:vi.spyOn(jira,'searchPeople').mockResolvedValue([{accountId:'person',displayName:'Person'}]),
  jira_people_follow:vi.spyOn(jira,'fetchPerson').mockResolvedValue({accountId:myselfFixture.accountId,displayName:'Person'}),
  jira_watch:vi.spyOn(jira,'fetchByKeys').mockResolvedValue([{key:'TT-1'}] as never),
 };
 vi.spyOn(jira,'fetchAncestors').mockResolvedValue([]);
 vi.spyOn(jira,'fetchDelivered').mockResolvedValue([]);
 vi.spyOn(jira,'fetchApproved').mockResolvedValue([]);
 return mocks;
}

describe('direct Jira operation execution matrix',()=>{
 for(const name of jiraOperations.map(operation=>operation.name)) {
  it(`${name}: executes its valid input through the shared application boundary`,async()=>{
   await stubJiraProviders();
   const input=jiraInputs().find(([operation])=>operation===name)![1];
   const result=await run(name,input);
   expect(jiraOperations.find(operation=>operation.name===name)!.resultSchema.safeParse(result).success).toBe(true);
  });
 }
 for(const name of ['jira_work','jira_transitions','jira_transition','jira_approvals','jira_approval','jira_comment','jira_flag','jira_priorities','jira_edit','jira_story_create','jira_epics','jira_parent','jira_start_suggest','jira_people_search','jira_people_follow','jira_watch'] as const) {
  it(`${name}: fails visibly and safely when the provider fails`,async()=>{
   const mocks=await stubJiraProviders();
   mocks[name].mockRejectedValue(new Error('private provider details'));
   const input=jiraInputs().find(([operation])=>operation===name)![1];
   const externalWrite=['jira_transition','jira_approval','jira_comment','jira_flag','jira_edit','jira_story_create','jira_parent'].includes(name);
   await expect(run(name,input)).rejects.toMatchObject(externalWrite?{status:409,code:'uncertain_outcome'}:{status:502,code:'upstream_failed'});
   await run(name,input).catch(error=>expect(error.message).not.toContain('private'));
  });
 }
});

describe('Jira write refusal and replay matrix',()=>{
 for(const name of ['jira_transition','jira_approval','jira_comment','jira_flag','jira_edit','jira_story_create','jira_parent'] as const) {
  it(`${name}: records known refusal and permits a corrected retry without claiming success`,async()=>{
   const mocks=await stubJiraProviders();
   const {ProviderRefusal}=await import('@/lib/integrations/refusal');
   mocks[name].mockRejectedValueOnce(new ProviderRefusal('private refusal body'));
   const input=jiraInputs().find(([operation])=>operation===name)![1];
   await expect(run(name,input)).rejects.toMatchObject({status:409,code:'state_changed'});
   expect(await run(name,input)).toMatchObject({ok:true});
   await run(name,input);
   expect(mocks[name]).toHaveBeenCalledTimes(2);
  });
 }
 it('fails summary visibly if its Jira source cannot be read',async()=>{
  const mocks=await stubJiraProviders();mocks.jira_work.mockRejectedValue(new Error('private source details'));
  await expect(run('jira_summary',{connectionId,period:'daily'})).rejects.toMatchObject({status:502,code:'upstream_failed'});
 });
});

it('rejects unknown transition result enums instead of silently accepting provider drift',async()=>{
 const transitions=await import('@/lib/integrations/jira/transitions');
 vi.spyOn(transitions,'fetchTransitions').mockResolvedValue([{id:'1',name:'Changed',to:{name:'Changed',category:'future-category'},requires:'nothing'}] as never);
 await expect(run('jira_transitions',{connectionId,key:'TT-1'})).rejects.toMatchObject({status:502,code:'invalid_result'});
});
