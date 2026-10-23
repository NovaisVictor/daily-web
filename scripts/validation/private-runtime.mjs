import fs from 'node:fs';
import { resolve } from 'node:path';
process.umask(0o077);
export function privateDirectory(value) {
  const directory = resolve(value);
  const state = fs.lstatSync(directory);
  if (!state.isDirectory() || state.isSymbolicLink() || state.uid !== process.getuid?.() || (state.mode & 0o077) !== 0) throw new Error('Validation requires an owned private directory without group or other access');
  return directory;
}
export function privateJson(directory, name) {
  const path = resolve(privateDirectory(directory), name);
  const state = fs.lstatSync(path);
  if (!state.isFile() || state.isSymbolicLink() || state.uid !== process.getuid?.() || (state.mode & 0o077) !== 0) throw new Error('Validation requires owned private credential files');
  return JSON.parse(fs.readFileSync(path, 'utf8'));
}
