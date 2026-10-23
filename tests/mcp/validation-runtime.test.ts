// @vitest-environment node
import { afterEach, describe, expect, it } from 'vitest';
import { chmodSync, mkdtempSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { privateDirectory, privateJson } from '../../scripts/validation/private-runtime.mjs';
const directories:string[]=[];
function fixture(){const directory=mkdtempSync(join(tmpdir(),'daily-validation-permissions-'));directories.push(directory);writeFileSync(join(directory,'auth.json'),JSON.stringify({kind:'disposable-fixture'}),{mode:0o600});return directory;}
afterEach(()=>{for(const directory of directories.splice(0))rmSync(directory,{recursive:true,force:true});});
describe('real-client validation credential boundary',()=>{
 it('reads only owned private fixture files and directories',()=>{const directory=fixture();expect(privateDirectory(directory)).toBe(directory);expect(privateJson(directory,'auth.json')).toEqual({kind:'disposable-fixture'});});
 it('rejects a permissive directory or credential file before reading it',()=>{const directory=fixture();chmodSync(directory,0o755);expect(()=>privateJson(directory,'auth.json')).toThrow('private directory');chmodSync(directory,0o700);chmodSync(join(directory,'auth.json'),0o644);expect(()=>privateJson(directory,'auth.json')).toThrow('private credential files');});
 it('rejects symlinks to directories and otherwise private credential files',()=>{const directory=fixture();const other=fixture();symlinkSync(directory,join(other,'directory-link'));expect(()=>privateDirectory(join(other,'directory-link'))).toThrow('private directory');symlinkSync(join(directory,'auth.json'),join(other,'credential-link.json'));expect(()=>privateJson(other,'credential-link.json')).toThrow('private credential files');});
});
