import fs from 'node:fs';
import path from 'node:path';
import { randomUUID } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { logicalBackup } from '../lib/agents/backup';

export function runBackup(args: string[], environment: {DAILY_WEB_BACKUP_DIR?: string; DAILY_WEB_DB_PATH?: string} = {DAILY_WEB_BACKUP_DIR:process.env.DAILY_WEB_BACKUP_DIR,DAILY_WEB_DB_PATH:process.env.DAILY_WEB_DB_PATH}, directory = process.cwd()): string {
  let source: string;
  let destination: string;
  if (args.length === 1 && args[0] === '--scheduled') {
    const backupDirectory = environment.DAILY_WEB_BACKUP_DIR;
    if (!backupDirectory || !path.isAbsolute(backupDirectory)) throw new Error('A private absolute DAILY_WEB_BACKUP_DIR is required');
    fs.mkdirSync(backupDirectory, {recursive:true,mode:0o700});
    const stat = fs.lstatSync(backupDirectory);
    if (!stat.isDirectory() || stat.isSymbolicLink() || (stat.mode & 0o077) !== 0 || stat.uid !== process.getuid?.()) throw new Error('Backup directory must be owned by the service account with mode 0700');
    source = environment.DAILY_WEB_DB_PATH ?? path.join(directory,'data','daily-web.db');
    destination = path.join(backupDirectory,`daily-web-${new Date().toISOString().replaceAll(':','-')}-${randomUUID()}.db`);
  } else {
    if (args.length !== 2 || args.some(value => value.startsWith('--'))) throw new Error('Usage: node dist/backup.js <database> <new-backup-file> | --scheduled');
    [source,destination] = args;
  }
  logicalBackup(source,destination);
  return destination;
}

if(process.argv[1] && path.resolve(process.argv[1])===fileURLToPath(import.meta.url)) {
  try { runBackup(process.argv.slice(2)); console.log('Logical backup completed; agent history omitted and API access revoked.'); }
  catch { console.error('Logical backup failed; check source database and private destination configuration.'); process.exitCode=1; }
}
