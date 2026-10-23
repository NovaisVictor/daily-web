import { createHash } from 'node:crypto';
import type Database from 'better-sqlite3';
import { errors, type AdapterPayload } from 'oidc-provider';
import { encrypt, decrypt } from '../vault/crypto';
const purpose = 'oauth-provider-v1';
const digest = (id: string) => createHash('sha256').update(id).digest('hex');
export class OAuthStore {
  constructor(readonly db: Database.Database) { db.pragma('busy_timeout = 5000'); }
  get(kind: string, id: string): AdapterPayload | undefined {
    const row = this.db.prepare('SELECT jsn_payload FROM main.tb_oauth_record WHERE typ_kind = ? AND uid_record = ? AND (tsz_expires IS NULL OR tsz_expires > ?)').get(kind, digest(id), new Date().toISOString()) as {jsn_payload:string}|undefined;
    return row ? JSON.parse(decrypt(row.jsn_payload, purpose)) as AdapterPayload : undefined;
  }
  put(kind: string, id: string, payload: AdapterPayload, expiresIn?: number): void {
    this.db.prepare(`INSERT INTO main.tb_oauth_record(typ_kind,uid_record,jsn_payload,tsz_expires,uid_user,uid_grant) VALUES(?,?,?,?,?,?) ON CONFLICT(typ_kind,uid_record) DO UPDATE SET jsn_payload=excluded.jsn_payload,tsz_expires=excluded.tsz_expires,uid_user=excluded.uid_user,uid_grant=excluded.uid_grant`).run(kind,digest(id),encrypt(JSON.stringify(payload),purpose),expiresIn === undefined ? null : new Date(Date.now()+expiresIn*1000).toISOString(),payload.accountId ?? payload.session?.accountId ?? null,payload.grantId ?? (kind === 'Grant' ? id : null));
    if(payload.uid && typeof payload.uid==='string')this.put(`${kind}:uid`,payload.uid,{reference:id},expiresIn);
    if(payload.userCode && typeof payload.userCode==='string')this.put(`${kind}:userCode`,payload.userCode,{reference:id},expiresIn);
    if(kind==='Client'&&!this.get('ClientRegistration',id))this.put('ClientRegistration',id,{reference:id,createdAt:Date.now()});
    if(kind==='Grant'&&payload.clientId){const registration=this.get('ClientRegistration',payload.clientId);if(registration)this.put('ClientRegistration',payload.clientId,{...registration,authorizedAt:Date.now()});}

  }
  remove(kind:string,id:string) { this.db.prepare('DELETE FROM main.tb_oauth_record WHERE typ_kind=? AND uid_record=?').run(kind,digest(id)); }
  revoke(grantId:string) { this.db.prepare('DELETE FROM main.tb_oauth_record WHERE uid_grant=?').run(grantId); }
  find(kind:string, property:'uid'|'userCode', value:string) {
    const index=this.get(`${kind}:${property}`,value);
    return index?.reference ? this.get(kind,String(index.reference)) : undefined;
  }
  cleanup(now=Date.now()) {
    this.db.prepare('DELETE FROM main.tb_oauth_record WHERE rowid IN (SELECT rowid FROM main.tb_oauth_record WHERE tsz_expires <= ? LIMIT 500)').run(new Date(now).toISOString());
    const rows=this.db.prepare("SELECT jsn_payload FROM main.tb_oauth_record WHERE typ_kind='ClientRegistration' LIMIT 1000").all() as {jsn_payload:string}[];
    for(const row of rows){const metadata=JSON.parse(decrypt(row.jsn_payload,purpose));if(!metadata.authorizedAt && metadata.createdAt<now-86400000){this.remove('Client',metadata.reference);this.remove('ClientRegistration',metadata.reference);}}
  }
  adapter = (kind:string) => ({
    upsert: async (id:string,payload:AdapterPayload,expiresIn?:number) => { this.put(kind,id,payload,expiresIn); },
    find: async (id:string) => this.get(kind,id),
    findByUid: async (uid:string) => this.find(kind,'uid',uid),
    findByUserCode: async (code:string) => this.find(kind,'userCode',code),
    destroy: async (id:string) => { this.remove(kind,id); },
    consume: async (id:string) => {
      const accepted=this.db.transaction(()=>{
        const payload=this.get(kind,id);
        if(!payload)return false;
        if(payload.consumed){if(payload.grantId)this.revoke(payload.grantId);return false;}
        payload.consumed=Math.floor(Date.now()/1000);
        this.put(kind,id,payload,payload.exp ? Math.max(0,payload.exp-Math.floor(Date.now()/1000)) : undefined);
        return true;
      }).immediate();
      if(!accepted)throw new errors.InvalidGrant('Token already consumed');
    },
    revokeByGrantId: async (id:string) => { this.revoke(id); },
  });
}
