import { getSession } from '@/lib/agents/operations';
import { handle, reporting } from '@/lib/agents/http';
export async function GET(request:Request,{params}:{params:Promise<{id:string}>}) { return handle(async()=>getSession(reporting(request,'agents:read'),(await params).id)); }
