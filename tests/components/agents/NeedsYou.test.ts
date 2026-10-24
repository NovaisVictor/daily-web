import {describe,expect,it} from 'vitest';
import {needsYou,type AgentTask,type LiveState} from '@/components/agents/contracts';

const SINCE='2026-10-24T01:00:00.000Z';
function task(status:AgentTask['status'],{attention,live,hold}:{attention?:'input'|'permission';live?:LiveState;hold?:AgentTask['hold']}={}):AgentTask{
 return {id:'t',parentTaskId:null,externalId:'t',title:'Ship',description:'',status,hold:hold??null,source:null,version:1,createdAt:SINCE,lastActivityAt:SINCE,
  assignment:{sessionId:'s',agentId:'a',provider:'claude',displayName:'Claude',freshness:'fresh',attention:attention?{kind:attention,since:SINCE}:null,live:live?{state:live,since:SINCE}:null}};
}

describe('needsYou',()=>{
 it('trusts the raw attention when no live evidence exists',()=>{
  expect(needsYou(task('working',{attention:'input'}))).toEqual({kind:'input',since:SINCE});
  expect(needsYou(task('working',{attention:'permission'}))).toEqual({kind:'permission',since:SINCE});
 });
 it('ignores an idle signal while the agent declared it is waiting for a process',()=>{
  expect(needsYou(task('waiting',{attention:'input',hold:{reason:'build',note:null}}))).toBeNull();
  expect(needsYou(task('waiting',{attention:'permission',hold:{reason:'build',note:null}}))).toEqual({kind:'permission',since:SINCE});
 });
 it('ignores attention while the terminal shows the agent working, in background, or stopped',()=>{
  for(const live of ['working','background','stopped'] as const)expect(needsYou(task('working',{attention:'input',live}))).toBeNull();
  expect(needsYou(task('working',{attention:'input',live:'idle'}))).toEqual({kind:'input',since:SINCE});
 });
 it('flags an open terminal menu even without a hook signal',()=>{
  expect(needsYou(task('working',{live:'prompt'}))).toEqual({kind:'menu',since:SINCE});
  expect(needsYou(task('working',{attention:'permission',live:'prompt'}))).toEqual({kind:'permission',since:SINCE});
 });
 it('keeps explicit decision blocks unless the agent is visibly working',()=>{
  const hold={reason:'decision' as const,note:'A ou B'};
  expect(needsYou(task('blocked',{hold,live:'background'}))).toEqual({kind:'decision',since:SINCE});
  expect(needsYou(task('blocked',{hold,live:'working'}))).toBeNull();
 });
 it('never flags finished tasks',()=>{
  for(const status of ['completed','failed','cancelled'] as const)expect(needsYou(task(status,{attention:'input',live:'prompt'}))).toBeNull();
 });
});
