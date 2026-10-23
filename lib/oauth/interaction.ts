import { randomBytes, timingSafeEqual,createHash } from 'node:crypto';
import { request } from 'node:http';
import type Provider from 'oidc-provider';
import { OAuthStore } from './adapter';
import { oauthConfig, MCP_SCOPES,verifyInternalSocket } from './config';
export const BROWSER_BINDING_COOKIE='daily_web_oauth_browser';
const browserDigest=(secret:string)=>createHash('sha256').update(secret).digest('hex');
export interface ConsentRequest { id:string; clientId:string; clientName:string; redirectHost:string; scopes:string[]; nonce:string; }
export function createHandoff(store:OAuthStore, id:string, params:Record<string,unknown>,browserSecret:string,accountId?:string) {
  if(!store.get('Handoff',id))store.put('Handoff',id,{params,expiresAt:Date.now()+300000,browserDigest:browserDigest(browserSecret),boundUserId:accountId,nonce:randomBytes(32).toString('base64url'),handoffState:'pending'},300);
}
export async function inspectInteraction(provider:Provider,store:OAuthStore,id:string,binding:{userId:string;browserSecret:string}):Promise<ConsentRequest> {
  const handoff=store.get('Handoff',id);const interaction=await provider.Interaction.find(id);
  if(!handoff || handoff.handoffState!=='pending' || !interaction || interaction.result || Number(handoff.expiresAt)<=Date.now())throw new Error('Interaction unavailable');
  const expectedBrowser=Buffer.from(String(handoff.browserDigest??''));const suppliedBrowser=Buffer.from(browserDigest(binding.browserSecret));
  if(!binding.browserSecret||expectedBrowser.length!==suppliedBrowser.length||!timingSafeEqual(expectedBrowser,suppliedBrowser))throw new Error('Browser binding required');
  if((interaction.session?.accountId&&interaction.session.accountId!==binding.userId)||(handoff.boundUserId&&handoff.boundUserId!==binding.userId)||!store.db.prepare('SELECT id FROM users WHERE id=?').get(binding.userId))throw new Error('Interaction account mismatch');
  store.db.transaction(()=>{const current=store.get('Handoff',id);if(!current||current.handoffState!=='pending'||(current.boundUserId&&current.boundUserId!==binding.userId))throw new Error('Interaction account mismatch');store.put('Handoff',id,{...current,boundUserId:binding.userId},Math.max(0,(Number(current.expiresAt)-Date.now())/1000));}).immediate();
  if(JSON.stringify(interaction.params)!==JSON.stringify(handoff.params))throw new Error('Interaction changed');
  const params=interaction.params;const clientId=String(params.client_id);const client=await provider.Client.find(clientId);
  return {id,clientId,clientName:client?.clientName ?? 'MCP client',redirectHost:new URL(String(params.redirect_uri)).host,scopes:String(params.scope??'').split(' ').filter(scope=>MCP_SCOPES.includes(scope as typeof MCP_SCOPES[number])),nonce:String(handoff.nonce)};
}
export async function decideInteraction(provider:Provider,store:OAuthStore,input:{id:string;nonce:string;userId:string;browserSecret:string;decision:'approve'|'deny';scopes:string[]}) {
  const info=await inspectInteraction(provider,store,input.id,{userId:input.userId,browserSecret:input.browserSecret});
  if(!store.db.prepare('SELECT id FROM users WHERE id=?').get(input.userId))throw new Error('Authentication required');
  const expected=Buffer.from(info.nonce);const supplied=Buffer.from(input.nonce);
  if(expected.length!==supplied.length||!timingSafeEqual(expected,supplied)||input.scopes.some(s=>!info.scopes.includes(s)))throw new Error('Invalid consent');
  store.db.transaction(()=>{const pending=store.get('Handoff',input.id);if(!pending||pending.handoffState!=='pending')throw new Error('Interaction consumed');store.put('Handoff',input.id,{...pending,handoffState:'consumed'},Math.max(0,(Number(pending.expiresAt)-Date.now())/1000));}).immediate();
  const interaction=await provider.Interaction.find(input.id);if(!interaction)throw new Error('Interaction unavailable');
  if(input.decision==='deny')interaction.result={error:'access_denied',error_description:'Authorization denied'};
  else {
    const grant=new provider.Grant({accountId:input.userId,clientId:info.clientId});
    const scopes=input.scopes.join(' ');
    grant.addOIDCScope(`openid offline_access ${scopes}`);grant.addResourceScope(oauthConfig().resource,scopes);
    const rejected=info.scopes.filter(scope=>!input.scopes.includes(scope));
    grant.rejectOIDCScope(rejected.join(' '));grant.rejectResourceScope(oauthConfig().resource,rejected.join(' '));
    interaction.result={login:{accountId:input.userId},consent:{grantId:await grant.save()}};
  }
  await interaction.persist();return {redirect:interaction.returnTo};
}
export function oauthInternal<T>(operation:string,payload:unknown):Promise<T> {
  return new Promise((resolve,reject)=>{
    const config=verifyInternalSocket();
    const body=JSON.stringify(payload);const req=request({socketPath:config.socket,path:`/${operation}`,method:'POST',headers:{'Content-Type':'application/json','Content-Length':Buffer.byteLength(body)}},res=>{let data='';res.on('data',(chunk)=>{data+=chunk;if(data.length>65536){res.destroy();reject(new Error('OAuth response too large'));}});res.on('end',()=>{try{if(res.statusCode!==200)throw new Error('OAuth operation unavailable');resolve(JSON.parse(data) as T);}catch(error){reject(error);}});});
    req.setTimeout(5000,()=>req.destroy(new Error('OAuth verification timeout')));req.on('error',reject);req.end(body);
  });
}
