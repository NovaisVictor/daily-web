import { z } from 'zod';
import { operation, connection, connectionShape, mutationShape, pageShape, page, mutate } from './context';
import { AccessError, requireScope } from '@/lib/access/principal';
import * as github from '@/lib/integrations/githubApi';
import * as actions from '@/lib/integrations/github/actions';
import { ExternalNotSubmittedError } from '@/lib/access/receipts';
import { saveConnection } from '@/lib/vault/connections';
import { isValidRepo } from '@/lib/api/validation';
import { parsePullFilters, matchesPullFilters } from '@/lib/pullFilters';
import { dropCache } from '@/lib/refresher';
import { fetchTransitions, applyTransition, TransitionUnavailable } from '@/lib/integrations/jira/transitions';
import { pickTransition } from '@/lib/pullJiraSync';

const refShape = { ...connectionShape, owner:z.string().regex(/^[A-Za-z0-9-]{1,100}$/),repo:z.string().regex(/^[A-Za-z0-9_.-]{1,100}$/).refine(value=>!/^\.+$/.test(value)),number:z.number().int().positive().max(1_000_000_000) };
const writeShape = {...refShape,...mutationShape};
const repoShape = {...connectionShape,repo:z.string().refine(isValidRepo)};
export const githubOperations = [
  operation('github_work','Read GitHub work and apply the same URL filters as the panel','github:read','read',{...connectionShape,...pageShape,view:z.enum(['tracked','reviews','mine']).default('tracked'),filters:z.string().max(2000).default('')},async(p,i)=>{
    const conn=connection(p,i.connectionId,'pulls','github:read');
    const digest=i.view==='reviews'?await github.fetchReviewRequests(conn):i.view==='mine'?await github.fetchMyPulls(conn):await github.fetchPulls(conn);
    const items=digest.items.filter(item=>matchesPullFilters(item,parsePullFilters(new URLSearchParams(i.filters))));
    const complete=(digest.errors?.length ?? 0)===0 && (Array.isArray(digest.truncated)?digest.truncated.length===0:!digest.truncated);
    return {...digest,...page(items,i,item=>`${item.repo}#${item.number}`),errors:(digest.errors??[]).map(()=> 'upstream_query_failed'),complete};
  }),
  operation('github_repositories','List tracked repositories','github:read','read',connectionShape,async(p,i)=>({repositories:github.trackedRepos(connection(p,i.connectionId,'pulls','github:read'))})),
  ...(['add','remove'] as const).map(action=>operation(`github_repository_${action}`,`${action} a tracked repository`,'github:write','write',{...repoShape,...mutationShape},async(p,i)=>{
    const conn=connection(p,i.connectionId,'pulls','github:write');
    return mutate(p,`github_repository_${action}`,{id:i.repo,connectionId:conn.id},i,async()=>{
      const repos=github.trackedRepos(conn);
      const next=action==='add'?[...new Set([...repos,i.repo])]:repos.filter(r=>r!==i.repo);
      if(next.length>github.TRACKED_REPOS_MAX)throw new AccessError(400,'repository_limit','Remove a tracked repository before adding another');
      saveConnection(p.userId,'pulls',conn.label,{...conn.values,repos:github.serializeRepoList(next)},conn.id);dropCache(p.userId);return {ok:true};});
  })),
  operation('github_review','Approve or request changes on a pull request','github:write','write',{...writeShape,event:z.enum(['APPROVE','REQUEST_CHANGES']),body:z.string().trim().max(actions.TEXT_MAX).nullable().default(null)},async(p,i)=>{
    const conn=connection(p,i.connectionId,'pulls','github:write');
    if(i.event==='REQUEST_CHANGES'&&!i.body)throw new AccessError(400,'body_required','Requesting changes needs an explanation');
    return mutate(p,'github_review',{id:`${i.owner}/${i.repo}#${i.number}`,connectionId:conn.id},i,async()=>{
      const result=await actions.submitReview(github.githubToken(conn),i,i.event,i.body);dropCache(p.userId);return {ok:true,id:result.id,state:result.state};
    });
  }),
  operation('github_comment','Comment on an issue or pull request','github:write','write',{...writeShape,body:z.string().trim().min(1).max(actions.TEXT_MAX)},async(p,i)=>{
    const conn=connection(p,i.connectionId,'pulls','github:write');return mutate(p,'github_comment',{id:`${i.owner}/${i.repo}#${i.number}`,connectionId:conn.id},i,async()=>{const r=await actions.addComment(github.githubToken(conn),i,i.body);dropCache(p.userId);return {ok:true,id:r.id};});
  }),
  operation('github_request_review','Request review from users or teams','github:write','write',{...writeShape,reviewers:z.array(z.string().regex(/^[A-Za-z0-9-]{1,100}$/)).max(actions.REVIEWERS_MAX).default([]),teams:z.array(z.string().regex(/^[A-Za-z0-9_-]{1,100}$/)).max(actions.REVIEWERS_MAX).default([])},async(p,i)=>{
    if(i.reviewers.length+i.teams.length===0||i.reviewers.length+i.teams.length>actions.REVIEWERS_MAX)throw new AccessError(400,'invalid_reviewers','Select valid reviewers');
    const conn=connection(p,i.connectionId,'pulls','github:write');return mutate(p,'github_request_review',{id:`${i.owner}/${i.repo}#${i.number}`,connectionId:conn.id},i,async()=>{await actions.requestReviewers(github.githubToken(conn),i,i.reviewers,i.teams);dropCache(p.userId);return {ok:true};});
  }),
  operation('github_merge','Merge the exact reviewed head SHA','github:write','write',{...writeShape,method:z.enum(['merge','squash','rebase']),headSha:z.string().regex(/^[a-f0-9]{40}$/)},async(p,i)=>{
    const conn=connection(p,i.connectionId,'pulls','github:write');return mutate(p,'github_merge',{id:`${i.owner}/${i.repo}#${i.number}`,connectionId:conn.id},i,async()=>{
      try{const sha=await actions.mergePull(github.githubToken(conn),i,i.method,i.headSha);dropCache(p.userId);return {ok:true,sha};}
      catch(e){if(e instanceof actions.PullStateRefusal)throw new ExternalNotSubmittedError('Pull request state changed');throw e;}
    });
  }),
  operation('github_rerun','Retry failed checks only for the expected head SHA','github:write','write',{...writeShape,headSha:z.string().regex(/^[a-f0-9]{40}$/)},async(p,i)=>{
    const conn=connection(p,i.connectionId,'pulls','github:write');return mutate(p,'github_rerun',{id:`${i.owner}/${i.repo}#${i.number}`,connectionId:conn.id},i,async()=>{
      let result:actions.RerunOutcome;
      try{result=await actions.rerunFailedRuns(github.githubToken(conn),i,i.headSha);}
      catch(error){if(error instanceof actions.PullStateRefusal)throw new ExternalNotSubmittedError('Pull request state changed');throw error;}
      dropCache(p.userId);
      if(result.failed.length)throw new Error('Some run requests were not confirmed');return {ok:true,number:result.rerun};
    });
  }),
  operation('github_jira_sync','Suggest or apply a Jira transition for a linked issue','github:read','write',{...connectionShape,...mutationShape,jiraConnectionId:z.string().min(1),key:z.string().regex(/^[A-Z][A-Z0-9_]*-\d+$/),intent:z.enum(['review','in-progress']),action:z.enum(['suggest','apply']),expectedTransitionId:z.string().max(30).optional()},async(p,i)=>{
    connection(p,i.connectionId,'pulls','github:read');const conn=connection(p,i.jiraConnectionId,'jira',i.action==='apply'?'jira:write':'jira:read');
    const target=async()=>{const value=pickTransition(await fetchTransitions(conn,i.key),i.intent);if(!value)throw new AccessError(409,'transition_unavailable','No matching transition is available');return value;};
    if(i.action==='suggest')return {transition:await target()};
    requireScope(p,'github:write');
    return mutate(p,'github_jira_sync',{id:i.key,connectionId:conn.id},i,async()=>{
      const current=await target();if(i.expectedTransitionId!==current.id)throw new AccessError(409,'transition_changed','Confirm the current transition before applying it');
      try{await applyTransition(conn,i.key,current.id);}catch(error){if(error instanceof TransitionUnavailable)throw new ExternalNotSubmittedError('The transition is no longer available');throw error;}
      dropCache(p.userId);return {ok:true,id:current.id};});
  }),
];
