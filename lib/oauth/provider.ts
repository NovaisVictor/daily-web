import { generateKeyPairSync, randomBytes } from 'node:crypto';
import Provider, { errors } from 'oidc-provider';
import type { Configuration } from 'oidc-provider';
import { OAuthStore } from './adapter';
import { createHandoff,BROWSER_BINDING_COOKIE } from './interaction';
import { MCP_SCOPES, oauthConfig } from './config';
export function createProvider(store:OAuthStore, clients:Configuration['clients']=[]) {
  const config=oauthConfig();
  let keys=store.get('Configuration','signing');
  if(!keys){const pair=generateKeyPairSync('rsa',{modulusLength:2048}); keys={jwks:{keys:[{...pair.privateKey.export({format:'jwk'}),use:'sig',alg:'RS256',kid:randomBytes(16).toString('hex')}]}, cookie:randomBytes(32).toString('base64url')};store.put('Configuration','signing',keys);}
  const provider = new Provider(config.issuer, {
    adapter: store.adapter, clients,
    extraClientMetadata:{properties:['daily_web_profile'],validator:(_ctx,_key,_value,metadata)=>{
      const redirects=metadata.redirect_uris;
      if(!Array.isArray(redirects)||redirects.length>10||redirects.some(uri=>{try{const url=new URL(uri);return url.username!==''||url.password!==''||url.hash!==''||(url.protocol!=='https:'&&!(url.protocol==='http:'&&['127.0.0.1','localhost','[::1]'].includes(url.hostname)&&metadata.application_type==='native'));}catch{return true;}}))throw new errors.InvalidClientMetadata('redirect_uris must use HTTPS or native loopback');
      if(metadata.grant_types?.some(type=>!['authorization_code','refresh_token'].includes(type)))throw new errors.InvalidClientMetadata('Unsupported grant type');
    }},
    jwks:keys.jwks as Configuration['jwks'], cookies:{keys:[String(keys.cookie)],short:{secure:config.origin.startsWith('https:')},long:{secure:config.origin.startsWith('https:')}},
    responseTypes:['code'], scopes:['openid','offline_access',...MCP_SCOPES],
    pkce:{required:()=>true},
    features:{devInteractions:{enabled:false}, registration:{enabled:true}, revocation:{enabled:true}, introspection:{enabled:false},
      resourceIndicators:{enabled:true, defaultResource:()=>config.resource, useGrantedResource:()=>true, getResourceServerInfo:(_ctx,resource)=>{if(resource!==config.resource)throw new Error('Invalid resource');return {scope:MCP_SCOPES.join(' '),audience:config.resource,accessTokenFormat:'opaque',accessTokenTTL:900};}}},
    ttl:{AccessToken:900,AuthorizationCode:60,Interaction:300,Grant:90*86400,Session:30*86400,IdToken:900,RefreshToken:(_ctx,token)=>Math.max(0,Math.min(30*86400,90*86400-(Math.floor(Date.now()/1000)-Number(token.iiat ?? token.iat ?? Math.floor(Date.now()/1000)))))},
    rotateRefreshToken:()=>true,
    issueRefreshToken:(_ctx,client)=>client.grantTypeAllowed('refresh_token'),
    findAccount:async (_ctx,id)=>{const row=store.db.prepare('SELECT id FROM users WHERE id=?').get(id);return row?{accountId:id,claims:async()=>({sub:id})}:undefined;},
    interactions:{url:(ctx,interaction)=>{let binding=ctx.cookies.get(BROWSER_BINDING_COOKIE,{signed:false});if(!binding||!/^[-_A-Za-z0-9]{43}$/.test(binding))binding=randomBytes(32).toString('base64url');ctx.cookies.set(BROWSER_BINDING_COOKIE,binding,{signed:false,httpOnly:true,secure:config.origin.startsWith('https:'),sameSite:'lax',path:'/',maxAge:300000});createHandoff(store,interaction.uid,interaction.params,binding,interaction.session?.accountId);return `${config.origin}/access/consent?interaction=${encodeURIComponent(interaction.uid)}`;}},
    clientDefaults:{grant_types:['authorization_code','refresh_token'],response_types:['code'],token_endpoint_auth_method:'none',application_type:'native'},
    renderError:async(ctx)=>{ctx.status=400;ctx.body={error:'invalid_request'};},
  });
  provider.proxy=true;
  return provider;
}
