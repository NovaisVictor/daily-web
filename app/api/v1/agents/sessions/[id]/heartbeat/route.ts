import { heartbeatSession } from '@/lib/agents/operations';
import { handle, reporting, body, mutation } from '@/lib/agents/http';
export async function POST(request:Request,{params}:{params:Promise<{id:string}>}) { return handle(async()=>heartbeatSession(reporting(request,'agents:write'),(await params).id,await body(request),mutation(request))); }
