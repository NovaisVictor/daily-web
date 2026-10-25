import { transitionTask } from '@/lib/agents/operations';
import { handle,browser,body,mutation } from '@/lib/agents/http';
export async function POST(request:Request,{params}:{params:Promise<{id:string}>}) { return handle(async()=>transitionTask(await browser(request,'write'),(await params).id,await body(request),mutation(request),'owner')); }
