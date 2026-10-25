import Database from 'better-sqlite3';
import fs from 'node:fs';
import path from 'node:path';
import { randomUUID } from 'node:crypto';
const excluded=new Set(['tb_agent','tb_agent_session','tb_agent_task','tb_agent_activity','tb_oauth_record','tb_push_subscription','tb_push_outbox']);
function quote(name:string):string{return '"'+name.replaceAll('"','""')+'"';}
export function logicalBackup(source:string,destination:string):void {
 if(path.resolve(source)===path.resolve(destination)||fs.existsSync(destination))throw new Error('Destination must be a new file');
 fs.mkdirSync(path.dirname(destination),{recursive:true,mode:0o700});
 const temporary=destination+'.'+randomUUID()+'.tmp';
 const input=new Database(source,{readonly:true,fileMustExist:true});let output:Database.Database|undefined;
 try{fs.closeSync(fs.openSync(temporary,'wx',0o600));output=new Database(temporary);
 input.transaction(()=>{output!.transaction(()=>{
 const schema=input.prepare("SELECT type,name,sql FROM sqlite_master WHERE sql IS NOT NULL AND name NOT LIKE 'sqlite_%' ORDER BY CASE type WHEN 'table' THEN 0 ELSE 1 END").all() as {type:string;name:string;sql:string}[];
 for(const item of schema.filter(s=>s.type==='table'))output!.exec(item.sql);
 for(const table of schema.filter(s=>s.type==='table'&&!excluded.has(s.name))){
 const cols=(input.prepare(`PRAGMA table_info(${quote(table.name)})`).all() as {name:string}[]).map(c=>c.name);
 const names=cols.map(quote).join(',');const write=output!.prepare(`INSERT INTO ${quote(table.name)} (${names}) VALUES (${cols.map(()=>'?').join(',')})`);
 for(const row of input.prepare(`SELECT ${names} FROM ${quote(table.name)}`).iterate() as Iterable<Record<string,unknown>>){if(table.name==='tb_mutation_receipt'&&/^(agents|sessions|tasks)\./.test(String(row.nam_capability)))continue;const values=cols.map(c=>table.name==='tb_api_credential'&&c==='typ_state'?'revoked':row[c]);write.run(...values);}
 }
 for(const item of schema.filter(s=>s.type!=='table'))output!.exec(item.sql);
 const version=input.pragma('user_version',{simple:true}) as number;output!.pragma(`user_version = ${version}`);
 })();})();output.close();output=undefined;fs.renameSync(temporary,destination);
 }finally{input.close();output?.close();if(fs.existsSync(temporary))fs.unlinkSync(temporary);}
}
export function restoreBackup(source:string,destination:string):void {logicalBackup(source,destination);}
