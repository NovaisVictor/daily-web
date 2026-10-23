import { reportActivity, listActivity } from '@/lib/agents/operations';
import { handle, reporting, body, mutation, query } from '@/lib/agents/http';
type Context={params:Promise<{id:string}>};
export async function POST(request:Request,{params}:Context) { return handle(async()=>reportActivity(reporting(request,'agents:write'),(await params).id,await body(request),mutation(request))); }
export async function GET(request:Request,{params}:Context) { return handle(async()=>listActivity(reporting(request,'agents:read'),(await params).id,query(request))); }
