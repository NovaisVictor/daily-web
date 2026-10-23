import { tmpdir } from 'node:os';
import path from 'node:path';
import { lstatSync,mkdirSync } from 'node:fs';
export const MCP_SCOPES = ['agents:read', 'agents:write', 'tasks:read', 'tasks:write', 'jira:read', 'jira:write', 'github:read', 'github:write', 'connections:read', 'connections:write', 'agenda:focus'] as const;
export function oauthConfig() {
  const raw=process.env.PUBLIC_ORIGIN??process.env.DAILY_WEB_ORIGIN;
  if(process.env.PUBLIC_ORIGIN&&process.env.DAILY_WEB_ORIGIN&&process.env.PUBLIC_ORIGIN!==process.env.DAILY_WEB_ORIGIN)throw new Error('Conflicting OAuth origins');
  if(!raw)throw new Error('PUBLIC_ORIGIN is required for OAuth');
  const url=new URL(raw);
  if(url.username||url.password||url.search||url.hash||url.pathname!=='/'||(url.protocol!=='https:'&&!(url.protocol==='http:'&&['localhost','127.0.0.1','[::1]'].includes(url.hostname))))throw new Error('Invalid OAuth origin');
  const runtimeDirectory=path.resolve(/*turbopackIgnore: true*/ process.env.DAILY_WEB_OAUTH_RUNTIME_DIR??path.join(tmpdir(),`daily-web-${process.getuid?.()??'user'}`));
  const socket=path.resolve(/*turbopackIgnore: true*/ process.env.DAILY_WEB_OAUTH_SOCKET??path.join(runtimeDirectory,'oauth.sock'));
  if(path.dirname(socket)!==runtimeDirectory)throw new Error('OAuth socket must be in its private runtime directory');
  return {origin:url.origin,issuer:`${url.origin}/oauth`,resource:`${url.origin}/mcp`,runtimeDirectory,socket,port:Number(process.env.DAILY_WEB_OAUTH_PORT??8011)};
}
export function verifyRuntimeDirectory(mode:'create'|'verify'='verify') {
 const config=oauthConfig();
 if(mode==='create')mkdirSync(config.runtimeDirectory,{recursive:true,mode:0o700});
 const directory=lstatSync(config.runtimeDirectory);
 if(!directory.isDirectory()||directory.isSymbolicLink()||directory.uid!==process.getuid?.()||(directory.mode&0o077)!==0)throw new Error('Unsafe OAuth runtime directory');
 return config;
}
export function verifyInternalSocket() {
 const config=verifyRuntimeDirectory();const socket=lstatSync(config.socket);
 if(!socket.isSocket()||socket.uid!==process.getuid?.()||(socket.mode&0o077)!==0)throw new Error('Unsafe OAuth socket');
 return config;
}
