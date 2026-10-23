import { getTask, updateTask, deleteTask } from '@/lib/agents/operations';
import { handle, reporting, body, mutation } from '@/lib/agents/http';
type Context={params:Promise<{id:string}>};
export async function GET(request:Request,{params}:Context) { return handle(async()=>getTask(reporting(request,'agents:read'),(await params).id)); }
export async function PATCH(request:Request,{params}:Context) { return handle(async()=>updateTask(reporting(request,'agents:write'),(await params).id,await body(request),mutation(request))); }
export async function DELETE(request:Request,{params}:Context) { return handle(async()=>deleteTask(reporting(request,'agents:write'),(await params).id,mutation(request)),204); }
