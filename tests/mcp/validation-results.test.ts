// @vitest-environment node
import { describe, expect, it } from 'vitest';
import { sessionToolResult } from '../../scripts/validation/mcp-result.mjs';
const at='2026-10-23T00:00:00.000Z';
const session={id:'fixture-session',agentId:'fixture-agent',externalId:'fixture-run',version:1,startedAt:at,lastActivityAt:at,freshness:'fresh',agent:{id:'fixture-agent',externalId:'fixture-agent',provider:'claude',displayName:'Fixture agent',createdAt:at,lastActivityAt:at}};
const page={items:[session],nextCursor:null,complete:true};
describe('sanitized real-client MCP response observations',()=>{
 it('counts a validated page inside the registry structured result wrapper',()=>{expect(sessionToolResult({jsonrpc:'2.0',id:1,result:{structuredContent:{result:page},content:[{type:'text',text:JSON.stringify(page)}]}})).toEqual({result:'success',itemCount:1});});
 it('accepts a validated text page when structured content is absent',()=>{expect(sessionToolResult({jsonrpc:'2.0',id:1,result:{content:[{type:'text',text:JSON.stringify(page)}]}})).toEqual({result:'success',itemCount:1});});
 it('never classifies malformed pages, unknown enums or protocol errors as success',()=>{expect(sessionToolResult({result:{structuredContent:{result:{...page,items:'one'}}}})).toEqual({result:'invalid'});expect(sessionToolResult({result:{structuredContent:{result:{...page,items:[{...session,freshness:'unknown'}]}}}})).toEqual({result:'invalid'});expect(sessionToolResult({error:{code:-32603,message:'fixture failure'}})).toEqual({result:'error'});expect(sessionToolResult({result:{isError:true,content:[{type:'text',text:JSON.stringify(page)}]}})).toEqual({result:'error'});});
});
