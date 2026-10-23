import { createHash, randomUUID } from 'node:crypto';
import { getDb } from '@/lib/db';
import { AccessError } from './principal';
import { findUserById } from '@/lib/auth/users';
import { RETENTION_MS, type Mutation } from '@/lib/agents/model';
import { ProviderRefusal } from '@/lib/integrations/refusal';

export function canonical(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(canonical).join(',')}]`;
  if (value !== null && typeof value === 'object') return `{${Object.entries(value).sort(([a], [b]) => a.localeCompare(b)).map(([key, val]) => `${JSON.stringify(key)}:${canonical(val)}`).join(',')}}`;
  return JSON.stringify(value) ?? 'null';
}
export function requestDigest(value: unknown): string { return createHash('sha256').update(canonical(value)).digest('hex'); }
export function validateMutation(mutation: Mutation, now = Date.now()): void {
  if (!mutation || typeof mutation.key !== 'string' || !/^[A-Za-z0-9_.:-]{8,160}$/.test(mutation.key)) throw new AccessError(400, 'invalid_idempotency_key', 'An idempotency key of 8–160 characters is required');
  const at = Date.parse(mutation.requestedAt);
  if (!Number.isFinite(at) || now - at > 86_400_000 || at - now > 60_000) throw new AccessError(400, 'stale_request', 'Request timestamp must be current');
}
interface Receipt { digest: string; state: string; outcome: string | null; resource: string | null; expires: string | null }
export function findReceipt(owner: string, capability: string, mutation: Mutation, input: unknown, now = Date.now()): Receipt | null {
  validateMutation(mutation, now);
  const row = getDb().prepare(`SELECT txt_digest AS digest, typ_state AS state, jsn_outcome AS outcome, ref_resource AS resource, tsz_expires AS expires FROM main.tb_mutation_receipt WHERE uid_user=? AND nam_capability=? AND ref_key=?`).get(owner, capability, mutation.key) as Receipt | undefined;
  if (!row) return null;
  if (row.digest !== requestDigest(input)) throw new AccessError(409, 'idempotency_conflict', 'This key was used for a different request');
  if (row.expires && row.expires <= new Date(now).toISOString()) throw new AccessError(409, 'receipt_expired', 'Reconcile the resource before issuing a new operation');
  return row;
}
export function insertReceipt(owner: string, capability: string, mutation: Mutation, input: unknown, resource: string | null, kind: 'local' | 'delete' | 'external', state: string, outcome: unknown, now: number, connection: string | null = null): void {
  const resolved = state === 'success' ? new Date(now).toISOString() : null;
  getDb().prepare(`INSERT INTO main.tb_mutation_receipt (uid_receipt,uid_user,nam_capability,ref_key,txt_digest,typ_class,ref_resource,ref_connection,typ_state,jsn_outcome,tsz_insert,tsz_resolved,tsz_expires) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)`).run(randomUUID(),owner,capability,mutation.key,requestDigest(input),kind,resource,connection,state,outcome === null ? null : JSON.stringify(outcome),new Date(now).toISOString(),resolved,resolved ? new Date(now+RETENTION_MS).toISOString() : null);
}
export class ExternalNotSubmittedError extends Error {}
function safeExternalOutcome(value:Record<string,unknown>):Record<string,unknown> {
  const result=Object.fromEntries(Object.entries(value).filter(([key,item])=>['ok','id','sha','state','code','number','rerun','complete'].includes(key)&&['string','number','boolean'].includes(typeof item)));
  const safeUrl=(item:unknown):item is string=>{
    if(typeof item!=='string'||item.length>2048)return false;
    try{const url=new URL(item);return url.protocol==='https:'&&url.hostname==='github.com'&&!url.username&&!url.password&&!url.search;}catch{return false;}
  };
  if(safeUrl(value.url))result.url=value.url;
  if(Array.isArray(value.requested)&&value.requested.length<=15&&value.requested.every(item=>typeof item==='string'&&/^(team:)?[A-Za-z0-9_-]{1,100}$/.test(item)))result.requested=value.requested;
  if(Array.isArray(value.failed)&&value.failed.length<=5)result.failed=value.failed.flatMap(item=>item&&typeof item==='object'&&Number.isSafeInteger(item.id)?[{id:item.id,error:'The provider outcome was not confirmed'}]:[]);
  if(value.review&&typeof value.review==='object'){
    const review=value.review as Record<string,unknown>;
    if(Number.isSafeInteger(review.id)&&['APPROVED','CHANGES_REQUESTED'].includes(String(review.state)))result.review={id:review.id,state:review.state};
  }
  if(value.comment&&typeof value.comment==='object'){
    const comment=value.comment as Record<string,unknown>;
    if(Number.isSafeInteger(comment.id)&&safeUrl(comment.url))result.comment={id:comment.id,url:comment.url};
  }
  return result;
}
export class ExternalPartialOutcome extends Error {
  readonly outcome:Record<string,unknown>;
  constructor(outcome:Record<string,unknown>){super('The provider outcome was only partially confirmed');this.outcome=safeExternalOutcome(outcome);}
}
export function localMutation<T extends Record<string, unknown>>(owner:string,capability:string,resource:{id:string;connectionId?:string;input?:unknown},mutation:Mutation,work:()=>T):T {
  if(!findUserById(owner))throw new AccessError(401,'invalid_identity','Authentication required');
  return getDb().transaction(()=>{
    const receipt=findReceipt(owner,capability,mutation,resource);
    if(receipt){
      if(receipt.state!=='success')throw new AccessError(409,'operation_pending','The operation has not completed');
      return JSON.parse(receipt.outcome??'{}') as T;
    }
    const result=work();
    insertReceipt(owner,capability,mutation,resource,resource.id,'local','success',result,Date.now(),resource.connectionId??null);
    return result;
  }).immediate();
}
export async function externalMutation<T extends Record<string, unknown>>(owner: string, capability: string, resource: {id:string;connectionId?:string;input?:unknown}, mutation: Mutation, work:()=>Promise<T>): Promise<T> {
  if(!findUserById(owner))throw new AccessError(401,'invalid_identity','Authentication required');
  const input = resource;
  const replay = getDb().transaction(() => {
    const receipt = findReceipt(owner, capability, mutation, input);
    if (receipt) {
      if(receipt.state==='not_submitted'){getDb().prepare(`UPDATE main.tb_mutation_receipt SET typ_state='pending',tsz_insert=?,tsz_resolved=NULL,tsz_expires=NULL WHERE uid_user=? AND nam_capability=? AND ref_key=?`).run(new Date().toISOString(),owner,capability,mutation.key);return null;}
      if (receipt.state !== 'success') {
        if(receipt.state==='unknown'&&receipt.outcome)throw new ExternalPartialOutcome(JSON.parse(receipt.outcome));
        throw new AccessError(409,'uncertain_outcome','The prior operation requires reconciliation before retry');
      }
      return JSON.parse(receipt.outcome ?? '{}') as T;
    }
    insertReceipt(owner,capability,mutation,input,resource.id,'external','pending',null,Date.now(),resource.connectionId ?? null);
    return null;
  }).immediate();
  if (replay) return replay;
  try {
    let deadline:ReturnType<typeof setTimeout>|undefined;
    const result = await Promise.race([work(),new Promise<never>((_,reject)=>{deadline=setTimeout(()=>reject(new Error('Provider deadline exceeded')),15000);})]).finally(()=>clearTimeout(deadline));
    const safe = safeExternalOutcome(result);
    const now = Date.now();
    getDb().prepare(`UPDATE main.tb_mutation_receipt SET typ_state='success',jsn_outcome=?,tsz_resolved=?,tsz_expires=? WHERE uid_user=? AND nam_capability=? AND ref_key=?`).run(JSON.stringify(safe),new Date(now).toISOString(),new Date(now+RETENTION_MS).toISOString(),owner,capability,mutation.key);
    return result;
  } catch (error) {
    if(error instanceof ExternalPartialOutcome){
      getDb().prepare(`UPDATE main.tb_mutation_receipt SET typ_state='unknown',jsn_outcome=? WHERE uid_user=? AND nam_capability=? AND ref_key=?`).run(JSON.stringify(error.outcome),owner,capability,mutation.key);
      throw error;
    }
    if (error instanceof ExternalNotSubmittedError || error instanceof ProviderRefusal || error instanceof AccessError) {
      const now=Date.now();getDb().prepare(`UPDATE main.tb_mutation_receipt SET typ_state='not_submitted',tsz_resolved=?,tsz_expires=? WHERE uid_user=? AND nam_capability=? AND ref_key=?`).run(new Date(now).toISOString(),new Date(now+RETENTION_MS).toISOString(),owner,capability,mutation.key);
      throw error;
    }
    getDb().prepare(`UPDATE main.tb_mutation_receipt SET typ_state='unknown' WHERE uid_user=? AND nam_capability=? AND ref_key=?`).run(owner,capability,mutation.key);
    throw new AccessError(409,'uncertain_outcome','The provider outcome is uncertain; reconcile before retry');
  }
}

export function listUncertainReceipts(owner:string):{id:string;capability:string;resource:string|null;connectionId:string|null;state:string;createdAt:string}[]{
 if(!findUserById(owner))throw new AccessError(401,'invalid_identity','Authentication required');
 return getDb().prepare(`SELECT uid_receipt AS id,nam_capability AS capability,ref_resource AS resource,ref_connection AS connectionId,typ_state AS state,tsz_insert AS createdAt FROM main.tb_mutation_receipt WHERE uid_user=? AND typ_class='external' AND typ_state IN ('pending','unknown') ORDER BY tsz_insert LIMIT 100`).all(owner) as {id:string;capability:string;resource:string|null;connectionId:string|null;state:string;createdAt:string}[];
}
export async function reconcileExternalMutation(owner:string,id:string,verify:(receipt:{capability:string;resource:string;connectionId:string|null})=>Promise<'submitted'|'not_submitted'|'unknown'>):Promise<'submitted'|'not_submitted'|'unknown'>{
 if(!findUserById(owner))throw new AccessError(401,'invalid_identity','Authentication required');
 const row=getDb().prepare(`SELECT nam_capability AS capability,ref_resource AS resource,ref_connection AS connectionId,typ_state AS state,tsz_insert AS createdAt FROM main.tb_mutation_receipt WHERE uid_user=? AND uid_receipt=? AND typ_class='external' AND typ_state IN ('pending','unknown')`).get(owner,id) as {capability:string;resource:string;connectionId:string|null;state:string;createdAt:string}|undefined;
 if(!row)throw new AccessError(404,'not_found','Uncertain operation not found');
 if(row.state==='pending'&&Date.now()-Date.parse(row.createdAt)<20000)throw new AccessError(409,'operation_pending','The operation may still be in flight');
 const outcome=await verify(row);
 if(outcome==='unknown')return outcome;
 if(outcome==='not_submitted'){const now=Date.now();getDb().prepare(`UPDATE main.tb_mutation_receipt SET typ_state='not_submitted',tsz_resolved=?,tsz_expires=? WHERE uid_user=? AND uid_receipt=? AND typ_state IN ('pending','unknown')`).run(new Date(now).toISOString(),new Date(now+RETENTION_MS).toISOString(),owner,id);return outcome;}
 const now=Date.now();getDb().prepare(`UPDATE main.tb_mutation_receipt SET typ_state='success',jsn_outcome=?,tsz_resolved=?,tsz_expires=? WHERE uid_user=? AND uid_receipt=? AND typ_state IN ('pending','unknown')`).run(JSON.stringify({ok:true}),new Date(now).toISOString(),new Date(now+RETENTION_MS).toISOString(),owner,id);return outcome;
}
