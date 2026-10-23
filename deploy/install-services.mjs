import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const marker = '# Managed by daily-web deploy/install-services.mjs';
const safePath = value => typeof value === 'string' && /^\/[A-Za-z0-9_./@-]+$/.test(value) && !value.split('/').includes('..');
const serviceName = value => /^[A-Za-z0-9_-]+$/.test(value);
const invoke = (command, args) => execFileSync(command, args, {encoding:'utf8', timeout:15000, stdio:['ignore','pipe','pipe']}).trim();

export function discoverService(service, run = invoke, files = fs, node = process.execPath) {
  if (!serviceName(service)) throw new Error('Invalid application service name');
  const raw = run('systemctl', ['show', `${service}.service`, '--property=User,WorkingDirectory,EnvironmentFiles,MainPID']);
  const properties = Object.fromEntries(raw.split('\n').map(line => { const index=line.indexOf('='); return [line.slice(0,index),line.slice(index+1)]; }));
  const user = properties.User;
  const directory = properties.WorkingDirectory;
  const environmentMatch = /^([^\s]+) \(ignore_errors=(?:yes|no)\)$/.exec(properties.EnvironmentFiles ?? '');
  const environmentFile = environmentMatch?.[1];
  const pid = Number(properties.MainPID);
  if (!Number.isSafeInteger(pid) || pid < 0 || !user || user === 'root' || !/^[a-z_][a-z0-9_-]*\$?$/.test(user) || !safePath(directory) || !safePath(environmentFile)) throw new Error('Application service requires an explicit non-root user, absolute working directory and one environment file');
  const nodePath = files.realpathSync(pid > 0 ? `/proc/${pid}/exe` : node);
  if (!safePath(nodePath) || path.basename(nodePath) !== 'node') throw new Error('Cannot resolve the application Node executable');
  for (const file of [directory,environmentFile,nodePath]) if (!files.existsSync(file)) throw new Error('Application service path is unavailable');
  return {user,directory,environmentFile,node:nodePath};
}

export function renderServices(config, service='daily-web') {
  if (!serviceName(service) || !/^[a-z_][a-z0-9_-]*\$?$/.test(config.user) || config.user==='root' || ![config.directory,config.environmentFile,config.node].every(safePath)) throw new Error('Invalid service configuration');
  const runtime=service;
  const common=`User=${config.user}\nWorkingDirectory=${config.directory}\nEnvironmentFile=${config.environmentFile}\nUMask=0077\nNoNewPrivileges=true\n`;
  const shared=`RuntimeDirectory=${runtime}\nRuntimeDirectoryMode=0700\nRuntimeDirectoryPreserve=yes\nEnvironment=DAILY_WEB_OAUTH_RUNTIME_DIR=/run/${runtime}\nEnvironment=DAILY_WEB_OAUTH_SOCKET=/run/${runtime}/oauth.sock\n`;
  return {
    [`${service}.service.d/50-agent-workspace.conf`]:`${marker}\n[Service]\n${shared}UMask=0077\nExecStartPre=${config.node} ${config.directory}/dist/migrate-db.js\n`,
    [`${service}-oauth.service`]:`${marker}\n[Unit]\nDescription=Daily Web OAuth companion\nRequires=${service}.service\nAfter=${service}.service\nPartOf=${service}.service\n\n[Service]\nType=simple\n${common}${shared}ExecStart=${config.node} ${config.directory}/dist/oauth-server.js\nRestart=on-failure\nRestartSec=5\nTimeoutStartSec=30\nTimeoutStopSec=10\n\n[Install]\nWantedBy=multi-user.target\n`,
    [`${service}-backup.service`]:`${marker}\n[Unit]\nDescription=Daily Web logical backup without agent history\nAfter=${service}.service\n\n[Service]\nType=oneshot\n${common}Environment=DAILY_WEB_BACKUP_DIR=${config.directory}/data/backups/logical\nExecStart=${config.node} ${config.directory}/dist/backup.js --scheduled\nTimeoutStartSec=300\n`,
    [`${service}-backup.timer`]:`${marker}\n[Unit]\nDescription=Daily Web daily logical backup\n\n[Timer]\nOnCalendar=daily\nRandomizedDelaySec=15m\nPersistent=true\nUnit=${service}-backup.service\n\n[Install]\nWantedBy=timers.target\n`,
  };
}

export function installServices({service='daily-web', target, artifactDirectory=target, mode='install', unitDirectory='/etc/systemd/system', run=invoke, files=fs, uid=process.getuid?.(), node=process.execPath}={}) {
  if (!['inspect','install'].includes(mode)) throw new Error('Invalid installation mode');
  if (uid !== 0) throw new Error('Service installation requires root');
  const config=discoverService(service,run,files,node);
  if (!safePath(target) || files.realpathSync(target)!==files.realpathSync(config.directory)) throw new Error('Publish target differs from the application working directory');
  for(const artifact of ['oauth-server.js','migrate-db.js','backup.js','restore.js']) if(!files.existsSync(path.join(artifactDirectory,'dist',artifact))) throw new Error('Compiled deployment artifact is incomplete');
  const units=renderServices(config,service);
  for(const relative of Object.keys(units)) {
    const destination=path.join(unitDirectory,relative);
    const parent=path.dirname(destination);
    if(files.existsSync(parent) && files.lstatSync(parent).isSymbolicLink()) throw new Error('Refusing a symbolic link in the service directory');
    if(files.existsSync(destination)) {
      if(files.lstatSync(destination).isSymbolicLink() || !files.readFileSync(destination,'utf8').startsWith(marker+'\n')) throw new Error(`Refusing to replace an unmanaged service file: ${relative}`);
    }
    const unit=relative.split('/')[0];
    if(!unit.endsWith('.d')) {
      const existing=run('systemctl',['show',unit,'--property=FragmentPath','--value']);
      if(existing && existing!==destination && files.existsSync(existing)) throw new Error(`An unmanaged service is already installed: ${unit}`);
    }
  }
  if(mode==='inspect') return config;
  for(const [relative,content] of Object.entries(units)) {
    const destination=path.join(unitDirectory,relative);
    files.mkdirSync(path.dirname(destination),{recursive:true,mode:0o755});
    if(files.existsSync(destination) && files.readFileSync(destination,'utf8')===content) continue;
    const temporary=`${destination}.${process.pid}.tmp`;
    files.writeFileSync(temporary,content,{mode:0o644,flag:'wx'});
    files.renameSync(temporary,destination);
  }
  run('systemctl',['daemon-reload']);
  run('systemctl',['enable',`${service}-oauth.service`]);
  run('systemctl',['enable','--now',`${service}-backup.timer`]);
  return config;
}

if(process.argv[1] && path.resolve(process.argv[1])===fileURLToPath(import.meta.url)) {
  try {
    const mode=process.argv[2]==='--check'?'inspect':'install';
    const target=process.argv[mode==='inspect'?3:2];
    installServices({service:process.env.DAILY_WEB_SERVICE??'daily-web',target,mode,artifactDirectory:mode==='inspect'?process.cwd():target});
    console.log(mode==='inspect'?'Managed service configuration validated.':'OAuth and logical backup services installed.');
  }
  catch { console.error('Service installation failed; verify managed unit ownership and application paths.'); process.exitCode=1; }
}
