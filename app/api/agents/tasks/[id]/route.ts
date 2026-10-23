import { getTask,updateTask,deleteTask,listActivity,listTasks } from '@/lib/agents/operations';
import { handle,browser,body,mutation,query } from '@/lib/agents/http';
type Context={params:Promise<{id:string}>};
export async function GET(request:Request,{params}:Context) { return handle(async()=>{const owner=await browser(request),{id}=await params;return {task:getTask(owner,id),activity:listActivity(owner,id,query(request)),subtasks:listTasks(owner,{parentTaskId:id,cursor:new URL(request.url).searchParams.get('subtaskCursor')??undefined})};}); }
export async function PATCH(request:Request,{params}:Context) { return handle(async()=>updateTask(await browser(request,'write'),(await params).id,await body(request),mutation(request))); }
export async function DELETE(request:Request,{params}:Context) { return handle(async()=>deleteTask(await browser(request,'write'),(await params).id,mutation(request)),204); }
