import { build } from 'esbuild';
import { mkdir,writeFile } from 'node:fs/promises';
await mkdir('dist',{recursive:true});
await build({entryPoints:['scripts/oauth-server.ts','scripts/migrate-db.ts','scripts/backup.ts','scripts/restore.ts'],outdir:'dist',bundle:true,platform:'node',target:'node24',format:'esm',packages:'external'});
await writeFile('dist/package.json',JSON.stringify({type:'module'}));
