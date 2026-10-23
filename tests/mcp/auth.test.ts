// @vitest-environment node
import { afterEach,beforeEach,describe,expect,it } from 'vitest';
import { mkdtempSync,rmSync,lstatSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { randomBytes } from 'node:crypto';
import { request as httpRequest,type Server } from 'node:http';
import { getDb } from '../../lib/db';
import { OAuthStore } from '../../lib/oauth/adapter';
import { createProvider } from '../../lib/oauth/provider';
import { startInternal } from '../../lib/oauth/runtime';
import { oauthInternal } from '../../lib/oauth/interaction';
import { authenticateMcp,revalidatePrincipal } from '../../lib/mcp/auth';
import { handleMcp } from '../../lib/mcp/server';
import { encrypt,decrypt } from '../../lib/vault/crypto';
import { listGrants,revokeGrant } from '../../lib/access/grants';
let dir:string;let socket:Server;let store:OAuthStore;let provider:ReturnType<typeof createProvider>;
const environment={...process.env};
beforeEach(async()=>{
 dir=mkdtempSync(join(tmpdir(),'daily-oauth-auth-'));
 process.env.DAILY_WEB_DB_PATH=join(dir,'db');process.env.DAILY_WEB_SECRET_KEY=randomBytes(32).toString('base64');process.env.PUBLIC_ORIGIN='http://127.0.0.1:8089';delete process.env.DAILY_WEB_ORIGIN;process.env.DAILY_WEB_OAUTH_RUNTIME_DIR=dir;process.env.DAILY_WEB_OAUTH_SOCKET=join(dir,'oauth.sock');
 const db=getDb();for(const id of ['owner-a','owner-b'])db.prepare('INSERT INTO users(id,username,password_hash,is_admin,created_at) VALUES(?,?,?,?,?)').run(id,id,'unused',0,new Date().toISOString());
 store=new OAuthStore(db);provider=createProvider(store,[{client_id:'client',client_name:'Test client',application_type:'native',redirect_uris:['http://127.0.0.1/callback'],response_types:['code'],grant_types:['authorization_code','refresh_token'],token_endpoint_auth_method:'none'}]);
 socket=await startInternal(provider,store);
});
afterEach(async()=>{await new Promise<void>(resolve=>socket.close(()=>resolve()));rmSync(dir,{recursive:true,force:true});process.env={...environment};});
async function access(audience='http://127.0.0.1:8089/mcp',scope='agents:read'){
 const client=await provider.Client.find('client');if(!client)throw new Error('Missing test client');
 const grant=new provider.Grant({accountId:'owner-a',clientId:'client'});grant.addResourceScope(audience,scope);const grantId=await grant.save();
 const token=await new provider.AccessToken({client,accountId:'owner-a',aud:audience,scope,grantId,gty:'authorization_code'}).save();return {token,grantId};
}
describe('OAuth isolation and transport',()=>{
 it('encrypts persisted payloads with separate purpose while retaining legacy vault support',()=>{
  const legacy=encrypt('legacy');expect(decrypt(legacy)).toBe('legacy');
  const separate=encrypt('oauth-secret','oauth-provider-v1');expect(()=>decrypt(separate)).toThrow();expect(()=>decrypt(legacy,'oauth-provider-v1')).toThrow();
  store.put('Test','record',{clientId:'sensitive-value'});const row=store.db.prepare("SELECT jsn_payload FROM main.tb_oauth_record WHERE typ_kind='Test'").get() as {jsn_payload:string};expect(row.jsn_payload).not.toContain('sensitive-value');expect(store.get('Test','record')?.clientId).toBe('sensitive-value');
 });
 it('consumes a code atomically and revokes its grant on concurrent reuse',async()=>{
  store.put('Grant','race-grant',{accountId:'owner-a'});
  store.put('AuthorizationCode','race-code',{accountId:'owner-a',grantId:'race-grant',exp:Math.floor(Date.now()/1000)+60});
  const adapter=store.adapter('AuthorizationCode');
  const results=await Promise.allSettled([adapter.consume('race-code'),adapter.consume('race-code')]);
  expect(results.filter(result=>result.status==='fulfilled')).toHaveLength(1);expect(results.filter(result=>result.status==='rejected')).toHaveLength(1);expect(store.get('Grant','race-grant')).toBeUndefined();
 });
 it('uses a private socket and rejects invalid, foreign-audience and revoked tokens immediately',async()=>{
  expect(lstatSync(process.env.DAILY_WEB_OAUTH_SOCKET!).mode&0o777).toBe(0o600);
  const {token,grantId}=await access();const request=()=>new Request('http://127.0.0.1:8089/mcp',{headers:{Authorization:`Bearer ${token}`}});
  const principal=await authenticateMcp(request());expect(principal.userId).toBe('owner-a');expect(listGrants('owner-b')).toHaveLength(0);expect(()=>revokeGrant('owner-b',grantId)).toThrow();
  expect(await oauthInternal('introspect',{token:'invalid'})).toEqual({active:false});
  const foreign=await access('http://other.invalid/mcp');await expect(authenticateMcp(new Request(request().url,{headers:{Authorization:`Bearer ${foreign.token}`}}))).rejects.toThrow();
  revokeGrant('owner-a',grantId);await expect(authenticateMcp(request())).rejects.toThrow();expect(()=>revalidatePrincipal(principal)).toThrow();
 });
 it('authenticates each MCP request without cookies and advertises only consented tools',async()=>{
  const {token}=await access();const call=(method:string,params:unknown={})=>handleMcp(new Request('http://127.0.0.1:8089/mcp',{method:'POST',headers:{Authorization:`Bearer ${token}`,'Content-Type':'application/json',Accept:'application/json, text/event-stream'},body:JSON.stringify({jsonrpc:'2.0',id:1,method,params})}));
  const response=await call('tools/list');expect(response.status).toBe(200);const text=await response.text();expect(text).toContain('agents_sessions_list');expect(text).not.toContain('agents_tasks_create');expect(text).not.toContain('jira_');
  const missing=await handleMcp(new Request('http://127.0.0.1:8089/mcp'));expect(missing.status).toBe(401);expect(missing.headers.get('www-authenticate')).toContain('oauth-protected-resource');
  const origin=await handleMcp(new Request('http://127.0.0.1:8089/mcp',{headers:{Authorization:`Bearer ${token}`,Origin:'http://other.invalid'}}));expect(origin.status).toBe(403);
 });
});

describe('OAuth registration and discovery routing',()=>{
 it('serves RFC8414 path insertion and bounds dynamic client registrations',async()=>{
  const {createPublicServer}=await import('../../lib/oauth/runtime');
  const publicServer=createPublicServer(provider,store);
  await new Promise<void>(resolve=>publicServer.listen(0,'127.0.0.1',resolve));
  try{
   const address=publicServer.address();if(!address||typeof address==='string')throw new Error('No test listener');
   const base=`http://127.0.0.1:${address.port}`;
   const call=(path:string,body?:string)=>new Promise<Response>((resolve,reject)=>{const req=httpRequest({hostname:'127.0.0.1',port:address.port,path,method:body?'POST':'GET',headers:{Host:'127.0.0.1:8089','x-forwarded-host':'untrusted.invalid',...(body?{'Content-Type':'application/json'}:{})}},res=>{let text='';res.on('data',chunk=>text+=chunk);res.on('end',()=>resolve(new Response(text,{status:res.statusCode,headers:{'retry-after':String(res.headers['retry-after']??'')}})));});req.setTimeout(5000,()=>req.destroy(new Error('Test timeout')));req.on('error',reject);req.end(body);});
   const response=await call('/.well-known/oauth-authorization-server/oauth');
   expect(response.status).toBe(200);const metadata=await response.json();expect(metadata.issuer).toBe('http://127.0.0.1:8089/oauth');expect(metadata.authorization_endpoint).toBe('http://127.0.0.1:8089/oauth/auth');expect(metadata.code_challenge_methods_supported).toEqual(['S256']);
   const untrusted=await fetch(`${base}/oauth/.well-known/openid-configuration`,{signal:AbortSignal.timeout(5000)});expect(untrusted.status).toBe(400);
   for(let index=0;index<11;index++){
    const registered=await call('/oauth/reg',JSON.stringify({application_type:'native',redirect_uris:['http://127.0.0.1/callback'],grant_types:['authorization_code'],response_types:['code'],token_endpoint_auth_method:'none'}));
    expect(registered.status).toBe(index<10?201:429);if(index===10)expect(registered.headers.get('retry-after')).toBe('60');
   }
  }finally{await new Promise<void>(resolve=>publicServer.close(()=>resolve()));}
 });
});


describe('MCP agent lifecycle parity',()=>{
 it('runs register/session/task lifecycle with shared versions, receipts and deletion',async()=>{
  const {token}=await access(undefined,'agents:read agents:write');
  let sequence=1;
  const call=async(name:string,args:Record<string,unknown>)=>{
   const response=await handleMcp(new Request('http://127.0.0.1:8089/mcp',{method:'POST',headers:{Authorization:`Bearer ${token}`,'Content-Type':'application/json',Accept:'application/json, text/event-stream'},body:JSON.stringify({jsonrpc:'2.0',id:sequence++,method:'tools/call',params:{name,arguments:args}})}));
   expect(response.status).toBe(200);const text=await response.text();const line=text.split('\n').find(line=>line.startsWith('data: '));return JSON.parse(line?line.slice(6):text).result;
  };
  const mutation=()=>({operationId:randomBytes(16).toString('hex'),requestedAt:new Date().toISOString()});
  const registered=await call('agents_register',{input:{provider:'claude',externalId:'test-agent',displayName:'Test agent'},...mutation()});expect(registered.isError).not.toBe(true);const agent=registered.structuredContent.result;
  const sessionResult=await call('agents_sessions_create',{agentId:agent.id,externalId:'test-session',...mutation()});const session=sessionResult.structuredContent.result;
  const taskResult=await call('agents_tasks_create',{input:{externalId:'test-task',title:'Test task',assignment:{sessionId:session.id}},...mutation()});const task=taskResult.structuredContent.result;expect(task.status).toBe('queued');
  const changed=await call('agents_tasks_transition',{id:task.id,status:'working',expectedVersion:1,...mutation()});expect(changed.structuredContent.result.version).toBe(2);
  const invalid=await call('agents_tasks_transition',{id:task.id,status:'completed',expectedVersion:1,...mutation()});expect(invalid.isError).toBe(true);
  const progress=await call('agents_tasks_activity',{id:task.id,input:{kind:'progress',summary:'Test progress'},...mutation()});expect(progress.isError).not.toBe(true);
  const removed=await call('agents_tasks_delete',{id:task.id,...mutation()});expect(removed.isError).not.toBe(true);
  expect((await call('agents_tasks_get',{id:task.id})).isError).toBe(true);
  expect((await call('agents_sessions_list',{userId:'owner-b'})).isError).toBe(true);
 });
});

describe('OAuth deployment boundaries',()=>{
 it('allows production loopback and HTTPS while rejecting remote HTTP',()=>{
  process.env={...process.env,NODE_ENV:'production'};expect(()=>createProvider(store)).not.toThrow();
  process.env.PUBLIC_ORIGIN='http://remote.invalid';expect(()=>createProvider(store)).toThrow('Invalid OAuth origin');
  process.env.PUBLIC_ORIGIN='https://remote.invalid';expect(()=>createProvider(store)).not.toThrow();
 });
 it('refuses unsafe runtime directories before opening an internal connection',async()=>{
  const {chmodSync}=await import('node:fs');chmodSync(dir,0o777);
  await expect(oauthInternal('introspect',{token:'private-test-token'})).rejects.toThrow('Unsafe OAuth runtime directory');chmodSync(dir,0o700);
 });
 it('rejects an impersonating non-socket file without sending a token',async()=>{
  const {writeFileSync}=await import('node:fs');const fake=join(dir,'fake.sock');writeFileSync(fake,'not-a-socket',{mode:0o600});process.env.DAILY_WEB_OAUTH_SOCKET=fake;
  await expect(oauthInternal('introspect',{token:'private-test-token'})).rejects.toThrow('Unsafe OAuth socket');
 });
});
