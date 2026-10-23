import { body as readBody } from '@/lib/agents/http';
import { createMcpHandler, McpServer } from '@modelcontextprotocol/server';
import { registerIntegrationTools } from './tools/integrations';
import { registerAgentTools } from './tools/agents';
import { authenticateMcp,oauthError } from './auth';
let activeRequests=0;
export async function handleMcp(request:Request):Promise<Response> {
 if(activeRequests>=32)return Response.json({error:'server_busy'},{status:429,headers:{'Retry-After':'1'}});
 activeRequests++;
 try{
  const principal=await authenticateMcp(request);
  const length=Number(request.headers.get('content-length')??0);if(length>65536)return Response.json({error:'payload_too_large'},{status:413});
  let safeRequest=request;
  if(request.method==='POST'){
   const data=await readBody(request);const headers=new Headers(request.headers);headers.delete('content-length');
   safeRequest=new Request(request.url,{method:request.method,headers,body:JSON.stringify(data)});
  }
  const handler=createMcpHandler(()=>{const server=new McpServer({name:'daily-web',version:'1.0.0'});registerAgentTools(server,principal);registerIntegrationTools(server,principal);return server;});
  const response=await handler.fetch(safeRequest);response.headers.set('Cache-Control','no-store');return response;
 }catch(error){return oauthError(error);}finally{activeRequests--;}
}
