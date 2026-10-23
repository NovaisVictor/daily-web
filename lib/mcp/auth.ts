import { oauthInternal } from '@/lib/oauth/interaction';
import { oauthConfig } from '@/lib/oauth/config';
import { AccessError, type Principal } from '@/lib/access/principal';
import { findUserById } from '@/lib/auth/users';
import { getDb } from '@/lib/db';
import { OAuthStore } from '@/lib/oauth/adapter';
import { SESSION_COOKIE } from '@/lib/auth/session';
interface Introspection {active:boolean;subject?:string;scopes?:string[];audience?:string;grantId?:string;expiresAt?:number;}
export type McpPrincipal=Principal & {grantId:string};
export async function authenticateMcp(request:Request):Promise<McpPrincipal> {
 const config=oauthConfig();const origin=request.headers.get('origin');
 if(origin && origin!==config.origin)throw new AccessError(403,'invalid_origin','Origin not allowed');
 if((request.headers.get('cookie')??'').split(';').some(c=>c.trim().startsWith(`${SESSION_COOKIE}=`)))throw new AccessError(400,'ambiguous_auth','Use OAuth bearer authorization only');
 const authorization=request.headers.get('authorization');
 if(!authorization?.match(/^Bearer [A-Za-z0-9_-]{20,1024}$/))throw new AccessError(401,'invalid_token','OAuth authorization required');
 const token=authorization.slice(7);
 let verified:Introspection;try{verified=await oauthInternal<Introspection>('introspect',{token});}catch{throw new AccessError(503,'verification_unavailable','Authorization verification unavailable');}
 if(!verified.active || verified.audience!==config.resource || !verified.subject || !verified.grantId || !verified.expiresAt || verified.expiresAt<=Date.now()/1000 || !findUserById(verified.subject))throw new AccessError(401,'invalid_token','OAuth authorization required');
 return {userId:verified.subject,scopes:verified.scopes??[],kind:'oauth',grantId:verified.grantId};
}
export function oauthError(error:unknown):Response {
 const known=error instanceof AccessError;const status=known?error.status:503;const headers:Record<string,string>={'Cache-Control':'no-store'};
 try{const config=oauthConfig();if(status===401||status===403)headers['WWW-Authenticate']=`Bearer resource_metadata="${config.origin}/.well-known/oauth-protected-resource/mcp", error="${status===401?'invalid_token':'insufficient_scope'}"`;}catch{/* No metadata is advertised without configured identity. */}
 return Response.json({error:known?error.code:'oauth_unavailable'},{status,headers});
}

export function revalidatePrincipal(principal:Principal):void {
 if(!findUserById(principal.userId))throw new AccessError(401,'invalid_token','Authorization revoked');
 if(principal.kind!=='oauth'||!('grantId' in principal))throw new AccessError(401,'invalid_token','OAuth required');
 const grant=new OAuthStore(getDb()).get('Grant',String(principal.grantId));
 if(!grant||grant.accountId!==principal.userId)throw new AccessError(401,'invalid_token','Authorization revoked');
}
