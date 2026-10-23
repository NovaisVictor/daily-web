import { z } from 'zod';
import type { McpServer, StandardSchemaWithJSON } from '@modelcontextprotocol/server';
import { AccessError,requireScope,type Principal } from '@/lib/access/principal';
import { revalidatePrincipal } from './auth';
export function registerTool<S extends z.ZodObject>(server:McpServer,principal:Principal,name:string,scope:string,schema:S,mode:'read'|'write',run:(args:z.infer<S>)=>unknown,output:z.ZodType){
 if(!principal.scopes.includes(scope))return;
 server.registerTool<StandardSchemaWithJSON,StandardSchemaWithJSON>(name,{description:name.replaceAll('_',' '),inputSchema:schema as StandardSchemaWithJSON,outputSchema:z.object({result:output}),annotations:{readOnlyHint:mode==='read',destructiveHint:mode==='write',idempotentHint:true,openWorldHint:false}},async(args)=>{
  try{
   requireScope(principal,scope);
   revalidatePrincipal(principal);
   const value=await run(schema.parse(args));const result=output.parse(value??null);return {content:[{type:'text' as const,text:JSON.stringify(result)}],structuredContent:{result}};
  }catch(error){const known=error instanceof AccessError;return {isError:true,content:[{type:'text' as const,text:JSON.stringify({code:known?error.code:'operation_failed',message:known?error.message:'Operation failed',retry:known&&error.status===409?'reload':'correct_request'})}]};}
 });
}
