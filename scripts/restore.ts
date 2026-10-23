import { restoreBackup } from '../lib/agents/backup';
const [source,destination]=process.argv.slice(2);
if(!source||!destination)throw new Error('Usage: vite-node scripts/restore.ts <backup> <new-database-file>');
restoreBackup(source,destination);
console.log('Restore completed; API credentials and OAuth access must be reissued before use.');
