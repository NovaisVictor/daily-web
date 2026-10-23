import {afterEach,describe,expect,it} from 'vitest';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {runBackup} from '../../scripts/backup';
import {runRestore} from '../../scripts/restore';
import Database from 'better-sqlite3';
const directories:string[]=[];
afterEach(()=>{for(const directory of directories.splice(0))fs.rmSync(directory,{recursive:true,force:true});});
const temporary=()=>{const directory=fs.mkdtempSync(path.join(os.tmpdir(),'daily-backup-deploy-'));directories.push(directory);return directory;};
describe('scheduled logical backup CLI',()=>{
 it('uses the actual default DB path, excludes agent/OAuth content, revokes PATs and restores only into a new file',()=>{
  const directory=temporary(),data=path.join(directory,'data'),destination=path.join(directory,'private-backups');fs.mkdirSync(data);
  const db=new Database(path.join(data,'daily-web.db'));
  db.exec("CREATE TABLE settings (value TEXT); INSERT INTO settings VALUES ('kept'); CREATE TABLE tb_agent (value TEXT); INSERT INTO tb_agent VALUES ('excluded'); CREATE TABLE tb_oauth_record (value TEXT); INSERT INTO tb_oauth_record VALUES ('excluded'); CREATE TABLE tb_api_credential (typ_state TEXT); INSERT INTO tb_api_credential VALUES ('active')");db.close();
  const backup=runBackup(['--scheduled'],{DAILY_WEB_BACKUP_DIR:destination},directory);
  expect(fs.statSync(destination).mode&0o777).toBe(0o700);expect(fs.statSync(backup).mode&0o777).toBe(0o600);
  const copy=new Database(backup,{readonly:true});expect(copy.prepare('SELECT value FROM settings').get()).toEqual({value:'kept'});expect(copy.prepare('SELECT * FROM tb_agent').all()).toEqual([]);expect(copy.prepare('SELECT * FROM tb_oauth_record').all()).toEqual([]);expect(copy.prepare('SELECT typ_state FROM tb_api_credential').get()).toEqual({typ_state:'revoked'});copy.close();
  const restored=path.join(directory,'restored.db');runRestore([backup,restored]);expect(fs.existsSync(restored)).toBe(true);expect(()=>runRestore([backup,restored])).toThrow();
  const second=runBackup(['--scheduled'],{DAILY_WEB_BACKUP_DIR:destination},directory);expect(second).not.toBe(backup);expect(fs.existsSync(backup)).toBe(true);
 });
 it('honors configured DB path and rejects missing, relative, public or symlink destinations',()=>{
  const directory=temporary(),dbPath=path.join(directory,'source.db');const db=new Database(dbPath);db.exec('CREATE TABLE settings (value TEXT)');db.close();
  expect(()=>runBackup(['--scheduled'],{},directory)).toThrow('private absolute');expect(()=>runBackup(['--scheduled'],{DAILY_WEB_BACKUP_DIR:'relative'},directory)).toThrow();
  const publicDirectory=path.join(directory,'public');fs.mkdirSync(publicDirectory,{mode:0o755});expect(()=>runBackup(['--scheduled'],{DAILY_WEB_BACKUP_DIR:publicDirectory,DAILY_WEB_DB_PATH:dbPath},directory)).toThrow('0700');
  const privateDirectory=path.join(directory,'private');fs.mkdirSync(privateDirectory,{mode:0o700});const linked=path.join(directory,'linked');fs.symlinkSync(privateDirectory,linked);expect(()=>runBackup(['--scheduled'],{DAILY_WEB_BACKUP_DIR:linked,DAILY_WEB_DB_PATH:dbPath},directory)).toThrow('0700');
  expect(fs.existsSync(runBackup(['--scheduled'],{DAILY_WEB_BACKUP_DIR:privateDirectory,DAILY_WEB_DB_PATH:dbPath},'/missing'))).toBe(true);
 });
});
function health(codes:string[],tries=3){
 const directory=temporary(),bin=path.join(directory,'bin');fs.mkdirSync(bin);const counter=path.join(directory,'count');
 fs.writeFileSync(path.join(bin,'curl'),`#!/bin/bash\nn=0; [[ ! -f "$COUNT_FILE" ]] || read -r n < "$COUNT_FILE"\nn=$((n+1)); echo "$n" > "$COUNT_FILE"\ncase "$n" in\n${codes.map((code,index)=>`${index+1}) printf '${code}' ;;`).join('\n')}\n*) printf '503' ;;\nesac\n`,{mode:0o755});
 const result=spawnSync('/bin/bash',['deploy/healthcheck.sh'],{encoding:'utf8',timeout:10000,env:{...process.env,PATH:bin+':'+process.env.PATH,COUNT_FILE:counter,DAILY_WEB_HEALTH_TRIES:String(tries),DAILY_WEB_HEALTH_DELAY:'0'}});
 return {...result,calls:Number(fs.readFileSync(counter,'utf8'))};
}
describe('mandatory app and OAuth health',()=>{
 it('retries OAuth independently after the app is already healthy',()=>{const result=health(['200','503','200','200']);expect(result.status).toBe(0);expect(result.calls).toBe(4);});
 it('fails when app works but OAuth remains unavailable',()=>{expect(health(['200','503','200','503','200','503']).status).toBe(1);});
 it('fails when OAuth works but app remains unavailable',()=>{expect(health(['503','200','503','200','503','200']).status).toBe(1);});
});

function publish(failure:'none'|'rsync'|'install'|'restart'|'oauth'|'health',existing='0'){
 const directory=temporary(),bin=path.join(directory,'bin'),target=path.join(directory,'target'),log=path.join(directory,'actions');fs.mkdirSync(bin);fs.mkdirSync(path.join(target,'deploy'),{recursive:true});
 const executable=(name:string,source:string)=>fs.writeFileSync(path.join(bin,name),'#!/bin/bash\n'+source,{mode:0o755});
 executable('node',"printf '/resolved/node\\n'");
 executable('systemctl',`if [[ "$1" == cat ]]; then [[ "$OAUTH_EXISTS" == 1 ]]; else exit 0; fi\n`);
 executable('rsync',`echo copy >> "$ACTION_LOG"\n[[ "$FAILURE" != rsync ]]\n`);
 executable('sudo',`if [[ "$1" == env && "$5" == --check ]]; then echo check >> "$ACTION_LOG"; exit 0; fi\nif [[ "$1" == env ]]; then echo install >> "$ACTION_LOG"; [[ "$FAILURE" != install ]]; exit; fi\nshift\necho "$*" >> "$ACTION_LOG"\nif [[ "$1" == restart && "$FAILURE" == restart ]]; then exit 1; fi\nif [[ "$1" == start && "$2" == daily-web-oauth && "$FAILURE" == oauth ]]; then exit 1; fi\nexit 0\n`);
 fs.writeFileSync(path.join(target,'deploy','healthcheck.sh'),`#!/bin/bash\necho health >> "$ACTION_LOG"\n[[ "$FAILURE" != health ]]\n`,{mode:0o755});
 const result=spawnSync('/bin/bash',['deploy/publish.sh'],{encoding:'utf8',timeout:10000,env:{...process.env,PATH:bin+':'+process.env.PATH,DAILY_WEB_DEPLOY_DIR:target,DAILY_WEB_SERVICE:'daily-web',ACTION_LOG:log,FAILURE:failure,OAUTH_EXISTS:existing}});
 return {...result,actions:fs.existsSync(log)?fs.readFileSync(log,'utf8').trim().split('\n'):[]};
}
describe('first upgrade publication',()=>{
 it('installs a missing companion before restarting and always verifies both services',()=>{
  const result=publish('none');expect(result.status).toBe(0);expect(result.actions).toEqual(['check','copy','install','restart daily-web','start daily-web-oauth','health']);
 });
 it('stops an existing companion before replacing artifacts',()=>{
  const result=publish('none','1');expect(result.status).toBe(0);expect(result.actions.slice(0,2)).toEqual(['check','stop daily-web-oauth']);
 });
 for(const failure of ['rsync','install','restart'] as const)it(`does not restart an old companion on ${failure} failure with mixed artifacts`,()=>{
  const result=publish(failure,'1');expect(result.status).not.toBe(0);expect(result.actions).not.toContain('start daily-web-oauth');expect(result.actions).not.toContain('health');
 });
 for(const failure of ['oauth','health'] as const)it(`fails publication on ${failure} failure`,()=>{expect(publish(failure).status).not.toBe(0);});
});
