import { logicalBackup } from '../lib/agents/backup';
const [source,destination]=process.argv.slice(2);
if(!source||!destination)throw new Error('Usage: vite-node scripts/backup.ts <database> <new-backup-file>');
logicalBackup(source,destination);
console.log('Logical backup completed; agent history omitted and API access revoked.');
