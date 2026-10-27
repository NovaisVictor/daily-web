import { z } from 'zod';
import { operation } from './context';
import { AccessError } from '@/lib/access/principal';
import { moduleStates, findConnection, saveConnection, deleteConnection, setModuleEnabled } from '@/lib/vault/connections';
import { testConnection as testJira } from '@/lib/integrations/jiraApi';
import { testConnection as testGithub } from '@/lib/integrations/githubApi';
import { dropCache } from '@/lib/refresher';
import { oauthConfig } from '@/lib/oauth/config';
import { MODULES, validateValues } from '@/lib/modules';

const moduleId=z.enum(['jira','pulls','tasks']);
const metadata=z.object({
  cloud:z.string().max(300).optional(),
  email:z.string().max(300).optional(),
  repos:z.string().max(4000).optional(),
  provider:z.enum(['local','mstodo']).optional(),
  clientId:z.string().max(200).optional(),
  list:z.string().max(300).optional(),
}).strict();
export const connectionOperations=[
  operation('connections_list','List your supported integration metadata without secrets','connections:read','read',{},async(p)=>({modules:moduleStates(p.userId).filter(m=>['jira','pulls','tasks'].includes(m.module))})),
  operation('connections_setup','Get the authenticated browser URL to enter or change a secret','connections:write','read',{module:moduleId},async(_p,i)=>({url:new URL(`/tools?module=${i.module}`,oauthConfig().origin).href,instruction:'Open this authenticated same-origin page to enter credentials. Never pass credentials to an MCP tool.'})),
  operation('connections_update','Change connection labels or declared non-secret settings; secret fields are rejected','connections:write','write',{connectionId:z.string().min(1),label:z.string().trim().min(1).max(100).optional(),values:metadata.optional()},async(p,i)=>{
    const conn=findConnection(p.userId,i.connectionId);if(!conn||!['jira','pulls','tasks'].includes(conn.module))throw new AccessError(404,'not_found','Connection not found');
    const allowed=new Set(MODULES[conn.module].fields.filter(field=>!field.secret&&!field.hidden).map(field=>field.name));
    const incoming=i.values??{};
    if(conn.module==='jira'&&incoming.cloud!==undefined&&incoming.cloud!==conn.values.cloud)throw new AccessError(409,'browser_setup_required','Change the credential destination in the authenticated browser setup');
    if(Object.keys(incoming).some(key=>!allowed.has(key))||(!i.label&&Object.keys(incoming).length===0))throw new AccessError(400,'invalid_input','Provide declared non-secret settings or a label');
    const values={...conn.values,...incoming};
    if(validateValues(conn.module,values).length)throw new AccessError(400,'invalid_input','The connection settings are invalid');
    saveConnection(p.userId,conn.module,i.label??conn.label,values,conn.id);dropCache(p.userId);return {ok:true};
  }),
  operation('connections_remove','Remove one of your supported connections','connections:write','write',{connectionId:z.string().min(1)},async(p,i)=>{
    const conn=findConnection(p.userId,i.connectionId);if(!conn||!['jira','pulls','tasks'].includes(conn.module))throw new AccessError(404,'not_found','Connection not found');
    deleteConnection(p.userId,conn.id);dropCache(p.userId);return {ok:true};
  }),
  operation('connections_test','Test an existing connection without exposing its credentials','connections:read','read',{connectionId:z.string().min(1)},async(p,i)=>{
    const conn=findConnection(p.userId,i.connectionId);if(!conn||!['jira','pulls','tasks'].includes(conn.module))throw new AccessError(404,'not_found','Connection not found');
    if(conn.module==='jira')await testJira(conn);else if(conn.module==='pulls')await testGithub(conn);else return {state:'not_applicable' as const,message:'Task provider connectivity is checked when listing tasks'};return {ok:true};
  }),
  operation('connections_toggle','Enable or disable a module for your user only','connections:write','write',{module:moduleId,state:z.enum(['enabled','disabled'])},async(p,i)=>{setModuleEnabled(p.userId,i.module,i.state==='enabled');dropCache(p.userId);return {ok:true};}),
];
