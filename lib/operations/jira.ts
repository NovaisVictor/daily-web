import { z } from 'zod';
import { createHash } from 'node:crypto';
import { operation, connection, connectionShape, mutationShape, pageShape, page, mutate } from './context';
import { AccessError } from '@/lib/access/principal';
import { ExternalNotSubmittedError, ExternalPartialOutcome, findReceipt, insertReceipt } from '@/lib/access/receipts';
import { ProviderRefusal } from '@/lib/integrations/refusal';
import { getDb } from '@/lib/db';
import type { Principal } from '@/lib/access/principal';
import { fetchMyPulls } from '@/lib/integrations/githubApi';
import { parseJiraOrder, sortJira, JIRA_ORDER_PARAM } from '@/lib/jiraOrder';
import * as jira from '@/lib/integrations/jiraApi';
import { fetchTransitions, applyTransition, TransitionUnavailable } from '@/lib/integrations/jira/transitions';
import { fetchPendingApprovals, answerApproval } from '@/lib/integrations/jira/approvals';
import { addComment } from '@/lib/integrations/jira/comments';
import { changeFlag, FlagCommentFailed } from '@/lib/integrations/jira/flag';
import { applyEdit, fetchPriorityOptions, createStoryInEpic, InvalidEdit } from '@/lib/integrations/jira/edits';
import { suggestStartDates, type StartDateResult } from '@/lib/integrations/jira/startDates';
import { isCalendarDate } from '@/lib/integrations/jira/parse';
import { jiraWatchedKeys, setJiraWatchedKeys, jiraFollowedPeople, setJiraFollowedPeople, MAX_JIRA_PEOPLE, isJiraAccountId } from '@/lib/preferences';
import { parseJiraFilters, matchesJiraFilters } from '@/lib/jiraFilters';
import { buildStandup, buildWeekly, standupText, weeklyText } from '@/lib/standup';
import { dropCache, patchCachedState, resolveJiraProblem } from '@/lib/refresher';
import type { Connection } from '@/lib/vault/connections';
import { pickTransition, type SyncIntent } from '@/lib/pullJiraSync';
import { fetchPersonView } from '@/lib/jiraPeople';
import type { JiraItem, JiraDatedItem, PullRequestItem } from '@/lib/types';
import { COMMENT_MAX, FLAG_REASON_MAX, SUMMARY_MAX, DESCRIPTION_MAX, START_DATE_BATCH } from '@/lib/jiraLimits';

const key=z.string().regex(/^[A-Z][A-Z0-9_]*-\d+$/);
const id=z.string().regex(/^\d{1,18}$/);
const issueShape={...connectionShape,key};
const writeShape={...issueShape,...mutationShape};
const date=z.string().refine(isCalendarDate);
const account=z.string().refine(isJiraAccountId);
const connOf=(p:Parameters<typeof connection>[0],i:{connectionId:string},mode:'read'|'write')=>connection(p,i.connectionId,'jira',`jira:${mode}`);
const subjectOf=(owner:string,accountId?:string):jira.JiraSubject=>{
  if(!accountId)return jira.ME;
  if(!jiraFollowedPeople(owner).some(p=>p.accountId===accountId))throw new AccessError(404,'person_not_followed','Follow this person before inspecting their work');
  return {kind:'person',accountId};
};
async function preferenceMutation<T>(principal:Principal,name:string,input:{operationId:string;requestedAt:string;connectionId:string},prepare:()=>Promise<T>,apply:(prepared:T)=>void):Promise<{ok:true}> {
  const mutation={key:input.operationId,requestedAt:input.requestedAt};
  if(findReceipt(principal.userId,name,mutation,input))return {ok:true};
  const prepared=await prepare();
  return getDb().transaction(()=>{
    if(findReceipt(principal.userId,name,mutation,input))return {ok:true as const};
    apply(prepared);
    insertReceipt(principal.userId,name,mutation,input,input.connectionId,'external','success',{ok:true},Date.now(),input.connectionId);
    return {ok:true as const};
  }).immediate();
}
export interface JiraActionContext { userId: string; connection: Connection }

export const jiraActions = {
  transitions: (conn: Connection, key: string) => fetchTransitions(conn, key),
  approvals: (conn: Connection, key: string) => fetchPendingApprovals(jira.jiraAuth(conn), key),
  priorities: (conn: Connection, key: string) => fetchPriorityOptions(conn, key),
  epics: (conn: Connection, project: string) => jira.fetchOpenEpics(conn, project),
  searchPeople: (conn: Connection, query: string) => jira.searchPeople(conn, query),
  personView: (conn: Connection, accountId: string) => fetchPersonView(conn, accountId),
  suggestStartDate: (conn: Connection, key: string) => jira.suggestStartDate(conn, key),
  async suggestStartDates(conn: Connection, keys: string[]) {
    return suggestStartDates(conn, keys);
  },
  async applyTransition(ctx: JiraActionContext, key: string, transitionId: string) {
    await applyTransition(ctx.connection, key, transitionId);
    dropCache(ctx.userId);
  },
  async suggestSync(conn: Connection, key: string, intent: SyncIntent) {
    return pickTransition(await fetchTransitions(conn, key), intent);
  },
  async applySync(ctx: JiraActionContext, key: string, intent: SyncIntent, expectedTransitionId: string) {
    const chosen = await jiraActions.suggestSync(ctx.connection, key, intent);
    if (!chosen || chosen.requires !== 'nothing' || chosen.id !== expectedTransitionId) throw new TransitionUnavailable();
    await jiraActions.applyTransition(ctx, key, chosen.id);
  },
  async answerApproval(ctx: JiraActionContext, key: string, approvalId: string, decision: 'approve' | 'decline') {
    const pending = await jiraActions.approvals(ctx.connection, key);
    if (!pending.some(item => item.id === approvalId)) throw new ExternalNotSubmittedError('essa aprovação não está mais pendente para você');
    await answerApproval(jira.jiraAuth(ctx.connection), key, approvalId, decision);
    dropCache(ctx.userId);
  },
  async comment(ctx: JiraActionContext, key: string, text: string) {
    const result = await addComment(ctx.connection, key, text);
    dropCache(ctx.userId);
    return result;
  },
  async flag(ctx: JiraActionContext, key: string, change: Parameters<typeof changeFlag>[2]) {
    try { await changeFlag(jira.jiraAuth(ctx.connection), key, change); }
    finally { dropCache(ctx.userId); }
  },
  async edit(ctx: JiraActionContext, key: string, change: Parameters<typeof applyEdit>[2]) {
    await applyEdit(ctx.connection, key, change);
    dropCache(ctx.userId);
  },
  async createStory(ctx: JiraActionContext, key: string, story: Parameters<typeof createStoryInEpic>[2]) {
    const result = await createStoryInEpic(ctx.connection, key, story);
    dropCache(ctx.userId);
    return result;
  },
  async parent(ctx: JiraActionContext, key: string, epicKey: string) {
    await jira.setEpic(ctx.connection, key, epicKey);
    resolveJiraProblem(ctx.userId, key, ['story-without-epic']);
    resolveJiraProblem(ctx.userId, epicKey, ['epic-without-stories']);
  },
  async startDate(ctx: JiraActionContext, key: string, date: string) {
    await jira.setStartDate(ctx.connection, key, date);
    resolveJiraProblem(ctx.userId, key, ['story-in-progress-without-start', 'story-done-without-start']);
  },
  async startDates(ctx: JiraActionContext, items: {key: string; date: string}[]) {
    await jira.startDateField(jira.jiraAuth(ctx.connection));
    const results: StartDateResult[] = [];
    for (const item of items) {
      try {
        await jiraActions.startDate(ctx, item.key, item.date);
        results.push({key: item.key, outcome: 'written'});
      } catch(error) { results.push({key: item.key, outcome: 'refused', error: error instanceof Error ? error.message : String(error)}); }
    }
    return results;
  },
  setPerson(userId: string, accountId: string, person: Awaited<ReturnType<typeof jira.fetchPerson>>) {
    return getDb().transaction(() => {
      const current = jiraFollowedPeople(userId);
      if (person && !current.some(item => item.accountId === accountId) && current.length >= MAX_JIRA_PEOPLE)
        throw new AccessError(400, 'people_limit', `limite de ${MAX_JIRA_PEOPLE} pessoas acompanhadas`);
      const people = person ? current.some(item => item.accountId === accountId) ? current : [...current, person]
        : current.filter(item => item.accountId !== accountId);
      setJiraFollowedPeople(userId, people);
      patchCachedState(userId, state => ({ ...state, jiraFollowedPeople: people }));
      return people;
    }).immediate();
  },
  async personToFollow(ctx: JiraActionContext, accountId: string) {
    const current = jiraFollowedPeople(ctx.userId);
    const existing = current.find(item => item.accountId === accountId);
    if (existing) return existing;
    if (current.length >= MAX_JIRA_PEOPLE) throw new AccessError(400, 'people_limit', `limite de ${MAX_JIRA_PEOPLE} pessoas acompanhadas`);
    const person = await jira.fetchPerson(ctx.connection, accountId);
    if (!person) throw new AccessError(404, 'not_found', 'pessoa não encontrada no Jira');
    return person;
  },
  async followPerson(ctx: JiraActionContext, accountId: string) {
    return jiraActions.setPerson(ctx.userId, accountId, await jiraActions.personToFollow(ctx, accountId));
  },
  watch(userId: string, key: string, action: 'watch' | 'unwatch') {
    getDb().transaction(() => {
      const keys = jiraWatchedKeys(userId);
      if (keys.length >= 100 && action === 'watch' && !keys.includes(key)) throw new AccessError(400, 'watch_limit', 'Too many watched issues');
      setJiraWatchedKeys(userId, action === 'watch' ? [...keys, key] : keys.filter(item => item !== key));
    }).immediate();
    dropCache(userId);
  },
};

export const jiraOperations=[
  operation('jira_work','Read Jira panel views with its URL filters and role selection','jira:read','read',{...connectionShape,...pageShape,view:z.enum(['open','delivered','approved','problems','watched','hierarchy']).default('open'),role:z.enum(['assignee','reporter','both']).default('both'),accountId:account.optional(),filters:z.string().max(2000).default(''),period:z.enum(['today','week']).default('today'),order:z.enum(['atualizacao','prazo','prioridade','parado']).optional()},async(p,i)=>{
    const conn=connOf(p,i,'read'),subject=subjectOf(p.userId,i.accountId);
    let items:JiraItem[];
    switch(i.view){
      case 'delivered':items=await jira.fetchDelivered(conn,subject);break;
      case 'approved':items=await jira.fetchApproved(conn,subject);break;
      case 'problems':items=await jira.fetchProblems(conn,subject);break;
      case 'watched':items=await jira.fetchByKeys(conn,jiraWatchedKeys(p.userId));break;
      default:items=await jira.fetchIssues(conn,i.role,subject);
    }
    if((i.view==='delivered'||i.view==='approved')&&i.period==='today')items=(items as JiraDatedItem[]).filter(item=>item.today);
    const ancestors=await jira.fetchAncestors(conn,items);
    if(i.view==='hierarchy')items=[...new Map([...ancestors,...items].map(item=>[item.key,item])).values()];
    const byKey=new Map([...ancestors,...items].map(item=>[item.key,item]));
    const parameters=new URLSearchParams(i.filters);
    const filtered=sortJira(items.filter(item=>matchesJiraFilters(item,parseJiraFilters(parameters),byKey)),i.order??parseJiraOrder(parameters.get(JIRA_ORDER_PARAM)));
    return {...page(filtered,i,item=>item.key),connectionId:conn.id,ancestors};
  }),
  operation('jira_transitions','List permitted issue transitions','jira:read','read',issueShape,async(p,i)=>({transitions:await jiraActions.transitions(connOf(p,i,'read'),i.key)})),
  operation('jira_transition','Apply a currently permitted issue transition','jira:write','write',{...writeShape,transitionId:id},async(p,i)=>{
    const conn=connOf(p,i,'write');return mutate(p,'jira_transition',{id:i.key,connectionId:conn.id},i,async()=>{
      try{await jiraActions.applyTransition({userId:p.userId,connection:conn},i.key,i.transitionId);}catch(e){if(e instanceof TransitionUnavailable)throw new ExternalNotSubmittedError('Transition is no longer available');throw e;}
      return {ok:true};
    });
  }),
  operation('jira_approvals','List approvals awaiting the current Jira user','jira:read','read',issueShape,async(p,i)=>({approvals:await jiraActions.approvals(connOf(p,i,'read'),i.key)})),
  operation('jira_approval','Approve or decline a pending Jira approval','jira:write','write',{...writeShape,approvalId:id,decision:z.enum(['approve','decline'])},async(p,i)=>{
    const conn=connOf(p,i,'write');
    return mutate(p,'jira_approval',{id:i.key,connectionId:conn.id},i,async()=>{
      await jiraActions.answerApproval({userId:p.userId,connection:conn},i.key,i.approvalId,i.decision);return {ok:true};});
  }),
  operation('jira_comment','Add a Jira comment','jira:write','write',{...writeShape,text:z.string().trim().min(1).max(COMMENT_MAX)},async(p,i)=>{
    const conn=connOf(p,i,'write');return mutate(p,'jira_comment',{id:i.key,connectionId:conn.id},i,async()=>{const comment=await jiraActions.comment({userId:p.userId,connection:conn},i.key,i.text);return {ok:true,id:comment.id};});
  }),
  operation('jira_flag','Mark or remove an impediment','jira:write','write',{...writeShape,action:z.enum(['flag','unflag']),reason:z.string().trim().max(FLAG_REASON_MAX).default('')},async(p,i)=>{
    if(i.action==='flag'&&!i.reason)throw new AccessError(400,'reason_required','An impediment needs a reason');
    const conn=connOf(p,i,'write');return mutate(p,'jira_flag',{id:i.key,connectionId:conn.id},i,async()=>{
      try { await jiraActions.flag({userId:p.userId,connection:conn},i.key,i.action==='flag'?{action:'flag',reason:i.reason}:{action:'unflag',note:i.reason||null}); }
      catch(error) { if(error instanceof FlagCommentFailed) throw new ExternalPartialOutcome({id:i.key,code:'flag_changed_comment_unconfirmed'}); throw error; }
      return {ok:true};
    });
  }),
  operation('jira_priorities','Read available priorities for an issue','jira:read','read',issueShape,async(p,i)=>({priorities:await jiraActions.priorities(connOf(p,i,'read'),i.key)})),
  operation('jira_edit','Set due date, priority or assign to self','jira:write','write',{...writeShape,change:z.enum(['due','priority','assign-self']),dueDate:date.nullable().optional(),priorityId:id.optional()},async(p,i)=>{
    if(i.change==='due'&&i.dueDate===undefined||i.change==='priority'&&!i.priorityId)throw new AccessError(400,'value_required','Provide the field value');
    const edit=i.change==='due'?{change:'due' as const,dueDate:i.dueDate!}:i.change==='priority'?{change:'priority' as const,priorityId:i.priorityId!}:{change:'assign-self' as const};
    const conn=connOf(p,i,'write');return mutate(p,'jira_edit',{id:i.key,connectionId:conn.id},i,async()=>{
      try{await jiraActions.edit({userId:p.userId,connection:conn},i.key,edit);}catch(error){if(error instanceof InvalidEdit)throw new ExternalNotSubmittedError('The requested field value is unavailable');throw error;}
      return {ok:true};});
  }),
  operation('jira_story_create','Create a story under an epic','jira:write','write',{...writeShape,summary:z.string().trim().min(1).max(SUMMARY_MAX),description:z.string().max(DESCRIPTION_MAX).nullable().default(null)},async(p,i)=>{
    const conn=connOf(p,i,'write');return mutate(p,'jira_story_create',{id:i.key,connectionId:conn.id},i,async()=>{
      try{const r=await jiraActions.createStory({userId:p.userId,connection:conn},i.key,{summary:i.summary,description:i.description});return {ok:true,id:r.key};}
      catch(error){if(error instanceof InvalidEdit)throw new ExternalNotSubmittedError('The epic does not support this story creation');throw error;}
    });
  }),
  operation('jira_epics','Search eligible epics in a project','jira:read','read',{...connectionShape,project:z.string().regex(/^[A-Z][A-Z0-9_]*$/)},async(p,i)=>({items:await jiraActions.epics(connOf(p,i,'read'),i.project)})),
  operation('jira_parent','Link a story to an epic','jira:write','write',{...writeShape,epicKey:key},async(p,i)=>{
    const conn=connOf(p,i,'write');return mutate(p,'jira_parent',{id:i.key,connectionId:conn.id},i,async()=>{await jiraActions.parent({userId:p.userId,connection:conn},i.key,i.epicKey);return {ok:true};});
  }),
  operation('jira_start_suggest','Suggest start dates from issue history','jira:read','read',{...connectionShape,keys:z.array(key).min(1).max(START_DATE_BATCH)},async(p,i)=>({suggestions:(await jiraActions.suggestStartDates(connOf(p,i,'read'),i.keys)).map(item=>item.status==='failed'?{...item,error:'Jira could not suggest a start date'}:item)})),
  operation('jira_start_apply','Set start dates; each item has its own retry receipt','jira:write','write',{...connectionShape,...mutationShape,items:z.array(z.strictObject({key,date})).min(1).max(START_DATE_BATCH)},async(p,i)=>{
    const conn=connOf(p,i,'write');if(new Set(i.items.map(v=>v.key)).size!==i.items.length)throw new AccessError(400,'duplicate_key','Repeated issue key');
    const today=new Date().toLocaleDateString('en-CA');if(i.items.some(v=>v.date>today))throw new AccessError(400,'future_date','Start date cannot be in the future');
    const results=[];
    for(const item of i.items){
      const operationId=createHash('sha256').update(JSON.stringify([i.operationId,item.key])).digest('hex');
      try {
        results.push(await mutate(p,'jira_start_apply',{id:item.key,connectionId:conn.id},{...i,operationId},async()=>{await jiraActions.startDate({userId:p.userId,connection:conn},item.key,item.date);return {ok:true,id:item.key};}));
      } catch(error) {
        if(error instanceof AccessError && error.code!=='uncertain_outcome') throw error;
        const refused=error instanceof ExternalNotSubmittedError || error instanceof ProviderRefusal;
        results.push({id:item.key,status:refused?'refused' as const:'uncertain' as const,code:refused?'state_changed' as const:'uncertain_outcome' as const});
      }
    }
    return {results};
  }),
  operation('jira_people','List followed Jira people','jira:read','read',connectionShape,async(p,i)=>{connOf(p,i,'read');return {people:jiraFollowedPeople(p.userId)};}),
  operation('jira_people_search','Search Jira users to follow','jira:read','read',{...connectionShape,query:z.string().trim().min(2).max(100)},async(p,i)=>({people:await jiraActions.searchPeople(connOf(p,i,'read'),i.query)})),
  operation('jira_people_follow','Follow or unfollow a Jira person','jira:write','write',{...connectionShape,...mutationShape,accountId:account,action:z.enum(['follow','unfollow'])},async(p,i)=>{
    const conn=connOf(p,i,'write');
    const result=await preferenceMutation(p,'jira_people_follow',i,async()=>{
      if(i.action==='unfollow')return null;
      return jiraActions.personToFollow({userId:p.userId,connection:conn},i.accountId);
    },person=>{
      jiraActions.setPerson(p.userId,i.accountId,person);
    });return result;
  }),
  operation('jira_watch','Watch or unwatch an issue','jira:write','write',{...writeShape,action:z.enum(['watch','unwatch'])},async(p,i)=>{
    const conn=connOf(p,i,'write');
    const result=await preferenceMutation(p,'jira_watch',i,async()=>{
      if(i.action==='watch'&&(await jira.fetchByKeys(conn,[i.key])).length===0)throw new AccessError(404,'not_found','Issue not found');
    },()=>{
      jiraActions.watch(p.userId,i.key,i.action);
    });return result;
  }),
  operation('jira_summary','Generate a daily or weekly summary with explicitly selected GitHub sources','jira:read','read',{...connectionShape,period:z.enum(['daily','weekly']),accountId:account.optional(),githubConnectionIds:z.array(z.string().min(1).max(100)).max(30).default([])},async(p,i)=>{
    const conn=connOf(p,i,'read'),subject=subjectOf(p.userId,i.accountId);
    if(i.accountId&&i.githubConnectionIds.length)throw new AccessError(400,'invalid_subject','GitHub sources represent your own work, not a followed person');
    const githubConnections=[...new Set(i.githubConnectionIds)].map(id=>connection(p,id,'pulls','github:read'));
    const [open,delivered,approved,digests]=await Promise.all([jira.fetchIssues(conn,'both',subject),jira.fetchDelivered(conn,subject),jira.fetchApproved(conn,subject),Promise.all(githubConnections.map(fetchMyPulls))]);
    const myPulls=[...new Map(digests.flatMap(d=>d.items).map(item=>[`${item.repo}#${item.number}`,item])).values()] as PullRequestItem[];
    const source={open,delivered,approved,myPulls};
    return {text:i.period==='daily'?standupText(buildStandup(source,new Date())):weeklyText(buildWeekly(source,new Date())),complete:digests.every(d=>!d.truncated&&!d.errors?.length),githubIncluded:githubConnections.length>0,githubSources:githubConnections.map((conn,index)=>({connectionId:conn.id,complete:!digests[index].truncated&&!digests[index].errors?.length}))};
  }),
];
