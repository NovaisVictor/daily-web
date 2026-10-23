import { listTasks,listSessions,summarizeSubtasks } from '@/lib/agents/operations';
import { handle,browser,query } from '@/lib/agents/http';
export async function GET(request:Request) { return handle(async()=>{const owner=await browser(request);const options=query(request);const sessionsView=new URL(request.url).searchParams.get('tab')==='sessions';const tasks=listTasks(owner,sessionsView?{}:options);return {tasks,sessions:listSessions(owner,sessionsView?options:{}),subtaskProgress:summarizeSubtasks(owner,tasks.items.filter(task=>task.parentTaskId===null).map(task=>task.id))};}); }
