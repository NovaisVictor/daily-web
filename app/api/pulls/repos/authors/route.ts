import { NextRequest, NextResponse } from 'next/server';
import { requireUser } from '@/lib/api/context';
import { isValidRepo } from '@/lib/api/validation';
import { listConnections } from '@/lib/vault/connections';
import { pullOperationError, runPullOperation } from '../../shared';

export async function PUT(request:NextRequest) {
  const auth=await requireUser();
  if(!auth.ok)return auth.response;
  const body=await request.json().catch(()=>null);
  if(!isValidRepo(body?.repo))return NextResponse.json({error:'repositório inválido (use owner/nome)'},{status:400});
  if(!Array.isArray(body?.authors))return NextResponse.json({error:'lista de autores inválida'},{status:400});
  const connection=listConnections(auth.value.id,'pulls')[0];
  if(!connection)return NextResponse.json({error:'configure o token do GitHub antes de escolher autores'},{status:409});
  const ctx={user:auth.value,connection};
  try {
    await runPullOperation(request,ctx,'github_repository_authors',{repo:body.repo,authors:body.authors});
    const result=await runPullOperation(new Request(request.url),ctx,'github_repositories',{});
    return NextResponse.json({repos:result.repositories,authors:result.authors});
  } catch(error){return pullOperationError(error,auth.value.id);}
}
