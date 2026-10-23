import { createServer, type IncomingMessage, type Server } from 'node:http';
import { chmodSync, lstatSync, unlinkSync } from 'node:fs';
import type Provider from 'oidc-provider';
import { OAuthStore } from './adapter';
import { inspectInteraction, decideInteraction } from './interaction';
import { oauthConfig,verifyRuntimeDirectory } from './config';
export async function readBody(req:IncomingMessage):Promise<unknown> {
  return new Promise((resolve,reject)=>{
    let size=0;const chunks:Buffer[]=[];
    const timeout=setTimeout(()=>{req.destroy();reject(new Error('Request timeout'));},5000);
    req.on('data',(chunk:Buffer)=>{size+=chunk.length;if(size>65536){clearTimeout(timeout);req.destroy();reject(new Error('Payload too large'));}else chunks.push(chunk);});
    req.once('error',error=>{clearTimeout(timeout);reject(error);});
    req.once('end',()=>{clearTimeout(timeout);try{resolve(JSON.parse(Buffer.concat(chunks).toString('utf8')));}catch(error){reject(error);}});
  });
}
export function startInternal(provider:Provider,store:OAuthStore):Promise<Server> {
  const config=verifyRuntimeDirectory('create');
  try{const stat=lstatSync(config.socket);if(!stat.isSocket()||stat.uid!==process.getuid?.())throw new Error('Unsafe OAuth socket');unlinkSync(config.socket);}catch(error){if((error as NodeJS.ErrnoException).code!=='ENOENT')throw error;}
  const server=createServer(async(req,res)=>{
    res.setHeader('Cache-Control','no-store');res.setHeader('Content-Type','application/json');
    try{
      if(req.method!=='POST')throw new Error('Invalid method');
      const body=await readBody(req) as Record<string,unknown>;
      let result:unknown;
      if(req.url==='/inspect' && typeof body.id==='string' && typeof body.userId==='string' && typeof body.browserSecret==='string')result=await inspectInteraction(provider,store,body.id,{userId:body.userId,browserSecret:body.browserSecret});
      else if(req.url==='/decide' && typeof body.id==='string' && typeof body.nonce==='string' && typeof body.userId==='string' && typeof body.browserSecret==='string' && (body.decision==='approve'||body.decision==='deny') && Array.isArray(body.scopes) && body.scopes.every(s=>typeof s==='string'))result=await decideInteraction(provider,store,body as Parameters<typeof decideInteraction>[2]);
      else if(req.url==='/introspect' && typeof body.token==='string'){
        const token=await provider.AccessToken.find(body.token);
        const grant=token?.grantId ? await provider.Grant.find(token.grantId) : undefined;
        const user=token?.accountId ? store.db.prepare('SELECT id FROM users WHERE id=?').get(token.accountId) : undefined;
        result=token&&grant&&user&&token.aud===config.resource?{active:true,subject:token.accountId,clientId:token.clientId,grantId:token.grantId,audience:token.aud,scopes:token.scope?.split(' ')??[],expiresAt:token.exp}:{active:false};
      } else throw new Error('Invalid operation');
      res.end(JSON.stringify(result));
    }catch{res.statusCode=400;res.end(JSON.stringify({error:'oauth_operation_rejected'}));}
  });server.requestTimeout=5000;server.headersTimeout=5000;
  return new Promise((resolve,reject)=>{server.once('error',reject);server.listen(config.socket,()=>{chmodSync(config.socket,0o600);resolve(server);});});
}
export function createPublicServer(provider:Provider,store:OAuthStore) {
  const config=oauthConfig();const addresses=new Map<string,{started:number;count:number}>();
  return createServer(async(req,res)=>{
    res.setHeader('Cache-Control','no-store');
    if(req.url==='/health'){res.end('ok');return;}
    if(req.headers.host!==new URL(config.origin).host){res.statusCode=400;res.end();return;}
    delete req.headers['x-forwarded-host'];
    req.headers['x-forwarded-proto']=new URL(config.origin).protocol.slice(0,-1);
    if(['/.well-known/oauth-authorization-server/oauth','/.well-known/openid-configuration/oauth','/oauth/.well-known/oauth-authorization-server'].includes(req.url??''))req.url='/oauth/.well-known/openid-configuration';
    if(!req.url?.startsWith('/oauth/')){res.statusCode=404;res.end();return;}
    if(req.url.split('?')[0]==='/oauth/reg' && req.method==='POST'){
      const now=Date.now();const ip=req.headers['x-forwarded-for']?.toString().split(',').at(-1)?.trim()??req.socket.remoteAddress??'unknown';
      let quota=addresses.get(ip);if(!quota||now-quota.started>=60000)quota={started:now,count:0};addresses.delete(ip);addresses.set(ip,quota);if(addresses.size>1000)addresses.delete(addresses.keys().next().value!);
      const count=store.db.prepare("SELECT count(*) AS count FROM main.tb_oauth_record WHERE typ_kind='Client'").get() as {count:number};
      if(++quota.count>10||count.count>=1000){res.statusCode=429;res.setHeader('Retry-After','60');res.end();return;}
    }
    (req as IncomingMessage & {originalUrl?:string}).originalUrl=req.url;
    req.url=req.url.slice('/oauth'.length);provider.callback()(req,res);
  });
}
