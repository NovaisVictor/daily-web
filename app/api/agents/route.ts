import { listTasks,listSessions } from '@/lib/agents/operations';
import { handle,browser,query } from '@/lib/agents/http';
export async function GET(request:Request) { return handle(async()=>{const owner=await browser(request);const options=query(request);const sessionsView=new URL(request.url).searchParams.get('tab')==='sessions';return {tasks:listTasks(owner,sessionsView?{}:options),sessions:listSessions(owner,sessionsView?options:{})};}); }
