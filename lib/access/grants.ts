import { getDb } from '@/lib/db';
import { OAuthStore } from '@/lib/oauth/adapter';
import { decrypt } from '@/lib/vault/crypto';
import { AccessError } from './principal';
export function listGrants(userId:string){
  const rows=getDb().prepare("SELECT jsn_payload,tsz_expires,uid_grant FROM main.tb_oauth_record WHERE typ_kind='Grant' AND uid_user=? AND (tsz_expires IS NULL OR tsz_expires>?) LIMIT 1000").all(userId,new Date().toISOString()) as {jsn_payload:string;tsz_expires:string|null;uid_grant:string}[];
  const store=new OAuthStore(getDb());
  return rows.map(row=>{const data=JSON.parse(decrypt(row.jsn_payload,'oauth-provider-v1'));const client=store.get('Client',data.clientId);return {id:row.uid_grant,clientId:data.clientId,clientName:client?.client_name??'MCP client',scopes:Object.values(data.resources??{}).flatMap(value=>String(value).split(' ')),expiresAt:row.tsz_expires};});
}
export function revokeGrant(userId:string,id:string){
  const store=new OAuthStore(getDb());const grant=store.get('Grant',id);if(!grant||grant.accountId!==userId)throw new AccessError(404,'not_found','Authorization not found');store.revoke(id);
}
