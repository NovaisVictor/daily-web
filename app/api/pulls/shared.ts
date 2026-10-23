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
    const rerun=Number(partial.outcome.rerun??0);
    const failed=((partial.outcome.failed??[]) as {id:number;error:string}[]).map(item=>({id:item.id,error:'Não foi possível confirmar a reexecução no GitHub'}));
    if(rerun===0&&failed.length)return NextResponse.json({error:failed[0].error,failed},{status:502});
    return pullsWriteDone(userId,{rerun,failed});
  }
  if(error instanceof AccessError){
    if(error.code==='repository_limit')return NextResponse.json({error:'limite de 30 repositórios acompanhados — remova um antes de adicionar outro'},{status:400});
    const messages:Record<string,string>={
      draft_pull:'O PR ainda é um rascunho',
      self_review:'Você não pode revisar seu próprio PR',
      author_review:'O autor do PR não pode ser solicitado como revisor',
      state_changed:'O estado do PR mudou ou impede esta ação. Atualize o painel e confira os commits e as regras da branch antes de tentar novamente',
      uncertain_outcome:'Não foi possível confirmar a operação no GitHub. Confira o resultado antes de tentar novamente',
      provider_refused:'O GitHub recusou a operação; nenhuma alteração foi aceita',
      invalid_result:'O GitHub retornou uma resposta inesperada. Atualize o painel antes de tentar novamente',
      invalid_input:'Os dados da operação são inválidos',
      body_required:'Explique as mudanças solicitadas antes de enviar a revisão',
      invalid_reviewers:'Selecione revisores válidos',
      transition_unavailable:'Nenhuma transição correspondente está disponível no Jira',
      not_found:'A conexão ou o recurso não foi encontrado',
      module_disabled:'Ative o módulo nas configurações antes de continuar',
      invalid_identity:'Sua sessão expirou. Entre novamente',
      insufficient_scope:'Você não tem permissão para esta operação',
      ambiguous_auth:'Use a sessão do navegador para esta operação',
      invalid_origin:'Esta operação precisa ser iniciada neste painel',
      unsupported_operation:'Esta operação não está disponível',
      invalid_idempotency_key:'A identificação da operação é inválida. Atualize o painel e tente novamente',
      stale_request:'A solicitação expirou. Atualize o painel e tente novamente',
      idempotency_conflict:'Esta identificação já foi usada em outra operação. Atualize o painel e confira o resultado',
      receipt_expired:'Confira o resultado da operação anterior antes de iniciar outra',
      operation_pending:'A operação anterior ainda não foi concluída. Aguarde e confira o resultado',
    };
    const status=error.code==='uncertain_outcome'?502:error.status;
    return NextResponse.json({error:messages[error.code]??'Não foi possível confirmar a operação no GitHub',code:error.code,...(error.code==='uncertain_outcome'?{retry:'reconcile'}:{})},{status});
  }
  return NextResponse.json({error:'Não foi possível confirmar a operação no GitHub'},{status:502});
}
