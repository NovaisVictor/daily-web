// @vitest-environment node
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { randomBytes, randomUUID } from 'node:crypto';
import type { McpServer } from '@modelcontextprotocol/server';
import { createUser } from '@/lib/auth/users';
import { getDb } from '@/lib/db';
import { OAuthStore } from '@/lib/oauth/adapter';
import { revokeGrant } from '@/lib/access/grants';
import type { McpPrincipal } from '@/lib/mcp/auth';
import { registerIntegrationTools } from '@/lib/mcp/tools/integrations';
import { saveConnection, setModuleEnabled } from '@/lib/vault/connections';
import captured from '@/tests/fixtures/github/operation-contracts.json';
import runs from '@/tests/fixtures/github/actions-runs.json';

interface Reply {isError?:boolean;content:{type:string;text:string}[];structuredContent?:{result:Record<string,unknown>}}
let dir:string,principal:McpPrincipal,connectionId:string;
const reply=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status});
const mutation=()=>({operationId:randomUUID(),requestedAt:new Date().toISOString()});
function tools(p=principal){
  const callbacks=new Map<string,(input:Record<string,unknown>)=>Promise<Reply>>();
  registerIntegrationTools({registerTool:(name:string,_config:unknown,callback:(input:Record<string,unknown>)=>Promise<Reply>)=>callbacks.set(name,callback)} as unknown as McpServer,p);
  return callbacks;
}
beforeEach(async()=>{
  dir=mkdtempSync(path.join(tmpdir(),'daily-mcp-github-'));
  vi.stubEnv('DAILY_WEB_DB_PATH',path.join(dir,'db.sqlite'));vi.stubEnv('DAILY_WEB_SECRET_KEY',randomBytes(32).toString('base64'));
  const user=await createUser('github-client',randomBytes(32).toString('hex'));
  principal={userId:user.id,kind:'oauth',grantId:'github-grant',scopes:['github:read','github:write']};
  new OAuthStore(getDb()).put('Grant',principal.grantId,{accountId:user.id,clientId:'test-client'});
  connectionId=saveConnection(user.id,'pulls','GitHub',{token:randomBytes(32).toString('hex'),repos:'acme/repo-4'});setModuleEnabled(user.id,'pulls',true);
});
afterEach(()=>{vi.restoreAllMocks();vi.unstubAllGlobals();vi.unstubAllEnvs();rmSync(dir,{recursive:true,force:true});});

describe('GitHub MCP adapter',()=>{
  it('advertises only consented GitHub capabilities and validates unknown input without contacting the provider',async()=>{
    const read=tools({...principal,scopes:['github:read']});expect(read.has('github_work')).toBe(true);expect(read.has('github_comment')).toBe(false);
    const fetch=vi.fn();vi.stubGlobal('fetch',fetch);
    const rejected=await tools().get('github_comment')!({connectionId,owner:'acme',repo:'repo-4',number:42,body:'Test comment',...mutation(),token:'forbidden-field'});
    expect(rejected.isError).toBe(true);expect(JSON.parse(rejected.content[0].text).code).toBe('invalid_input');expect(fetch).not.toHaveBeenCalled();
  });
  it('replays a confirmed comment result and checks live grant revocation before the next tool call',async()=>{
    const fetch=vi.fn().mockResolvedValue(reply(captured.comment,201));vi.stubGlobal('fetch',fetch);
    const comment=tools().get('github_comment')!;
    const input={connectionId,owner:'acme',repo:'repo-4',number:42,body:'Test comment',...mutation()};
    const result=await comment(input);expect(result.isError).not.toBe(true);expect(result.structuredContent?.result).toMatchObject({id:captured.comment.id,url:captured.comment.html_url});
    expect(await comment(input)).toEqual(result);expect(fetch).toHaveBeenCalledTimes(1);
    revokeGrant(principal.userId,principal.grantId);
    const denied=await comment({...input,...mutation()});expect(denied.isError).toBe(true);expect(JSON.parse(denied.content[0].text).code).toBe('invalid_token');expect(fetch).toHaveBeenCalledTimes(1);
  });
  it('exposes partial provider effects as an uncertain error and never retries accepted jobs',async()=>{
    const [first,second]=runs['acme/repo-4'].workflow_runs;
    const responses=[reply(captured.pull),reply({workflow_runs:[first,second]}),reply({},201),reply(captured.refusal.response,403)];
    const fetch=vi.fn();responses.forEach(response=>fetch.mockResolvedValueOnce(response));vi.stubGlobal('fetch',fetch);
    const run=tools().get('github_rerun')!,input={connectionId,owner:'acme',repo:'repo-4',number:42,headSha:captured.pull.head.sha,...mutation()};
    const outcomes:unknown[]=[];
    for(let attempt=0;attempt<2;attempt++){
      const result=await run(input);expect(result.isError).toBe(true);expect(result.structuredContent).toBeUndefined();
      const outcome=JSON.parse(result.content[0].text);outcomes.push(outcome);
      expect(outcome).toMatchObject({code:'uncertain_outcome',retry:'reconcile',partialOutcome:{number:1,rerun:1,complete:false,failed:[{id:second.id,error:'The provider outcome was not confirmed'}]}});
      expect(JSON.stringify(result)).not.toContain(captured.refusal.response.message);
    }
    expect(outcomes[1]).toEqual(outcomes[0]);
    expect(fetch).toHaveBeenCalledTimes(4);
  });
  it('denies a foreign connection and missing cross-provider permission without leaking source data',async()=>{
    const other=await createUser('other-client',randomBytes(32).toString('hex'));
    const foreign=saveConnection(other.id,'pulls','Private connection',{token:randomBytes(32).toString('hex')});
    const network=vi.fn();vi.stubGlobal('fetch',network);
    const result=await tools().get('github_repositories')!({connectionId:foreign});expect(result.isError).toBe(true);expect(JSON.parse(result.content[0].text).code).toBe('not_found');expect(JSON.stringify(result)).not.toContain('Private connection');
    expect(network).not.toHaveBeenCalled();
  });
});
