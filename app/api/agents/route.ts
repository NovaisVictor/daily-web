import { listTasks,listSessions,summarizeSubtasks } from '@/lib/agents/operations';
import { attachLive } from '@/lib/agents/deck';
import { handle,browser,query } from '@/lib/agents/http';
export async function GET(request:Request) { return handle(async()=>{const owner=await browser(request);const options=query(request);const sessionsView=new URL(request.url).searchParams.get('tab')==='sessions';const tasks=listTasks(owner,sessionsView?{}:options);const sessions=listSessions(owner,sessionsView?options:{});const live=await attachLive(owner,{tasks:tasks.items,sessions:sessions.items});return {tasks:{...tasks,items:live.tasks},sessions:{...sessions,items:live.sessions},subtaskProgress:summarizeSubtasks(owner,tasks.items.filter(task=>task.parentTaskId===null).map(task=>task.id))};}); }
