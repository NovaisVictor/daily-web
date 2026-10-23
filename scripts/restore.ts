import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { restoreBackup } from '../lib/agents/backup';

export function runRestore(args: string[]): void {
  if(args.length!==2 || args.some(value=>value.startsWith('--'))) throw new Error('Usage: node dist/restore.js <backup> <new-database-file>');
  restoreBackup(args[0],args[1]);
}
if(process.argv[1] && path.resolve(process.argv[1])===fileURLToPath(import.meta.url)) {
  try { runRestore(process.argv.slice(2)); console.log('Restore completed; API credentials and OAuth access must be reissued before use.'); }
  catch { console.error('Restore failed; destination must be a new database file.'); process.exitCode=1; }
}
