import { NextRequest, NextResponse } from 'next/server';
import { requireUser } from '@/lib/api/context';
import { isValidRepo } from '@/lib/api/validation';
import { listConnections } from '@/lib/vault/connections';
import { pullOperationError, runPullOperation } from '../shared';

export async function GET() {
  const auth=await requireUser();
  if(!auth.ok)return auth.response;
  const connection=listConnections(auth.value.id,'pulls')[0];
  if(!connection)return NextResponse.json({repos:[]});
  try {
    const result=await runPullOperation(new Request('http://localhost/api/pulls/repos'),{user:auth.value,connection},'github_repositories',{});
    return NextResponse.json({repos:result.repositories});
  } catch(error){return pullOperationError(error,auth.value.id);}
}

async function change(request:NextRequest,action:'add'|'remove') {
  const auth=await requireUser();
  if(!auth.ok)return auth.response;
  const body=await request.json().catch(()=>null);
  if(!isValidRepo(body?.repo))return NextResponse.json({error:'repositório inválido (use owner/nome)'},{status:400});
  const connection=listConnections(auth.value.id,'pulls')[0];
  if(!connection)return NextResponse.json({error:'configure o token do GitHub antes de escolher repositórios'},{status:409});
  const ctx={user:auth.value,connection};
  try {
    await runPullOperation(request,ctx,`github_repository_${action}`,{repo:body.repo});
    const result=await runPullOperation(new Request(request.url),ctx,'github_repositories',{});
    return NextResponse.json({repos:result.repositories});
  } catch(error){return pullOperationError(error,auth.value.id);}
}
export function POST(request:NextRequest){return change(request,'add');}
export function DELETE(request:NextRequest){return change(request,'remove');}
