import { randomUUID } from 'node:crypto';
import { NextResponse } from 'next/server';
import { type ConnectionContext } from '@/lib/api/context';
import { AccessError } from '@/lib/access/principal';
import { ExternalPartialOutcome } from '@/lib/access/receipts';
import { runGithubOperation, githubOperations } from '@/lib/operations/github';
import { pullsWriteDone } from '@/lib/api/pulls';

export async function runPullOperation(request:Request,ctx:ConnectionContext,name:string,input:Record<string,unknown>) {
  const expected=process.env.PUBLIC_ORIGIN?new URL(process.env.PUBLIC_ORIGIN).origin:new URL(request.url).origin;
  const origin=request.headers.get('origin');
  if(request.headers.has('authorization'))throw new AccessError(400,'ambiguous_auth','Use the browser session for this action');
  if(origin&&origin!==expected)throw new AccessError(403,'invalid_origin','Same-origin browser request required');
  const selected=githubOperations.find(item=>item.name===name);
  const mutation=selected?.mode==='write'?{operationId:request.headers.get('idempotency-key')??randomUUID(),requestedAt:request.headers.get('x-request-timestamp')??new Date().toISOString()}:{};
  return runGithubOperation({userId:ctx.user.id,kind:'browser',scopes:['github:read','github:write']},name,{...input,connectionId:ctx.connection.id,...mutation});
}

export function pullOperationError(error:unknown,userId:string):NextResponse {
  const partial=error instanceof ExternalPartialOutcome?error:error instanceof Error&&error.cause instanceof ExternalPartialOutcome?error.cause:null;
  if(partial){
    const rerun=Number(partial.outcome.rerun??0),failed=partial.outcome.failed as {id:number;error:string}[];
    if(rerun===0&&failed.length)return NextResponse.json({error:failed[0].error,failed},{status:502});
    return pullsWriteDone(userId,{rerun,failed});
  }
  if(error instanceof AccessError){
    if(error.code==='repository_limit')return NextResponse.json({error:'limite de 30 repositórios acompanhados — remova um antes de adicionar outro'},{status:400});
    const status=error.code==='uncertain_outcome'?502:error.status;
    return NextResponse.json({error:error.message,code:error.code,...(error.code==='uncertain_outcome'?{retry:'reconcile'}:{})},{status});
  }
  return NextResponse.json({error:'Não foi possível confirmar a operação no GitHub'},{status:502});
}
