import { beforeEach,afterEach,it,expect,vi } from 'vitest';
import { mkdtempSync,rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { getDb } from '@/lib/db';
import { externalMutation, localMutation } from '@/lib/access/receipts';
import { AccessError } from '@/lib/access/principal';
let dir:string;
beforeEach(()=>{dir=mkdtempSync(path.join(tmpdir(),'daily-receipts-'));process.env.DAILY_WEB_DB_PATH=path.join(dir,'test.db');getDb().prepare("INSERT INTO users(id,username,password_hash,is_admin,created_at) VALUES('a','a','unused',1,'2026-01-01')").run();});
afterEach(()=>rmSync(dir,{recursive:true,force:true}));
it('deduplicates external effects and rejects changed input',async()=>{const m={key:'operation-1',requestedAt:new Date().toISOString()},resource={id:'repo#1',input:{text:'A'}},write=vi.fn(async()=>({ok:true,id:'remote-id'}));await externalMutation('a','comment',resource,m,write);await externalMutation('a','comment',resource,m,write);expect(write).toHaveBeenCalledTimes(1);await expect(externalMutation('a','comment',{...resource,input:{text:'B'}},m,write)).rejects.toThrow('different request');});
it('never retries unknown submission and rejects old timestamps',async()=>{const m={key:'operation-2',requestedAt:new Date().toISOString()},write=vi.fn(async()=>{throw new Error('timeout');});await expect(externalMutation('a','comment',{id:'repo#2'},m,write)).rejects.toThrow('uncertain');await expect(externalMutation('a','comment',{id:'repo#2'},m,write)).rejects.toThrow('reconciliation');expect(write).toHaveBeenCalledTimes(1);await expect(externalMutation('a','comment',{id:'repo#2'},{...m,requestedAt:'2000-01-01'},write)).rejects.toThrow('timestamp');});
it('keeps the fingerprint through authoritative non-submission reconciliation',async()=>{
 const {listUncertainReceipts,reconcileExternalMutation}=await import('@/lib/access/receipts');
 const m={key:'operation-3',requestedAt:new Date().toISOString()},resource={id:'repo#3',input:{text:'A'}};
 await expect(externalMutation('a','comment',resource,m,async()=>{throw new Error('lost connection');})).rejects.toThrow('uncertain');
 const [receipt]=listUncertainReceipts('a');
 expect(await reconcileExternalMutation('a',receipt.id,async()=>'not_submitted')).toBe('not_submitted');
 await expect(externalMutation('a','comment',{...resource,input:{text:'B'}},m,async()=>({ok:true}))).rejects.toThrow('different request');
 expect(await externalMutation('a','comment',resource,m,async()=>({ok:true,id:'confirmed'}))).toEqual({ok:true,id:'confirmed'});
});
it('preserves deterministic pre-submission errors without an uncertain receipt',async()=>{
 const mutation={key:'missing-resource',requestedAt:new Date().toISOString()};
 await expect(externalMutation('a','tasks_edit',{id:'missing'},mutation,async()=>{throw new AccessError(404,'not_found','Task not found');})).rejects.toMatchObject({status:404,code:'not_found'});
 expect(getDb().prepare('SELECT typ_state AS state FROM main.tb_mutation_receipt WHERE ref_key=?').get(mutation.key)).toEqual({state:'not_submitted'});
});
it('rolls a local mutation back if the receipt cannot commit and deduplicates successful commits',()=>{
 const mutation={key:'atomic-local-task',requestedAt:new Date().toISOString()},resource={id:'local'};
 const write=()=>{getDb().prepare("INSERT INTO tasks(id,user_id,title,position,created_at) VALUES('task','a','Local',1,'2026-01-01')").run();return {ok:true,id:'task'};};
 getDb().exec("CREATE TRIGGER fail_receipt BEFORE INSERT ON tb_mutation_receipt BEGIN SELECT RAISE(ABORT,'receipt failed'); END");
 expect(()=>localMutation('a','tasks_create',resource,mutation,write)).toThrow('receipt failed');
 expect(getDb().prepare("SELECT id FROM tasks WHERE id='task'").get()).toBeUndefined();
 getDb().exec('DROP TRIGGER fail_receipt');
 expect(localMutation('a','tasks_create',resource,mutation,write)).toEqual({ok:true,id:'task'});
 expect(localMutation('a','tasks_create',resource,mutation,write)).toEqual({ok:true,id:'task'});
});
it('preserves personal-task receipts across a logical backup without retaining agent receipts',async()=>{
 const {logicalBackup}=await import('@/lib/agents/backup');
 const {default:Database}=await import('better-sqlite3');
 const mutation={key:'personal-backup',requestedAt:new Date().toISOString()};
 localMutation('a','tasks_create',{id:'local'},mutation,()=>({ok:true,id:'personal'}));
 const destination=path.join(dir,'backup.db');logicalBackup(process.env.DAILY_WEB_DB_PATH!,destination);
 const backup=new Database(destination,{readonly:true});
 expect(backup.prepare('SELECT nam_capability AS capability FROM tb_mutation_receipt').all()).toEqual([{capability:'tasks_create'}]);
 backup.close();
});
