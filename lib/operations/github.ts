import { z } from 'zod';
import { operation, connection, connectionShape, mutationShape, pageShape, page, mutate } from './context';
import { AccessError, requireScope, type Principal } from '@/lib/access/principal';
import * as github from '@/lib/integrations/githubApi';
import * as actions from '@/lib/integrations/github/actions';
import { GithubResponseError } from '@/lib/integrations/github/client';
import { ExternalPartialOutcome, localMutation } from '@/lib/access/receipts';
import { findConnection, saveConnection } from '@/lib/vault/connections';
import { isRequestableLogin } from '@/lib/githubLogin';
import { isValidRepo } from '@/lib/api/validation';
import { parsePullFilters, matchesPullFilters } from '@/lib/pullFilters';
import { dropCache } from '@/lib/refresher';
import { jiraActions } from './jira';

const refShape = { ...connectionShape, owner:z.string().regex(/^[A-Za-z0-9-]{1,100}$/),repo:z.string().regex(/^[A-Za-z0-9_.-]{1,100}$/).refine(value=>!/^\.+$/.test(value)),number:z.number().int().positive().max(1_000_000_000) };
const writeShape = {...refShape,...mutationShape};
const repoShape = {...connectionShape,repo:z.string().refine(isValidRepo)};
const pullSnapshot = z.object({state:z.enum(['open','closed']),draft:z.boolean(),user:z.object({login:z.string().min(1)}),head:z.object({sha:z.string().regex(/^[a-f0-9]{40}$/)})});
const viewerSchema = z.object({login:z.string().min(1)});
const reviewer = z.string().refine(isRequestableLogin);
const team = z.string().regex(/^[A-Za-z0-9][A-Za-z0-9_-]{0,99}$/);

function repositoryConnection(p:Principal,id:string,scope:string) {
  requireScope(p,scope);
  const conn=findConnection(p.userId,id);
  if(!conn||conn.module!=='pulls')throw new AccessError(404,'not_found','Connection not found');
  return conn;
}

async function beforeWrite<T>(work:()=>Promise<T>):Promise<T> {
  try{return await work();}
  catch(error){
    if(error instanceof GithubResponseError && error.status>=400 && error.status<500)throw new AccessError(502,'provider_refused','GitHub refused the operation; no write was accepted');
    if(error instanceof actions.PullStateRefusal)throw new AccessError(409,'state_changed','The pull request changed; refresh before trying again');
    throw error;
  }
}

async function currentPull(token:string,ref:actions.PullRef) {
  const value=pullSnapshot.safeParse(await github.githubRequest(token,`/repos/${encodeURIComponent(ref.owner)}/${encodeURIComponent(ref.repo)}/pulls/${ref.number}`));
  if(!value.success)throw new AccessError(502,'invalid_result','GitHub returned an unsupported pull request snapshot');
  if(value.data.state!=='open')throw new AccessError(409,'state_changed','The pull request is no longer open');
  if(value.data.draft)throw new AccessError(409,'draft_pull','The pull request is still a draft');
  return value.data;
}

export const githubOperations = [
  operation('github_work','Read GitHub work and apply the same URL filters as the panel','github:read','read',{...connectionShape,...pageShape,view:z.enum(['tracked','reviews','mine']).default('tracked'),filters:z.string().max(2000).default('')},async(p,i)=>{
    const conn=connection(p,i.connectionId,'pulls','github:read');
    const digest=i.view==='reviews'?await github.fetchReviewRequests(conn):i.view==='mine'?await github.fetchMyPulls(conn):await github.fetchPulls(conn);
    const items=digest.items.filter(item=>matchesPullFilters(item,parsePullFilters(new URLSearchParams(i.filters))));
    const complete=(digest.errors?.length ?? 0)===0 && (Array.isArray(digest.truncated)?digest.truncated.length===0:!digest.truncated);
    return {...digest,...page(items,i,item=>`${item.repo}#${item.number}`),errors:(digest.errors??[]).map(()=> 'upstream_query_failed'),complete};
  }),
  operation('github_repositories','List tracked repositories','github:read','read',connectionShape,async(p,i)=>({repositories:github.trackedRepos(repositoryConnection(p,i.connectionId,'github:read'))})),
  ...(['add','remove'] as const).map(action=>operation(`github_repository_${action}`,`${action} a tracked repository`,'github:write','write',{...repoShape,...mutationShape},async(p,i)=>{
    const conn=repositoryConnection(p,i.connectionId,'github:write');
    return localMutation(p.userId,`github_repository_${action}`,{id:i.repo,connectionId:conn.id,input:i},{key:i.operationId,requestedAt:i.requestedAt},()=>{
      const current=repositoryConnection(p,i.connectionId,'github:write');
      const repos=github.trackedRepos(current);
      const next=action==='add'?[...new Set([...repos,i.repo])]:repos.filter(r=>r!==i.repo);
      if(next.length>github.TRACKED_REPOS_MAX)throw new AccessError(400,'repository_limit','Remove a tracked repository before adding another');
      saveConnection(p.userId,'pulls',current.label,{...current.values,repos:github.serializeRepoList(next)},current.id);dropCache(p.userId);return {ok:true};});
  })),
  operation('github_review','Approve or request changes on a pull request','github:write','write',{...writeShape,event:z.enum(['APPROVE','REQUEST_CHANGES']),body:z.string().trim().max(actions.TEXT_MAX).nullable().default(null)},async(p,i)=>{
    const conn=connection(p,i.connectionId,'pulls','github:write');
    if(i.event==='REQUEST_CHANGES'&&!i.body)throw new AccessError(400,'body_required','Requesting changes needs an explanation');
    return mutate(p,'github_review',{id:`${i.owner}/${i.repo}#${i.number}`,connectionId:conn.id},i,async()=>beforeWrite(async()=>{
      const token=github.githubToken(conn);
      const pull=await currentPull(token,i);
      const viewer=viewerSchema.safeParse(await github.githubRequest(token,'/user'));
      if(!viewer.success)throw new AccessError(502,'invalid_result','GitHub returned an unsupported viewer identity');
      if(pull.user.login.toLowerCase()===viewer.data.login.toLowerCase())throw new AccessError(409,'self_review','You cannot review your own pull request');
      const result=await actions.submitReview(token,i,i.event,i.body);dropCache(p.userId);return {ok:true,id:result.id,state:result.state};
    }));
  }),
  operation('github_comment','Comment on an issue or pull request','github:write','write',{...writeShape,body:z.string().trim().min(1).max(actions.TEXT_MAX)},async(p,i)=>{
    const conn=connection(p,i.connectionId,'pulls','github:write');
    return mutate(p,'github_comment',{id:`${i.owner}/${i.repo}#${i.number}`,connectionId:conn.id},i,async()=>beforeWrite(async()=>{
      const result=await actions.addComment(github.githubToken(conn),i,i.body);dropCache(p.userId);return {ok:true,id:result.id,url:result.url};
    }));
  }),
  operation('github_request_review','Request review from users or teams','github:write','write',{...writeShape,reviewers:z.array(reviewer).max(actions.REVIEWERS_MAX).default([]),teams:z.array(team).max(actions.REVIEWERS_MAX).default([])},async(p,i)=>{
    const reviewers=[...new Set(i.reviewers)],teams=[...new Set(i.teams)];
    if(reviewers.length+teams.length===0||reviewers.length+teams.length>actions.REVIEWERS_MAX)throw new AccessError(400,'invalid_reviewers','Select valid reviewers');
    const conn=connection(p,i.connectionId,'pulls','github:write');
    return mutate(p,'github_request_review',{id:`${i.owner}/${i.repo}#${i.number}`,connectionId:conn.id},i,async()=>beforeWrite(async()=>{
      const token=github.githubToken(conn),pull=await currentPull(token,i);
      if(reviewers.some(login=>login.toLowerCase()===pull.user.login.toLowerCase()))throw new AccessError(409,'author_review','The pull request author cannot be requested as a reviewer');
      const requested=await actions.requestReviewers(token,i,reviewers,teams);dropCache(p.userId);return {ok:true,requested};
    }));
  }),
  operation('github_merge','Merge the exact reviewed head SHA','github:write','write',{...writeShape,method:z.enum(['merge','squash','rebase']),headSha:z.string().regex(/^[a-f0-9]{40}$/)},async(p,i)=>{
    const conn=connection(p,i.connectionId,'pulls','github:write');
    return mutate(p,'github_merge',{id:`${i.owner}/${i.repo}#${i.number}`,connectionId:conn.id},i,async()=>beforeWrite(async()=>{
      const sha=await actions.mergePull(github.githubToken(conn),i,i.method,i.headSha);dropCache(p.userId);return {ok:true,sha};
    }));
  }),
  operation('github_rerun','Retry failed checks only for the expected head SHA','github:write','write',{...writeShape,headSha:z.string().regex(/^[a-f0-9]{40}$/)},async(p,i)=>{
    const conn=connection(p,i.connectionId,'pulls','github:write');
    return mutate(p,'github_rerun',{id:`${i.owner}/${i.repo}#${i.number}`,connectionId:conn.id},i,async()=>beforeWrite(async()=>{
      const result=await actions.rerunFailedRuns(github.githubToken(conn),i,i.headSha);dropCache(p.userId);
      if(result.failed.length)throw new ExternalPartialOutcome({number:result.rerun,rerun:result.rerun,complete:false,failed:result.failed});
      return {ok:true,number:result.rerun,rerun:result.rerun,failed:[],complete:true};
    }));
  }),
  operation('github_jira_sync','Suggest or apply a Jira transition for a linked issue','github:read','write',{...connectionShape,...mutationShape,jiraConnectionId:z.string().min(1),key:z.string().regex(/^[A-Z][A-Z0-9_]*-\d+$/),intent:z.enum(['review','in-progress']),action:z.enum(['suggest','apply']),expectedTransitionId:z.string().max(30).optional()},async(p,i)=>{
    connection(p,i.connectionId,'pulls','github:read');const conn=connection(p,i.jiraConnectionId,'jira',i.action==='apply'?'jira:write':'jira:read');
    if(i.action==='suggest'){
      const transition=await jiraActions.suggestSync(conn,i.key,i.intent);
      if(!transition)throw new AccessError(409,'transition_unavailable','No matching transition is available');
      return {transition};
    }
    requireScope(p,'github:write');
    return mutate(p,'github_jira_sync',{id:i.key,connectionId:conn.id},i,async()=>{
      await jiraActions.applySync({userId:p.userId,connection:conn},i.key,i.intent,i.expectedTransitionId??'');
      dropCache(p.userId);return {ok:true,id:i.expectedTransitionId};});
  }),
];

export async function runGithubOperation(principal:Principal,name:string,input:unknown):Promise<Record<string,unknown>> {
  const selected=githubOperations.find(item=>item.name===name);
  if(!selected)throw new AccessError(400,'unsupported_operation','Unknown GitHub operation');
  return await selected.run(principal,input) as Record<string,unknown>;
}
