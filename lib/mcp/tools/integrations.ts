import { z } from 'zod';
import type { McpServer } from '@modelcontextprotocol/server';
import type { Principal } from '@/lib/access/principal';
import { AccessError } from '@/lib/access/principal';
import { revalidatePrincipal } from '@/lib/mcp/auth';
import { githubOperations } from '@/lib/operations/github';
import { jiraOperations } from '@/lib/operations/jira';
import { taskOperations } from '@/lib/operations/tasks';
import { connectionOperations } from '@/lib/operations/connections';
import { focusOperations } from '@/lib/operations/focus';

export const integrationOperations=[...jiraOperations,...githubOperations,...taskOperations,...connectionOperations,...focusOperations];
export function registerIntegrationTools(server:McpServer,principal:Principal):void {
  for(const op of integrationOperations){
    if(!principal.scopes.includes(op.scope))continue;
    server.registerTool(op.name,{
      description:op.description,inputSchema:op.schema,
      outputSchema:z.object({result:op.resultSchema}),
      annotations:{readOnlyHint:op.mode==='read',destructiveHint:op.mode==='write',idempotentHint:op.mode==='read',openWorldHint:true},
    },async(args)=>{
      try{
        revalidatePrincipal(principal);
        const result=JSON.parse(JSON.stringify(await op.run(principal,args))) as z.infer<ReturnType<typeof z.json>>;
        return {content:[{type:'text' as const,text:JSON.stringify(result)}],structuredContent:{result}};
      }catch(error){
        const known=error instanceof AccessError;
        const result={code:known?error.code:'operation_failed',message:known?error.message:'The operation could not be completed',retry:known&&error.code==='uncertain_outcome'?'reconcile':'correct_request'};
        return {isError:true,content:[{type:'text' as const,text:JSON.stringify(result)}]};
      }
    });
  }
}
