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
