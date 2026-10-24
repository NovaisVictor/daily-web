import { getSession } from '@/lib/agents/operations';
import { terminal } from '@/lib/agents/deck';
import { handle,browser } from '@/lib/agents/http';
export async function GET(request:Request,{params}:{params:Promise<{id:string}>}) { return handle(async()=>{const owner=await browser(request);const session=getSession(owner,(await params).id);return terminal(owner,{id:session.id,externalId:session.externalId,provider:session.agent.provider});}); }
