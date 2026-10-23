import { z } from 'zod';
import { operation, mutationShape, pageShape, page, connection, mutate } from './context';
import { AccessError } from '@/lib/access/principal';
import { ExternalPartialOutcome, localMutation } from '@/lib/access/receipts';
import type { EditTaskInput } from '@/lib/tasks/types';
import type { ProviderTask } from '@/lib/types';
import * as local from '@/lib/tasks/local';
import * as mstodo from '@/lib/cli/mstodo';
import { withBoardOverlay, markDoing, clearBoardStatus } from '@/lib/tasks/boardStatus';
import { setBoardStyle, clearBoardStyle, type BoardStylePatch } from '@/lib/tasks/boardStyle';
import { NOTE_PAPERS, PIN_COLORS } from '@/lib/taskBoard';
import { dropCache } from '@/lib/refresher';
import { isValidTaskId, isSafePositionalValue } from '@/lib/api/validation';
import { isCalendarDate } from '@/lib/integrations/jira/parse';
import { groupTasksByDueWindow } from '@/lib/taskGrouping';
import type { Principal } from '@/lib/access/principal';

const sourceShape={provider:z.enum(['local','mstodo']),connectionId:z.string().min(1).optional()};
const taskShape={...sourceShape,id:z.string().refine(isValidTaskId)};
const title=z.string().trim().min(1).max(500).refine(isSafePositionalValue);
const boardStyleSchema=z.object({paper:z.enum(NOTE_PAPERS).nullable().optional(),pin:z.enum(PIN_COLORS).nullable().optional()}).strict().refine(value=>value.paper!==undefined||value.pin!==undefined);
const metadataShape={
  due:z.string().refine(value=>value===''||isCalendarDate(value)).optional(),
  time:z.string().regex(/^(|([01]\d|2[0-3]):[0-5]\d)$/).optional(),
  priority:z.enum(['low','normal','high']).optional(),
  recur:z.enum(['none','daily','weekly','monthly','']).optional(),
};
type TaskMetadata=z.infer<z.ZodObject<typeof metadataShape>>;
function metadataEdit(input:TaskMetadata,task:ProviderTask|null):EditTaskInput {
  const due=input.due??task?.due??'';
  const time=input.time??task?.time??'';
  const recur=input.recur??task?.recur??'';
  if(!due&&(time||recur&&recur!=='none'))throw new AccessError(400,'invalid_input','A time or repeating task requires a due date');
  return {due:input.due===''?'none':input.due,time:input.time===''?'none':input.time,priority:input.priority,recur:input.recur};
}

function source(p:Principal,i:{provider:'local'|'mstodo';connectionId?:string}) {
  if(i.provider==='local')return null;
  if(!i.connectionId)throw new AccessError(400,'connection_required','Choose a task connection');
  const conn=connection(p,i.connectionId,'tasks',p.scopes.includes('tasks:write')?'tasks:write':'tasks:read');
  if(conn.values.provider!=='mstodo')throw new AccessError(400,'provider_mismatch','This connection is not Microsoft To Do');
  return {DAILY_TUI_TODO_CLIENT_ID:conn.values.clientId??'',DAILY_TUI_TODO_LIST:conn.values.list??''};
}
async function list(p:Principal,i:z.infer<z.ZodObject<typeof sourceShape>>) {
  const env=source(p,i);return withBoardOverlay(p.userId,env?await mstodo.fetchTasks(env):local.listTasks(p.userId));
}
export async function readPersonalTask(p:Principal,i:z.infer<z.ZodObject<typeof taskShape>>) {
  const tasks=await list(p,i);const task=tasks.find(t=>t.id===i.id);if(!task)throw new AccessError(404,'not_found','Task not found');return task;
}
type PersonalWrite = z.infer<z.ZodObject<typeof sourceShape>> & {id?:string;operationId:string;requestedAt:string};
async function writePersonal<T extends Record<string,unknown>>(
  p:Principal,input:PersonalWrite,name:string,
  writeLocal:(task:ProviderTask|null)=>T,
  writeRemote:(env:NonNullable<ReturnType<typeof source>>,task:ProviderTask|null)=>Promise<T>,
):Promise<T> {
  const env=source(p,input);
  const resource={id:input.id??input.provider,connectionId:input.connectionId,input};
  const mutation={key:input.operationId,requestedAt:input.requestedAt};
  if(!env){
    return localMutation(p.userId,name,resource,mutation,()=>{
      const task=input.id?local.listTasks(p.userId).find(item=>item.id===input.id)??null:null;
      if(input.id&&!task)throw new AccessError(404,'not_found','Task not found');
      const result=writeLocal(task);dropCache(p.userId);return result;
    });
  }
  return mutate(p,name,resource,input,async()=>{
    const task=input.id?await readPersonalTask(p,{...input,id:input.id}):null;
    const result=await writeRemote(env,task);dropCache(p.userId);return result;
  });
}
async function writeStyle(p:Principal,input:PersonalWrite&{id:string;boardStyle:BoardStylePatch}) {
  const env=source(p,input);
  if(env)await readPersonalTask(p,{...input,id:input.id});
  return localMutation(p.userId,'tasks_edit',{id:input.id,connectionId:input.connectionId,input},{key:input.operationId,requestedAt:input.requestedAt},()=>{
    if(!env&&!local.listTasks(p.userId).some(task=>task.id===input.id))throw new AccessError(404,'not_found','Task not found');
    setBoardStyle(p.userId,input.id,input.boardStyle);dropCache(p.userId);return {ok:true};
  });
}
export const taskOperations=[
  operation('tasks_list','List personal tasks from an explicit local or Microsoft To Do source','tasks:read','read',{...sourceShape,...pageShape,query:z.string().max(200).default(''),status:z.enum(['all','todo','doing','done']).default('all'),priority:z.enum(['all','low','normal','high']).default('all'),dueWindow:z.enum(['all','overdue','today','week','month','later','noDate']).default('all'),groupBy:z.enum(['none','due']).default('none')},async(p,i)=>{
    let items=(await list(p,i)).filter(t=>(!i.query||t.title.toLowerCase().includes(i.query.toLowerCase()))&&(i.priority==='all'||i.priority===t.priority)&&(i.status==='all'||(i.status==='done'?t.completed:i.status==='doing'?!t.completed&&t.doing:!t.completed&&!t.doing)));
    if(i.dueWindow!=='all')items=groupTasksByDueWindow(items).find(g=>g.key===i.dueWindow)?.tasks??[];
    const result=page(items,i,t=>t.id);
    return i.groupBy==='due'?{...result,groups:groupTasksByDueWindow(result.items)}:result;
  }),
  operation('tasks_get','Read a personal task and its subtasks','tasks:read','read',taskShape,async(p,i)=>({task:await readPersonalTask(p,i)})),
  operation('tasks_create','Create a personal task with optional scheduling, priority and recurrence','tasks:write','write',{...sourceShape,...mutationShape,title,...metadataShape,boardStyle:boardStyleSchema.optional(),status:z.enum(['todo','doing']).default('todo')},async(p,i)=>{
    const edit=metadataEdit(i,null);
    const metadataFields=Object.values(edit).filter(value=>value!==undefined);
    return writePersonal(p,i,'tasks_create',()=>{
      const id=local.addTask(p.userId,i.title);
      if(metadataFields.length)local.editTask(p.userId,id,edit);
      if(i.status==='doing')markDoing(p.userId,id);
      if(i.boardStyle)setBoardStyle(p.userId,id,i.boardStyle);
      return {ok:true,id};
    },async env=>{
      const id:unknown=await mstodo.addTask(env,i.title);
      if(!isValidTaskId(id))throw new ExternalPartialOutcome({code:'created_task_unidentified'});
      if(metadataFields.length){
        try{await mstodo.editTask(env,id,edit);}
        catch{throw new ExternalPartialOutcome({id,code:'task_metadata_unconfirmed'});}
      }
      if(i.status==='doing'){
        try{markDoing(p.userId,id);}
        catch{throw new ExternalPartialOutcome({id,code:'task_board_unconfirmed'});}
      }
      if(i.boardStyle){
        try{setBoardStyle(p.userId,id,i.boardStyle);}
        catch{throw new ExternalPartialOutcome({id,code:'task_style_unconfirmed'});}
      }
      return {ok:true,id};
    });
  }),
  operation('tasks_edit','Edit task details or the note paper and pin colours','tasks:write','write',{...taskShape,...mutationShape,title:title.optional(),...metadataShape,boardStyle:boardStyleSchema.optional()},async(p,i)=>{
    const details={title:i.title,due:i.due,time:i.time,priority:i.priority,recur:i.recur};
    if(i.boardStyle&&Object.values(details).every(value=>value===undefined))return writeStyle(p,{...i,boardStyle:i.boardStyle});
    const edit=(task:ProviderTask|null)=>({...metadataEdit(i,task),title:i.title});
    return writePersonal(p,i,'tasks_edit',task=>{
      local.editTask(p.userId,i.id,edit(task));
      if(i.boardStyle)setBoardStyle(p.userId,i.id,i.boardStyle);
      return {ok:true};
    },async(env,task)=>{
      await mstodo.editTask(env,i.id,edit(task));
      if(i.boardStyle){
        try{setBoardStyle(p.userId,i.id,i.boardStyle);}
        catch{throw new ExternalPartialOutcome({id:i.id,code:'task_style_unconfirmed'});}
      }
      return {ok:true};
    });
  }),
  operation('tasks_transition','Complete, reopen, or move a personal task on its board','tasks:write','write',{...taskShape,...mutationShape,status:z.enum(['todo','doing','done'])},async(p,i)=>{
    const board=()=>{if(i.status==='doing')markDoing(p.userId,i.id);else clearBoardStatus(p.userId,i.id);};
    return writePersonal(p,i,'tasks_transition',()=>{
      local.setCompleted(p.userId,i.id,i.status==='done');board();return {ok:true};
    },async(env,task)=>{
      if(i.status==='done')await mstodo.completeTask(env,i.id);
      else if(task!.completed)await mstodo.reopenTask(env,i.id);
      board();return {ok:true};
    });
  }),
  operation('tasks_delete','Delete a personal task','tasks:write','write',{...taskShape,...mutationShape},async(p,i)=>
    writePersonal(p,i,'tasks_delete',()=>{local.deleteTask(p.userId,i.id);clearBoardStatus(p.userId,i.id);clearBoardStyle(p.userId,i.id);return {ok:true};},async env=>{await mstodo.deleteTask(env,i.id);clearBoardStatus(p.userId,i.id);clearBoardStyle(p.userId,i.id);return {ok:true};})),
  operation('tasks_subtask_create','Add a subtask','tasks:write','write',{...taskShape,...mutationShape,title},async(p,i)=>
    writePersonal(p,i,'tasks_subtask_create',()=>{local.addSubtask(p.userId,i.id,i.title);return {ok:true};},async env=>{await mstodo.addSubtask(env,i.id,i.title);return {ok:true};})),
  operation('tasks_subtask_edit','Edit, complete, reopen or remove a subtask','tasks:write','write',{...taskShape,...mutationShape,itemId:z.string().refine(isValidTaskId),action:z.enum(['edit','complete','reopen','delete']),title:title.optional()},async(p,i)=>{
    if(i.action==='edit'&&!i.title)throw new AccessError(400,'title_required','Provide a subtask title');
    const owned=(task:ProviderTask|null)=>{if(!task?.subtasks.some(item=>item.id===i.itemId))throw new AccessError(404,'not_found','Subtask not found');};
    return writePersonal(p,i,'tasks_subtask_edit',task=>{
      owned(task);
      if(i.action==='delete')local.deleteSubtask(p.userId,i.id,i.itemId);
      else if(i.action==='edit')local.editSubtask(p.userId,i.id,i.itemId,i.title!);
      else local.checkSubtask(p.userId,i.id,i.itemId,i.action==='complete');
      return {ok:true};
    },async(env,task)=>{
      owned(task);
      if(i.action==='delete')await mstodo.deleteSubtask(env,i.id,i.itemId);
      else if(i.action==='edit')await mstodo.editSubtask(env,i.id,i.itemId,i.title!);
      else await mstodo.checkSubtask(env,i.id,i.itemId,i.action==='complete');
      return {ok:true};
    });
  }),
];
