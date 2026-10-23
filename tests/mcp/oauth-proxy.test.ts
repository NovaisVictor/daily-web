import {createServer,type Server} from 'node:http';
import {createHash,randomBytes} from 'node:crypto';
import {mkdtempSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {getDb} from '@/lib/db';
import {OAuthStore} from '@/lib/oauth/adapter';
import {createProvider} from '@/lib/oauth/provider';
import {createPublicServer} from '@/lib/oauth/runtime';
import {BROWSER_BINDING_COOKIE} from '@/lib/oauth/interaction';
import {afterEach,beforeEach,describe,expect,it,vi} from 'vitest';
import {proxyOAuth} from '@/lib/oauth/http';
let server:Server,requests:{path:string;host:string|undefined;forwarded:string|undefined;spoofed:string|undefined;cookie:string|undefined;authorization:string|undefined;body:string}[]=[];
beforeEach(async()=>{
 requests=[];vi.stubEnv('PUBLIC_ORIGIN','https://daily.example');
 server=createServer((request,response)=>{
  let body='';request.on('data',chunk=>{body+=chunk;});request.on('end',()=>{
   requests.push({path:request.url!,host:request.headers.host,forwarded:request.headers['x-forwarded-for']?.toString(),spoofed:request.headers['x-forwarded-host']?.toString(),cookie:request.headers.cookie,authorization:request.headers.authorization,body});
   if(request.url==='/oauth/redirect'){response.writeHead(303,{Location:'https://daily.example/access/consent?interaction=fixture'});response.end();return;}
   response.setHeader('Set-Cookie',['interaction=first; HttpOnly; Secure','browser=second; HttpOnly; Secure']);
   response.setHeader('Content-Type','application/json');response.end(JSON.stringify({issuer:'https://daily.example/oauth'}));
  });
 });
 await new Promise<void>(resolve=>server.listen(0,'127.0.0.1',resolve));
 vi.stubEnv('DAILY_WEB_OAUTH_PORT',String((server.address() as {port:number}).port));
});
afterEach(async()=>{await new Promise<void>(resolve=>server.close(()=>resolve()));vi.restoreAllMocks();vi.unstubAllEnvs();});
describe('bounded OAuth route proxy',()=>{
 for(const metadata of ['/.well-known/oauth-authorization-server','/.well-known/oauth-authorization-server/oauth','/.well-known/openid-configuration/oauth']){
  it(`serves ${metadata} through the existing application origin`,async()=>{
   const response=await proxyOAuth(new Request('https://attacker.invalid'+metadata,{headers:{'x-forwarded-for':'spoofed, 198.51.100.12','x-forwarded-host':'attacker.invalid'}}));
   expect(response.status).toBe(200);expect(await response.json()).toEqual({issuer:'https://daily.example/oauth'});
   expect(requests[0]).toMatchObject({path:'/oauth/.well-known/openid-configuration',host:'daily.example',forwarded:'198.51.100.12',spoofed:undefined});
   expect(response.headers.getSetCookie()).toHaveLength(2);expect(response.headers.get('cache-control')).toBe('no-store');
  });
 }
 it('forwards form protocol bodies and authentication without forwarding spoofed proxy headers',async()=>{
  const credential=randomBytes(12).toString('hex'),body=new URLSearchParams({grant_type:'authorization_code',code:randomBytes(12).toString('hex')}).toString();
  const response=await proxyOAuth(new Request('https://daily.example/oauth/token',{method:'POST',headers:{'content-type':'application/x-www-form-urlencoded',authorization:'Basic '+credential,cookie:'interaction='+credential,'x-forwarded-for':'not-an-address'},body}));
  expect(response.status).toBe(200);expect(requests[0]).toMatchObject({path:'/oauth/token',authorization:'Basic '+credential,cookie:'interaction='+credential,body,forwarded:undefined});
 });
 it('preserves browser preflight headers for provider-controlled CORS',async()=>{
  server.removeAllListeners('request');server.on('request',(request,response)=>{
   expect(request.headers.origin).toBe('https://client.example');expect(request.headers['access-control-request-method']).toBe('POST');expect(request.headers['access-control-request-headers']).toBe('content-type');
   response.writeHead(204,{'Access-Control-Allow-Origin':'https://client.example','Access-Control-Allow-Methods':'POST'});response.end();
  });
  const response=await proxyOAuth(new Request('https://daily.example/oauth/token',{method:'OPTIONS',headers:{origin:'https://client.example','access-control-request-method':'POST','access-control-request-headers':'content-type'}}));
  expect(response.status).toBe(204);expect(response.headers.get('access-control-allow-origin')).toBe('https://client.example');
 });
 it('returns provider redirects without following them',async()=>{
  const response=await proxyOAuth(new Request('https://daily.example/oauth/redirect'));
  expect(response.status).toBe(303);expect(response.headers.get('location')).toBe('https://daily.example/access/consent?interaction=fixture');expect(requests).toHaveLength(1);
 });
 it('refuses unrelated paths, methods and excessive request bodies before forwarding',async()=>{
  expect((await proxyOAuth(new Request('https://daily.example/api/users'))).status).toBe(404);
  expect((await proxyOAuth(new Request('https://daily.example/.well-known/oauth-authorization-server/other'))).status).toBe(404);
  expect((await proxyOAuth(new Request('https://daily.example/oauth/reg',{method:'DELETE'}))).status).toBe(405);
  expect((await proxyOAuth(new Request('https://daily.example/oauth/reg',{method:'POST',body:'x'.repeat(65537)}))).status).toBe(413);
  expect(requests).toHaveLength(0);
 });
 it('fails closed when the companion is unavailable without exposing internal errors',async()=>{
  await new Promise<void>(resolve=>server.close(()=>resolve()));
  const response=await proxyOAuth(new Request('https://daily.example/oauth/token',{method:'POST',body:'grant_type=refresh_token'}));
  expect(response.status).toBe(503);expect(await response.json()).toEqual({error:'temporarily_unavailable'});
 });
 it('bounds provider response size',async()=>{
  server.removeAllListeners('request');server.on('request',(_request,response)=>response.end('x'.repeat(262145)));
  const response=await proxyOAuth(new Request('https://daily.example/oauth/auth'));
  expect(response.status).toBe(413);
 });
});


it('preserves canonical HTTPS and secure authorization cookies through the real companion despite spoofed proxy headers',async()=>{
 await new Promise<void>(resolve=>server.close(()=>resolve()));
 const directory=mkdtempSync(path.join(tmpdir(),'daily-https-proxy-'));
 vi.stubEnv('DAILY_WEB_DB_PATH',path.join(directory,'oauth.db'));
 vi.stubEnv('DAILY_WEB_SECRET_KEY',randomBytes(32).toString('base64'));
 const db=getDb();
 try {
  const store=new OAuthStore(db);
  const provider=createProvider(store);
  server=createPublicServer(provider,store);
  await new Promise<void>(resolve=>server.listen(0,'127.0.0.1',resolve));
  vi.stubEnv('DAILY_WEB_OAUTH_PORT',String((server.address() as {port:number}).port));
  const spoofed={'x-forwarded-proto':'http','x-forwarded-host':'attacker.invalid'};
  const registration=await proxyOAuth(new Request('https://daily.example/oauth/reg',{
   method:'POST',headers:{...spoofed,'content-type':'application/json'},
   body:JSON.stringify({client_name:'HTTPS proxy regression',application_type:'native',redirect_uris:['http://127.0.0.1:18181/callback'],grant_types:['authorization_code','refresh_token'],response_types:['code'],token_endpoint_auth_method:'none'}),
  }));
  expect(registration.status).toBe(201);
  const client=await registration.json();
  const verifier=randomBytes(32).toString('base64url');
  const challenge=createHash('sha256').update(verifier).digest('base64url');
  const parameters=new URLSearchParams({client_id:client.client_id,redirect_uri:'http://127.0.0.1:18181/callback',response_type:'code',scope:'openid agents:read',resource:'https://daily.example/mcp',code_challenge:challenge,code_challenge_method:'S256',state:randomBytes(16).toString('hex')});
  const authorization=await proxyOAuth(new Request(`https://daily.example/oauth/auth?${parameters}`,{headers:spoofed}));
  expect(authorization.status).toBe(303);
  const location=new URL(authorization.headers.get('location')!);
  expect(location.origin).toBe('https://daily.example');
  expect(location.pathname).toBe('/access/consent');
  expect(location.searchParams.get('interaction')).toBeTruthy();
  const cookies=authorization.headers.getSetCookie();
  expect(cookies.length).toBeGreaterThan(0);
  expect(cookies.some(cookie=>cookie.startsWith(`${BROWSER_BINDING_COOKIE}=`))).toBe(true);
  for(const cookie of cookies){expect(cookie).toMatch(/; secure(?:;|$)/i);expect(cookie).toMatch(/; httponly(?:;|$)/i);}
 } finally {db.close();rmSync(directory,{recursive:true,force:true});}
});
