import { createTask, listTasks } from '@/lib/agents/operations';
import { handle, reporting, body, mutation, query } from '@/lib/agents/http';
export async function POST(request:Request) { return handle(async()=>createTask(reporting(request,'agents:write'),await body(request),mutation(request)),201); }
export async function GET(request:Request) { return handle(()=>listTasks(reporting(request,'agents:read'),query(request))); }
