import { registerAgent } from '@/lib/agents/operations';
import { handle, reporting, body, mutation } from '@/lib/agents/http';
export async function POST(request:Request) { return handle(async()=>registerAgent(reporting(request,'agents:write'),await body(request),mutation(request)),201); }
