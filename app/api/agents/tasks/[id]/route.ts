import { getTask,updateTask,deleteTask,listActivity,listTasks } from '@/lib/agents/operations';
import { attachLive } from '@/lib/agents/deck';
import { handle,browser,body,mutation,query } from '@/lib/agents/http';
type Context={params:Promise<{id:string}>};
export async function GET(request:Request,{params}:Context) { return handle(async()=>{const owner=await browser(request),{id}=await params;const task=getTask(owner,id);const subtasks=listTasks(owner,{parentTaskId:id,cursor:new URL(request.url).searchParams.get('subtaskCursor')??undefined});const live=await attachLive(owner,{tasks:[task,...subtasks.items],sessions:[]});return {task:live.tasks[0],activity:listActivity(owner,id,query(request)),subtasks:{...subtasks,items:live.tasks.slice(1)}};}); }
export async function PATCH(request:Request,{params}:Context) { return handle(async()=>updateTask(await browser(request,'write'),(await params).id,await body(request),mutation(request))); }
export async function DELETE(request:Request,{params}:Context) { return handle(async()=>deleteTask(await browser(request,'write'),(await params).id,mutation(request)),204); }
