import {afterEach,beforeEach,describe,expect,it,vi} from 'vitest';
import {mkdtempSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {getDb} from '@/lib/db';
import * as ops from '@/lib/agents/operations';
let directory:string,sequence=0;
const mutation=()=>({key:`attention-operation-${++sequence}`,requestedAt:new Date().toISOString()});
const session=(owner='a')=>{const agent=ops.registerAgent(owner,{externalId:`agent-${++sequence}`,provider:'claude',displayName:'Claude'},mutation());return ops.createSession(owner,{agentId:agent.id,externalId:`session-${++sequence}`},mutation());};
beforeEach(()=>{
 directory=mkdtempSync(path.join(tmpdir(),'daily-agent-attention-'));
 vi.stubEnv('DAILY_WEB_DB_PATH',path.join(directory,'db'));
 for(const id of ['a','b'])getDb().prepare('INSERT INTO users(id,username,password_hash,is_admin,created_at) VALUES(?,?,?,?,?)').run(id,id,'unused',0,new Date().toISOString());
});
afterEach(()=>{vi.useRealTimers();vi.unstubAllEnvs();rmSync(directory,{recursive:true,force:true});});

describe('session attention',()=>{
 it('marks a session as waiting for the user, exposes it on assigned tasks, and clears it',()=>{
  vi.useFakeTimers();vi.setSystemTime(Date.parse('2026-10-24T01:00:00.000Z'));
  const s=session();
  const task=ops.createTask('a',{externalId:`task-${++sequence}`,title:'Ship',assignment:{sessionId:s.id}},mutation());
  expect(task.assignment?.attention).toBeNull();
  const waiting=ops.setSessionAttention('a',s.id,{attention:{kind:'input'}},mutation());
  expect(waiting.attention).toEqual({kind:'input',since:'2026-10-24T01:00:00.000Z'});
  expect(ops.getTask('a',task.id).assignment?.attention).toEqual({kind:'input',since:'2026-10-24T01:00:00.000Z'});
  vi.setSystemTime(Date.parse('2026-10-24T01:05:00.000Z'));
  expect(ops.setSessionAttention('a',s.id,{attention:{kind:'input'}},mutation()).attention?.since).toBe('2026-10-24T01:00:00.000Z');
  expect(ops.setSessionAttention('a',s.id,{attention:{kind:'permission'}},mutation()).attention).toEqual({kind:'permission',since:'2026-10-24T01:05:00.000Z'});
  const cleared=ops.setSessionAttention('a',s.id,{attention:null},mutation());
  expect(cleared.attention).toBeNull();
  expect(cleared.lastActivityAt).toBe('2026-10-24T01:05:00.000Z');
  expect(ops.listSessions('a').items[0].attention).toBeNull();
 });
 it('replays the same operation without a second effect',()=>{
  const s=session(),key=mutation();
  const first=ops.setSessionAttention('a',s.id,{attention:{kind:'permission'}},key);
  expect(ops.setSessionAttention('a',s.id,{attention:{kind:'permission'}},key)).toEqual(first);
 });
 it('rejects unknown kinds, extra fields, a missing attention and foreign or missing sessions',()=>{
  const s=session(),foreign=session('b');
  for(const input of [{attention:{kind:'surprise'}},{attention:{kind:'input',extra:true}},{attention:'input'},{},{attention:null,other:1}])
   expect(()=>ops.setSessionAttention('a',s.id,input,mutation())).toThrowError(expect.objectContaining({status:400}));
  for(const id of [foreign.id,'missing-session'])
   expect(()=>ops.setSessionAttention('a',id,{attention:{kind:'input'}},mutation())).toThrowError(expect.objectContaining({status:404}));
  expect(ops.getSession('b',foreign.id).attention).toBeNull();
 });
});
