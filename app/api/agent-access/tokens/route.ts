import { createCredential,listCredentials } from '@/lib/access/credentials';
import { handle,browser,body } from '@/lib/agents/http';
export async function GET(request:Request) { return handle(async()=>({items:listCredentials(await browser(request))})); }
export async function POST(request:Request) { return handle(async()=>createCredential(await browser(request,'write'),await body(request)),201); }
