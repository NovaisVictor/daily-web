// @vitest-environment node
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { randomBytes, randomUUID } from 'node:crypto';
import { createUser } from '@/lib/auth/users';
import { saveConnection, setModuleEnabled } from '@/lib/vault/connections';
import { githubOperations, runGithubOperation } from '@/lib/operations/github';
import type { Principal } from '@/lib/access/principal';
import * as github from '@/lib/integrations/githubApi';
import { jiraActions } from '@/lib/operations/jira';
import * as transitionProvider from '@/lib/integrations/jira/transitions';
import { parseTransitions, TransitionUnavailable } from '@/lib/integrations/jira/transitions';
import captured from '@/tests/fixtures/github/operation-contracts.json';
import reviewCapture from '@/tests/fixtures/github/pull-reviews.json';
import reposCapture from '@/tests/fixtures/github/graphql-repos.json';
import runsCapture from '@/tests/fixtures/github/actions-runs.json';
import transitionCapture from '@/tests/fixtures/jira-write/transitions-story.json';

const scopes=['github:read','github:write','jira:read','jira:write'];
const ref={owner:'acme',repo:'repo-4',number:42};
const sha=captured.pull.head.sha;
const approved=reviewCapture.find(item=>item.state==='APPROVED')!;
const transition=parseTransitions(transitionCapture,'10175').find(item=>item.id==='7')!;
const mutation=()=>({operationId:randomUUID(),requestedAt:new Date().toISOString()});
const reply=(body:unknown,status=200)=>new Response(status===204?null:JSON.stringify(body),{status});
let dir:string,owner:Principal,other:Principal,connectionId:string,jiraConnectionId:string;
function fetchQueue(...values:(Response|Error)[]) {
  const fn=vi.fn();
  values.forEach(value=>value instanceof Error?fn.mockRejectedValueOnce(value):fn.mockResolvedValueOnce(value));
  vi.stubGlobal('fetch',fn);
  return fn;
}
function input(name:string):Record<string,unknown> {
  const common={connectionId,...mutation()};
  switch(name){
    case 'github_work':return {connectionId};
    case 'github_repositories':return {connectionId};
    case 'github_repository_add':case 'github_repository_remove':return {...common,repo:'acme/new'};
    case 'github_review':return {...common,...ref,event:'APPROVE'};
    case 'github_comment':return {...common,...ref,body:'Test-only comment'};
    case 'github_request_review':return {...common,...ref,reviewers:['reviewer-1'],teams:['team-1']};
    case 'github_merge':return {...common,...ref,method:'squash',headSha:sha};
    case 'github_rerun':return {...common,...ref,headSha:sha};
    case 'github_jira_sync':return {...common,jiraConnectionId,key:'TT-1',intent:'review',action:'apply',expectedTransitionId:transition.id};
    default:throw new Error('Missing scenario');
  }
}
function captureDigest() {
  const data=structuredClone(reposCapture.data) as unknown as Record<string,unknown>;
  const visit=(node:unknown):void=>{if(Array.isArray(node))node.forEach(visit);else if(node&&typeof node==='object'){const value=node as Record<string,unknown>;if(typeof value.number==='number'&&typeof value.url==='string'&&!value.id)value.id=`node:${value.url}`;Object.values(value).forEach(visit);}};
  visit(data);
  return github.parseReposData(data,Array.from({length:8},(_,index)=>`acme/repo-${index+1}`),[]);
}
function mutationResponses(name:string,write:Response|Error) {
  if(name==='github_review')return [reply(captured.pull),reply(captured.viewer),write];
  if(name==='github_request_review')return [reply(captured.pull),write];
  if(name==='github_merge')return [reply(captured.pull),write];
  if(name==='github_rerun')return [reply(captured.pull),reply({workflow_runs:[runsCapture['acme/repo-4'].workflow_runs[0]],total_count:1}),write];
  return [write];
}
beforeEach(async()=>{
  dir=mkdtempSync(path.join(tmpdir(),'daily-github-ops-'));
  vi.stubEnv('DAILY_WEB_DB_PATH',path.join(dir,'db.sqlite'));
  vi.stubEnv('DAILY_WEB_SECRET_KEY',randomBytes(32).toString('base64'));
  const a=await createUser('owner',randomBytes(32).toString('hex')),b=await createUser('other',randomBytes(32).toString('hex'));
  owner={userId:a.id,scopes,kind:'oauth'};other={userId:b.id,scopes,kind:'oauth'};
  connectionId=saveConnection(a.id,'pulls','GitHub',{token:randomBytes(32).toString('hex'),repos:'acme/repo-4'});
  jiraConnectionId=saveConnection(a.id,'jira','Jira',{cloud:'example.invalid',email:'fixture@example.invalid',token:randomBytes(32).toString('hex')});
  setModuleEnabled(a.id,'pulls',true);setModuleEnabled(a.id,'jira',true);
});
afterEach(()=>{vi.restoreAllMocks();vi.unstubAllGlobals();vi.unstubAllEnvs();rmSync(dir,{recursive:true,force:true});});

describe('every GitHub shared operation boundary',()=>{
  for(const op of githubOperations){
    it(`${op.name}: denies scope and foreign connection and rejects invalid input before network`,async()=>{
      const network=fetchQueue();
      await expect(op.run({...owner,scopes:[]},input(op.name))).rejects.toMatchObject({status:403,code:'insufficient_scope'});
      await expect(op.run(other,input(op.name))).rejects.toMatchObject({status:404,code:'not_found'});
      await expect(op.run(owner,{...input(op.name),unrecognized:true})).rejects.toMatchObject({status:400,code:'invalid_input'});
      expect(network).not.toHaveBeenCalled();
    });
  }
  it('configures repositories while the module is disabled, with atomic idempotent add/remove',async()=>{
    setModuleEnabled(owner.userId,'pulls',false);
    const add=input('github_repository_add'),remove=input('github_repository_remove');
    await runGithubOperation(owner,'github_repository_add',add);
    await runGithubOperation(owner,'github_repository_add',add);
    expect(await runGithubOperation(owner,'github_repositories',{connectionId})).toEqual({repositories:['acme/repo-4','acme/new']});
    await runGithubOperation(owner,'github_repository_remove',remove);
    await runGithubOperation(owner,'github_repository_remove',remove);
    expect(await runGithubOperation(owner,'github_repositories',{connectionId})).toEqual({repositories:['acme/repo-4']});
  });
  it('reads tracked/review/mine views, default branch information and cursor pages from captured provider contracts',async()=>{
    const digest=captureDigest();
    const tracked=vi.spyOn(github,'fetchPulls').mockResolvedValue(digest);
    const reviews=vi.spyOn(github,'fetchReviewRequests').mockResolvedValue({...digest,total:digest.items.length,truncated:false,scopeNote:null});
    const mine=vi.spyOn(github,'fetchMyPulls').mockResolvedValue({...digest,total:digest.items.length,truncated:false});
    const first=await runGithubOperation(owner,'github_work',{connectionId,limit:1}) as {items:{id:string}[];nextCursor:string;defaultBranches:unknown[]};
    const second=await runGithubOperation(owner,'github_work',{connectionId,limit:1,cursor:first.nextCursor}) as {items:{id:string}[]};
    expect(first.items).toHaveLength(1);expect(second.items[0].id).not.toBe(first.items[0].id);expect(first.defaultBranches.length).toBeGreaterThan(0);
    await runGithubOperation(owner,'github_work',{connectionId,view:'reviews'});await runGithubOperation(owner,'github_work',{connectionId,view:'mine'});
    expect(await runGithubOperation(owner,'github_work',{connectionId,filters:'pr_q=never-matching-fixture'})).toMatchObject({items:[]});
    expect(tracked).toHaveBeenCalledTimes(3);expect(reviews).toHaveBeenCalledTimes(1);expect(mine).toHaveBeenCalledTimes(1);
  });
  it('preserves partial reads and rejects unknown result enums and invalid cursors visibly',async()=>{
    const digest=captureDigest();
    const loader=vi.spyOn(github,'fetchPulls').mockResolvedValue({...digest,errors:['sensitive upstream detail']});
    const partial=await runGithubOperation(owner,'github_work',{connectionId});
    expect(partial.complete).toBe(false);expect(JSON.stringify(partial)).not.toContain('sensitive upstream detail');
    await expect(runGithubOperation(owner,'github_work',{connectionId,cursor:'missing'})).rejects.toMatchObject({status:400,code:'invalid_cursor'});
    loader.mockResolvedValue({...digest,items:[{...digest.items[0],ci:'unknown'}]} as never);
    await expect(runGithubOperation(owner,'github_work',{connectionId})).rejects.toMatchObject({status:502,code:'invalid_result'});
    loader.mockRejectedValue(new Error('sensitive provider failure'));
    await expect(runGithubOperation(owner,'github_work',{connectionId})).rejects.toMatchObject({status:502,code:'upstream_failed'});
  });
  it('submits review/comment/reviewer requests and replays only their confirmed captured identities',async()=>{
    const scenarios:[string,Response,Record<string,unknown>][]=[
      ['github_review',reply({id:approved.id,state:approved.state}),{id:approved.id,state:'APPROVED'}],
      ['github_comment',reply(captured.comment,201),{id:captured.comment.id,url:captured.comment.html_url}],
      ['github_request_review',reply({...captured.pull,requested_teams:[{slug:'team-1'}]},201),{requested:['reviewer-1','team:team-1']}],
    ];
    for(const [name,response,expected] of scenarios){
      const fetch=fetchQueue(...mutationResponses(name,response));const values=input(name);
      expect(await runGithubOperation(owner,name,values)).toMatchObject(expected);
      const count=fetch.mock.calls.length;expect(await runGithubOperation(owner,name,values)).toMatchObject(expected);expect(fetch).toHaveBeenCalledTimes(count);
    }
  });
  it('merges the current captured SHA and replays without re-reading the now-closed PR',async()=>{
    const fetch=fetchQueue(reply(captured.pull),reply({merged:true,sha}));const values=input('github_merge');
    expect(await runGithubOperation(owner,'github_merge',values)).toEqual({ok:true,sha});
    expect(await runGithubOperation(owner,'github_merge',values)).toEqual({ok:true,sha});
    expect(fetch).toHaveBeenCalledTimes(2);expect(JSON.parse(fetch.mock.calls[1][1].body)).toMatchObject({sha,merge_method:'squash'});
  });
  it('reruns bounded failed jobs and reports zero when no captured Actions jobs failed',async()=>{
    const failed=runsCapture['acme/repo-4'].workflow_runs;
    const fetch=fetchQueue(reply(captured.pull),reply({workflow_runs:failed}),...failed.slice(0,5).map(()=>reply({},201)));
    const values=input('github_rerun');expect(await runGithubOperation(owner,'github_rerun',values)).toMatchObject({rerun:5,complete:true,failed:[]});
    await runGithubOperation(owner,'github_rerun',values);expect(fetch).toHaveBeenCalledTimes(7);
    fetchQueue(reply(captured.pull),reply(runsCapture['acme/repo-1']));
    expect(await runGithubOperation(owner,'github_rerun',input('github_rerun'))).toMatchObject({rerun:0,complete:true});
  });
  it('uses both providers/scopes for Jira sync, revalidates the selected transition and replays without another transition',async()=>{
    const suggest=vi.spyOn(jiraActions,'suggestSync').mockResolvedValue(transition),apply=vi.spyOn(jiraActions,'applySync').mockResolvedValue();
    const values=input('github_jira_sync');
    expect(await runGithubOperation(owner,'github_jira_sync',{...values,action:'suggest'})).toEqual({transition});
    expect(await runGithubOperation(owner,'github_jira_sync',values)).toMatchObject({ok:true,id:transition.id});
    await runGithubOperation(owner,'github_jira_sync',values);expect(apply).toHaveBeenCalledTimes(1);expect(suggest).toHaveBeenCalledTimes(1);
    await expect(runGithubOperation({...owner,scopes:['github:read','jira:read']},'github_jira_sync',input('github_jira_sync'))).rejects.toMatchObject({status:403});
    apply.mockRejectedValue(new TransitionUnavailable());
    await expect(runGithubOperation(owner,'github_jira_sync',input('github_jira_sync'))).rejects.toMatchObject({status:409,code:'state_changed'});
  });
});

describe('GitHub refusal and uncertain outcomes',()=>{
  for(const name of ['github_review','github_comment','github_request_review','github_merge','github_rerun']){
    it(`${name}: never repeats an uncertain write and exposes no upstream error text`,async()=>{
      const network=fetchQueue(...mutationResponses(name,new Error('sensitive upstream payload'))),values=input(name);
      await expect(runGithubOperation(owner,name,values)).rejects.toMatchObject({status:409,code:'uncertain_outcome'});
      const count=network.mock.calls.length;
      await expect(runGithubOperation(owner,name,values)).rejects.toMatchObject({status:409,code:'uncertain_outcome'});
      expect(network).toHaveBeenCalledTimes(count);
    });
  }
  for(const name of ['github_review','github_comment','github_request_review','github_merge']){
    it(`${name}: records a confirmed provider rejection without claiming a write happened`,async()=>{
      fetchQueue(...mutationResponses(name,reply(captured.refusal.response,403)));
      await expect(runGithubOperation(owner,name,input(name))).rejects.toMatchObject({status:502,code:'provider_refused'});
    });
  }
  it('keeps partial rerun receipts uncertain and replays sanitized outcomes without more run requests',async()=>{
    const [a,b]=runsCapture['acme/repo-4'].workflow_runs;
    const fetch=fetchQueue(reply(captured.pull),reply({workflow_runs:[a,b]}),reply({},201),reply(captured.refusal.response,403));const values=input('github_rerun');
    for(let attempt=0;attempt<2;attempt++){
      try{await runGithubOperation(owner,'github_rerun',values);throw new Error('Expected partial failure');}
      catch(error){expect(error).toMatchObject({code:'uncertain_outcome',cause:{outcome:{rerun:1,complete:false,failed:[{id:b.id,error:'The provider outcome was not confirmed'}]}}});}
    }
    expect(fetch).toHaveBeenCalledTimes(4);
  });
  it.each([
    ['github_review',{...captured.pull,draft:true},captured.viewer,'draft_pull'],
    ['github_review',captured.pull,{login:'author'},'self_review'],
    ['github_request_review',{...captured.pull,draft:true},captured.viewer,'draft_pull'],
  ])('blocks %s state before submitting',async(name,pull,viewer,code)=>{
    const fetch=fetchQueue(reply(pull),reply(viewer));await expect(runGithubOperation(owner,name,input(name))).rejects.toMatchObject({status:409,code});
    expect(fetch.mock.calls.every(([,init])=>init.method==='GET')).toBe(true);
  });
  it.each([
    ['draft',{draft:true}],['closed',{state:'closed'}],['stale SHA',{head:{sha:'a'.repeat(40)}}],['unknown mergeability',{mergeable:null}],['blocked',{mergeable:false}],
  ])('does not merge a %s pull request',async(_label,over)=>{
    const fetch=fetchQueue(reply({...captured.pull,...over}));await expect(runGithubOperation(owner,'github_merge',input('github_merge'))).rejects.toMatchObject({status:409,code:'state_changed'});expect(fetch).toHaveBeenCalledTimes(1);
  });
  it('rejects unknown review results, malformed snapshots and missing reviewer response fields',async()=>{
    fetchQueue(...mutationResponses('github_review',reply({id:approved.id,state:'PENDING'})));
    await expect(runGithubOperation(owner,'github_review',input('github_review'))).rejects.toMatchObject({code:'uncertain_outcome'});
    fetchQueue(reply({...captured.pull,state:'unexpected'}));
    await expect(runGithubOperation(owner,'github_review',input('github_review'))).rejects.toMatchObject({status:502,code:'invalid_result'});
    fetchQueue(...mutationResponses('github_request_review',reply({})));
    await expect(runGithubOperation(owner,'github_request_review',input('github_request_review'))).rejects.toMatchObject({code:'uncertain_outcome'});
  });
  it('keeps unknown cross-provider sync outcomes from applying again',async()=>{
    const apply=vi.spyOn(jiraActions,'applySync').mockRejectedValue(new Error('sensitive provider payload'));const values=input('github_jira_sync');
    await expect(runGithubOperation(owner,'github_jira_sync',values)).rejects.toMatchObject({code:'uncertain_outcome'});
    await expect(runGithubOperation(owner,'github_jira_sync',values)).rejects.toMatchObject({code:'uncertain_outcome'});expect(apply).toHaveBeenCalledTimes(1);
  });
});


describe('real shared Jira-sync preflight',()=>{
  it('applies the confirmed captured transition and never consults Jira on a confirmed replay',async()=>{
    const load=vi.spyOn(transitionProvider,'fetchTransitions').mockResolvedValue(parseTransitions(transitionCapture,'10175'));
    const apply=vi.spyOn(transitionProvider,'applyTransition').mockResolvedValue();
    const values=input('github_jira_sync');
    await runGithubOperation(owner,'github_jira_sync',values);
    await runGithubOperation(owner,'github_jira_sync',values);
    expect(load).toHaveBeenCalledTimes(1);expect(apply).toHaveBeenCalledTimes(1);
    expect(apply.mock.calls[0].slice(1)).toEqual(['TT-1',transition.id]);
  });
  it.each(['changed','screen','different-intent'] as const)('rejects %s before applying the shared Jira transition',async(scenario)=>{
    const available=parseTransitions(transitionCapture,'10175').map(item=>scenario==='screen'&&item.id===transition.id?{...item,requires:'screen' as const}:item);
    vi.spyOn(transitionProvider,'fetchTransitions').mockResolvedValue(available);
    const apply=vi.spyOn(transitionProvider,'applyTransition').mockResolvedValue();
    const values={...input('github_jira_sync'),...(scenario==='changed'?{expectedTransitionId:'unconfirmed'}:{}),...(scenario==='different-intent'?{intent:'in-progress'}:{})};
    await expect(runGithubOperation(owner,'github_jira_sync',values)).rejects.toMatchObject({status:409,code:'state_changed'});
    expect(apply).not.toHaveBeenCalled();
  });
  it('reports suggestion failures and missing Jira read scope without leaking provider text',async()=>{
    const suggest=vi.spyOn(jiraActions,'suggestSync').mockRejectedValue(new Error('sensitive upstream details'));
    const values={...input('github_jira_sync'),action:'suggest'};
    await expect(runGithubOperation({...owner,scopes:['github:read']},'github_jira_sync',values)).rejects.toMatchObject({status:403});expect(suggest).not.toHaveBeenCalled();
    await expect(runGithubOperation(owner,'github_jira_sync',values)).rejects.toMatchObject({status:502,code:'upstream_failed'});
  });
});


it('rejects requesting the author before making a reviewer mutation',async()=>{
  const fetch=fetchQueue(reply(captured.pull));
  await expect(runGithubOperation(owner,'github_request_review',{...input('github_request_review'),reviewers:['author'],teams:[]})).rejects.toMatchObject({status:409,code:'author_review'});
  expect(fetch).toHaveBeenCalledTimes(1);
});
