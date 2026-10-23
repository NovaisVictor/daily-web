import {afterEach,describe,expect,it,vi} from 'vitest';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {discoverService,renderServices,installServices} from '../../deploy/install-services.mjs';
const directories=[];
afterEach(()=>{for(const directory of directories.splice(0))fs.rmSync(directory,{recursive:true,force:true});});
function fixture(){
 const directory=fs.mkdtempSync(path.join(os.tmpdir(),'daily-deploy-'));directories.push(directory);
 const app=path.join(directory,'app'),environment=path.join(directory,'env'),units=path.join(directory,'units');
 fs.mkdirSync(path.join(app,'dist'),{recursive:true});fs.writeFileSync(environment,'PUBLIC_ORIGIN=https://example.invalid');
 for(const file of ['oauth-server.js','migrate-db.js','backup.js','restore.js'])fs.writeFileSync(path.join(app,'dist',file),'');
 const run=vi.fn((command,args)=>args.includes('--property=User,WorkingDirectory,EnvironmentFiles,MainPID')?`User=appuser\nWorkingDirectory=${app}\nEnvironmentFiles=${environment} (ignore_errors=no)\nMainPID=0`:'');
 return {app,units,environment,run,options:{target:app,unitDirectory:units,run,uid:0,node:process.execPath}};
}
describe('managed service installer',()=>{
 it('discovers the actual account, working directory, environment and executable',()=>{
  const f=fixture();expect(discoverService('daily-web',f.run,fs,process.execPath)).toEqual({user:'appuser',directory:f.app,environmentFile:f.environment,node:fs.realpathSync(process.execPath)});
 });
 it('renders complete shared private runtime, migrate and daily logical backup services',()=>{
  const f=fixture(),config=discoverService('daily-web',f.run,fs,process.execPath),units=renderServices(config);
  expect(Object.keys(units)).toHaveLength(4);
  expect(units['daily-web.service.d/50-agent-workspace.conf']).toContain(`ExecStartPre=${config.node} ${f.app}/dist/migrate-db.js`);
  for(const name of ['daily-web.service.d/50-agent-workspace.conf','daily-web-oauth.service']){expect(units[name]).toContain('RuntimeDirectoryMode=0700');expect(units[name]).toContain('RuntimeDirectoryPreserve=yes');expect(units[name]).toContain('UMask=0077');}
  expect(units['daily-web-backup.service']).toContain('dist/backup.js --scheduled');expect(units['daily-web-backup.timer']).toContain('OnCalendar=daily');
  expect(JSON.stringify(units)).not.toContain('SEU_USUARIO');
 });
 it('validates the first upgrade before any service stop or installation writes',()=>{
  const f=fixture();installServices({...f.options,mode:'inspect'});expect(fs.existsSync(f.units)).toBe(false);expect(f.run.mock.calls.some(([,args])=>args.includes('daemon-reload'))).toBe(false);
 });
 it('installs idempotently and enables companion and backup timer without restarting the app',()=>{
  const f=fixture();installServices(f.options);const file=path.join(f.units,'daily-web-oauth.service'),before=fs.statSync(file).mtimeMs;
  installServices(f.options);expect(fs.statSync(file).mtimeMs).toBe(before);
  expect(f.run).toHaveBeenCalledWith('systemctl',['enable','daily-web-oauth.service']);expect(f.run).toHaveBeenCalledWith('systemctl',['enable','--now','daily-web-backup.timer']);expect(f.run.mock.calls.some(([,args])=>args.includes('restart'))).toBe(false);
 });
 it('rejects an unmanaged unit before writing any service file',()=>{
  const f=fixture();fs.mkdirSync(f.units);fs.writeFileSync(path.join(f.units,'daily-web-oauth.service'),'custom unit');
  expect(()=>installServices(f.options)).toThrow('unmanaged');expect(fs.readdirSync(f.units)).toEqual(['daily-web-oauth.service']);
 });
 it('rejects a system vendor custom unit outside the destination',()=>{
  const f=fixture(),custom=path.join(f.app,'custom.service');fs.writeFileSync(custom,'custom');
  const original=f.run.getMockImplementation();f.run.mockImplementation((command,args)=>args.includes('--property=FragmentPath')?custom:original(command,args));
  expect(()=>installServices(f.options)).toThrow('unmanaged');expect(fs.existsSync(f.units)).toBe(false);
 });
 it('rejects nonroot invocation, target mismatch and missing compiled artifact',()=>{
  const f=fixture();expect(()=>installServices({...f.options,uid:501})).toThrow('root');expect(()=>installServices({...f.options,target:f.units})).toThrow();fs.unlinkSync(path.join(f.app,'dist','backup.js'));expect(()=>installServices(f.options)).toThrow('incomplete');
 });
 it('rejects ambiguous environment files, unsafe names and root app accounts',()=>{
  const f=fixture(),original=f.run.getMockImplementation();
  f.run.mockImplementation((command,args)=>original(command,args).replace('User=appuser','User=root'));expect(()=>discoverService('daily-web',f.run,fs)).toThrow('non-root');
  expect(()=>discoverService('daily-web;bad',f.run,fs)).toThrow('name');
  expect(()=>renderServices({user:'appuser',directory:'/tmp/app\nExecStart=bad',environmentFile:'/tmp/env',node:process.execPath})).toThrow();
 });
 it('propagates daemon-reload or timer failure so a deployment cannot finish green',()=>{
  const f=fixture(),original=f.run.getMockImplementation();f.run.mockImplementation((command,args)=>{if(args.includes('daemon-reload'))throw Error('failed');return original(command,args);});expect(()=>installServices(f.options)).toThrow('failed');
 });
});
