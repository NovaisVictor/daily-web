import { getSession } from '@/lib/agents/operations';
import { MESSAGE_MAX,sendMessage } from '@/lib/agents/deck';
import { externalMutation } from '@/lib/access/receipts';
import * as schema from '@/lib/agents/schemas';
import { handle,browser,body,mutation } from '@/lib/agents/http';
export async function POST(request:Request,{params}:{params:Promise<{id:string}>}) { return handle(async()=>{const owner=await browser(request,'write');const session=getSession(owner,(await params).id);const data=schema.object(await body(request),['text']);const text=schema.text(data.text,'message',MESSAGE_MAX);const ref={id:session.id,externalId:session.externalId,provider:session.agent.provider};return externalMutation(owner,'agents.sessions.message',{id:session.id,input:{text}},mutation(request),()=>sendMessage(owner,ref,text));},202); }
