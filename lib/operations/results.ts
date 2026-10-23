import { z } from 'zod';
const identity=z.union([z.string(),z.number()]);
const success=z.object({ok:z.literal(true),id:identity.optional(),sha:z.string().optional(),state:z.enum(['APPROVED','CHANGES_REQUESTED']).optional(),code:z.string().optional(),number:z.number().int().optional()}).strict();
const pager={nextCursor:z.string().nullable(),complete:z.boolean()};
const statusCategory=z.enum(['new','indeterminate','done']);
const jiraItem=z.object({key:z.string(),summary:z.string(),status:z.string(),statusCategory,project:z.string(),url:z.string(),parent:z.object({key:z.string(),summary:z.string()}).nullable(),role:z.enum(['assignee','reporter','both']),awaitingApproval:z.boolean(),kind:z.string(),subtask:z.boolean(),hierarchyLevel:z.number().nullable(),updatedAt:z.string(),dueDate:z.string(),priority:z.object({name:z.string(),rank:z.number().nullable()}).nullable(),flag:z.enum(['impediment','none'])}).passthrough();
const transition=z.object({id:z.string(),name:z.string(),to:z.object({name:z.string(),category:statusCategory}),requires:z.enum(['nothing','screen'])});
const pull=z.object({id:z.string(),repo:z.string(),number:z.number().int(),title:z.string(),url:z.string(),author:z.string(),draft:z.boolean(),awaitingYou:z.boolean(),mine:z.boolean(),isPullRequest:z.boolean(),updatedAt:z.string(),createdAt:z.string(),ci:z.enum(['passing','failing','running','none']),review:z.enum(['approved','changes-requested','pending','none']),merge:z.enum(['clean','conflict','blocked','unknown','none']),reviewers:z.array(z.object({login:z.string(),state:z.enum(['approved','changes-requested','commented','dismissed','pending'])}))}).passthrough();
const task=z.object({id:z.string(),title:z.string(),completed:z.boolean(),due:z.string(),priority:z.enum(['low','normal','high']),time:z.string(),recur:z.enum(['','none','daily','weekly','monthly']),notes:z.string(),subtasks:z.array(z.object({id:z.string(),title:z.string(),completed:z.boolean()})),doing:z.boolean()});
const module=z.object({module:z.enum(['jira','pulls','tasks']),label:z.string(),summary:z.string(),multi:z.boolean(),enabled:z.boolean(),configured:z.boolean(),connections:z.array(z.object({id:z.string(),module:z.enum(['jira','pulls','tasks']),label:z.string(),visible:z.record(z.string(),z.string()),secretsSet:z.array(z.string()),updatedAt:z.string(),unreadable:z.boolean()}))});
const schemas:Record<string,z.ZodType>={
  github_work:z.object({items:z.array(pull),...pager}).passthrough(),
  github_repositories:z.object({repositories:z.array(z.string())}),
  jira_work:z.object({items:z.array(jiraItem),ancestors:z.array(jiraItem),connectionId:z.string(),...pager}).passthrough(),
  jira_transitions:z.object({transitions:z.array(transition)}),
  jira_approvals:z.object({approvals:z.array(z.object({id:z.string(),name:z.string()}))}),
  jira_priorities:z.object({priorities:z.object({priorities:z.array(z.object({id:z.string(),name:z.string()})),current:z.object({id:z.string(),name:z.string()}).nullable()})}),
  jira_epics:z.object({items:z.array(jiraItem)}),
  jira_start_suggest:z.object({suggestions:z.array(z.discriminatedUnion('status',[z.object({status:z.literal('suggested'),key:z.string(),date:z.string(),basis:z.enum(['started','finished','created'])}),z.object({status:z.literal('failed'),key:z.string(),error:z.string()})]))}),
  jira_start_apply:z.object({results:z.array(success)}),
  jira_people:z.object({people:z.array(z.object({accountId:z.string(),displayName:z.string()}))}),
  jira_people_search:z.object({people:z.array(z.object({accountId:z.string(),displayName:z.string()}))}),
  jira_summary:z.object({text:z.string(),complete:z.boolean(),githubIncluded:z.boolean(),githubSources:z.array(z.object({connectionId:z.string(),complete:z.boolean()}))}),
  tasks_list:z.object({items:z.array(task),...pager,groups:z.array(z.object({key:z.enum(['overdue','today','week','month','later','noDate']),label:z.string(),tasks:z.array(task)})).optional()}),
  tasks_get:z.object({task}),
  connections_list:z.object({modules:z.array(module)}),
  connections_setup:z.object({url:z.url(),instruction:z.string()}),
  connections_test:z.union([success,z.object({state:z.literal('not_applicable'),message:z.string()})]),
  focus_targets:z.object({targets:z.array(z.object({id:z.string(),label:z.string()}))}),
};
const writes=new Set(['github_repository_add','github_repository_remove','github_review','github_comment','github_request_review','github_merge','github_rerun','jira_transition','jira_approval','jira_comment','jira_flag','jira_edit','jira_story_create','jira_parent','jira_people_follow','jira_watch','tasks_create','tasks_edit','tasks_transition','tasks_delete','tasks_subtask_create','tasks_subtask_edit','connections_update','connections_remove','connections_toggle','focus_create']);
export function resultSchemaFor(name:string):z.ZodType {
  if(name==='github_jira_sync')return z.union([success,z.object({transition})]);
  if(writes.has(name))return success;
  const schema=schemas[name];if(!schema)throw new Error(`Missing result contract: ${name}`);return schema;
}
export function mutationResultSchemaFor(name:string):z.ZodType {
  return name==='jira_start_apply'?success:resultSchemaFor(name);
}
