import {afterEach,beforeEach,describe,expect,it,vi} from 'vitest';
import {mkdtempSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {randomBytes,randomUUID} from 'node:crypto';
import {getDb} from '@/lib/db';
import {saveConnection} from '@/lib/vault/connections';
import {taskOperations} from '@/lib/operations/tasks';
import {ExternalPartialOutcome} from '@/lib/access/receipts';
import * as local from '@/lib/tasks/local';
import * as board from '@/lib/tasks/boardStatus';
import {NOTE_PAPERS,PIN_COLORS} from '@/lib/taskBoard';
import * as mstodo from '@/lib/cli/mstodo';
import {parseTasks} from '@/lib/parsers/mstodo';
import type {Principal} from '@/lib/access/principal';
import fixture from '../../fixtures/mstodo-tasks.json';

const principal:Principal={userId:'owner',kind:'oauth',scopes:['tasks:read','tasks:write']};
const mutation=()=>({operationId:randomUUID(),requestedAt:new Date().toISOString()});
const run=(name:string,input:unknown,p=principal)=>taskOperations.find(op=>op.name===name)!.run(p,input);
const metadata={due:'2030-01-20',time:'14:30',priority:'high',recur:'monthly'};
let directory:string,connectionId:string;
beforeEach(()=>{
  directory=mkdtempSync(path.join(tmpdir(),'daily-task-metadata-'));
  vi.stubEnv('DAILY_WEB_DB_PATH',path.join(directory,'db'));
  vi.stubEnv('DAILY_WEB_SECRET_KEY',randomBytes(32).toString('base64'));
  for(const id of ['owner','other'])getDb().prepare('INSERT INTO users(id,username,password_hash,is_admin,created_at) VALUES(?,?,?,?,?)').run(id,id,'unused',0,new Date().toISOString());
  connectionId=saveConnection('owner','tasks','Microsoft',{provider:'mstodo',clientId:'application',list:'Inbox'});
  vi.spyOn(mstodo,'fetchTasks').mockResolvedValue(parseTasks(JSON.stringify(fixture)));
});
afterEach(()=>{vi.restoreAllMocks();vi.unstubAllEnvs();rmSync(directory,{recursive:true,force:true});});

describe('personal task creation metadata',()=>{
  it.each(['todo','doing'] as const)('creates a local task in %s within its creation receipt',async status=>{
    const input={provider:'local',title:'Initial column',status,...metadata,...mutation()};
    const result=await run('tasks_create',input) as {id:string};
    expect(await run('tasks_create',input)).toEqual(result);
    expect(local.listTasks('owner')).toHaveLength(1);
    expect(await run('tasks_get',{provider:'local',id:result.id})).toMatchObject({task:{id:result.id,doing:status==='doing',completed:false}});
  });
  it('defaults new tasks to todo and rejects done before any provider effect',async()=>{
    const created=await run('tasks_create',{provider:'local',title:'Default column',...mutation()}) as {id:string};
    expect(await run('tasks_get',{provider:'local',id:created.id})).toMatchObject({task:{doing:false,completed:false}});
    const add=vi.spyOn(mstodo,'addTask').mockResolvedValue('created-id');
    for(const provider of ['local','mstodo'])await expect(run('tasks_create',{provider,connectionId,title:'Invalid column',status:'done',...mutation()})).rejects.toMatchObject({status:400});
    expect(add).not.toHaveBeenCalled();expect(local.listTasks('owner')).toHaveLength(1);
  });
  it('rolls back local creation when its initial board status cannot be written',async()=>{
    const input={provider:'local',title:'Initial column',status:'doing',...mutation()};
    const mark=vi.spyOn(board,'markDoing').mockImplementationOnce(()=>{throw new Error('board write failed');});
    await expect(run('tasks_create',input)).rejects.toMatchObject({code:'upstream_failed'});
    expect(local.listTasks('owner')).toEqual([]);
    mark.mockRestore();
    await run('tasks_create',input);
    expect(local.listTasks('owner')).toHaveLength(1);
  });
  it('creates a remote task in doing after metadata and replays without duplicate effects',async()=>{
    const add=vi.spyOn(mstodo,'addTask').mockResolvedValue('created-id');
    const edit=vi.spyOn(mstodo,'editTask').mockResolvedValue(undefined);
    const mark=vi.spyOn(board,'markDoing');
    const input={provider:'mstodo',connectionId,title:'Initial column',status:'doing',...metadata,...mutation()};
    const result=await run('tasks_create',input);
    expect(await run('tasks_create',input)).toEqual(result);
    expect(add).toHaveBeenCalledTimes(1);expect(edit).toHaveBeenCalledTimes(1);expect(mark).toHaveBeenCalledTimes(1);
    expect(mark.mock.invocationCallOrder[0]).toBeGreaterThan(edit.mock.invocationCallOrder[0]);
    vi.mocked(mstodo.fetchTasks).mockResolvedValue([{...parseTasks(JSON.stringify(fixture))[0],id:'created-id',completed:false}]);
    expect(await run('tasks_get',{provider:'mstodo',connectionId,id:'created-id'})).toMatchObject({task:{doing:true}});
  });
  it('retains the created remote task ID if the initial board write fails and blocks duplicate creation',async()=>{
    const add=vi.spyOn(mstodo,'addTask').mockResolvedValue('created-id');
    const edit=vi.spyOn(mstodo,'editTask').mockResolvedValue(undefined);
    const mark=vi.spyOn(board,'markDoing').mockImplementation(()=>{throw new Error('private board failure');});
    const input={provider:'mstodo',connectionId,title:'Initial column',status:'doing',...metadata,...mutation()};
    for(let attempt=0;attempt<2;attempt++)await expect(run('tasks_create',input)).rejects.toMatchObject({code:'uncertain_outcome',cause:{outcome:{id:'created-id',code:'task_board_unconfirmed'}}});
    expect(add).toHaveBeenCalledTimes(1);expect(edit).toHaveBeenCalledTimes(1);expect(mark).toHaveBeenCalledTimes(1);
    expect(getDb().prepare('SELECT typ_state AS state FROM tb_mutation_receipt').get()).toEqual({state:'unknown'});
  });

  it('creates local scheduling and priority atomically and replays the same task',async()=>{
    const input={provider:'local',title:'Scheduled',...metadata,...mutation()};
    const result=await run('tasks_create',input) as {id:string};
    expect(await run('tasks_create',input)).toEqual(result);
    expect(local.listTasks('owner')).toMatchObject([{id:result.id,title:'Scheduled',...metadata}]);
    expect(local.listTasks('other')).toEqual([]);
  });
  it('rolls back the local task and receipt when metadata writing fails',async()=>{
    const input={provider:'local',title:'Scheduled',...metadata,...mutation()};
    const edit=vi.spyOn(local,'editTask').mockImplementationOnce(()=>{throw new Error('write failed');});
    await expect(run('tasks_create',input)).rejects.toMatchObject({code:'upstream_failed'});
    expect(local.listTasks('owner')).toEqual([]);
    edit.mockRestore();
    await run('tasks_create',input);
    expect(local.listTasks('owner')).toHaveLength(1);
  });
  it('creates and edits the selected remote task exactly once with a stable replay',async()=>{
    const add=vi.spyOn(mstodo,'addTask').mockResolvedValue('created-id');
    const edit=vi.spyOn(mstodo,'editTask').mockResolvedValue(undefined);
    const input={provider:'mstodo',connectionId,title:'Scheduled',...metadata,...mutation()};
    expect(await run('tasks_create',input)).toEqual({ok:true,id:'created-id'});
    expect(await run('tasks_create',input)).toEqual({ok:true,id:'created-id'});
    expect(add).toHaveBeenCalledTimes(1);
    expect(edit).toHaveBeenCalledTimes(1);
    expect(edit).toHaveBeenCalledWith(expect.any(Object),'created-id',metadata);
  });
  it('retains a safe created ID after a metadata failure and never repeats creation',async()=>{
    const add=vi.spyOn(mstodo,'addTask').mockResolvedValue('created-id');
    const edit=vi.spyOn(mstodo,'editTask').mockRejectedValue(new Error('private provider payload'));
    const input={provider:'mstodo',connectionId,title:'Scheduled',...metadata,...mutation()};
    for(let attempt=0;attempt<2;attempt++){
      try{await run('tasks_create',input);expect.fail('Expected uncertainty');}
      catch(error){
        expect(error).toMatchObject({code:'uncertain_outcome',cause:expect.any(ExternalPartialOutcome)});
        expect((error as Error).cause).toMatchObject({outcome:{id:'created-id',code:'task_metadata_unconfirmed'}});
        expect(JSON.stringify(error)).not.toContain('private provider payload');
      }
    }
    expect(add).toHaveBeenCalledTimes(1);expect(edit).toHaveBeenCalledTimes(1);
    expect(getDb().prepare('SELECT typ_state AS state FROM tb_mutation_receipt').get()).toEqual({state:'unknown'});
  });
  for(const id of ['', '-flag', 'bad id', null, {id:'nested'}]){
    it(`fails closed on an unsupported add result (${JSON.stringify(id)}) without editing or retrying`,async()=>{
      const add=vi.spyOn(mstodo,'addTask').mockResolvedValue(id as never);
      const edit=vi.spyOn(mstodo,'editTask').mockResolvedValue(undefined);
      const input={provider:'mstodo',connectionId,title:'Scheduled',...metadata,...mutation()};
      for(let attempt=0;attempt<2;attempt++)await expect(run('tasks_create',input)).rejects.toMatchObject({code:'uncertain_outcome',cause:{outcome:{code:'created_task_unidentified'}}});
      expect(add).toHaveBeenCalledTimes(1);expect(edit).not.toHaveBeenCalled();
    });
  }
  for(const values of [{recur:'daily'},{time:'12:30'},{due:'',recur:'monthly'},{due:'2030-02-31'},{time:'25:00'},{recur:'absoluteMonthly'}]){
    it(`rejects invalid scheduling before remote effects (${JSON.stringify(values)})`,async()=>{
      const add=vi.spyOn(mstodo,'addTask').mockResolvedValue('created-id');
      await expect(run('tasks_create',{provider:'mstodo',connectionId,title:'Scheduled',...values,...mutation()})).rejects.toMatchObject({status:400});
      expect(add).not.toHaveBeenCalled();expect(mstodo.fetchTasks).not.toHaveBeenCalled();
    });
  }
  it('checks scope and connection ownership before creating remotely',async()=>{
    const add=vi.spyOn(mstodo,'addTask').mockResolvedValue('created-id');
    const input={provider:'mstodo',connectionId,title:'Scheduled',...metadata,...mutation()};
    await expect(run('tasks_create',input,{...principal,scopes:['tasks:read']})).rejects.toMatchObject({status:403});
    await expect(run('tasks_create',input,{...principal,userId:'other'})).rejects.toMatchObject({status:404});
    expect(add).not.toHaveBeenCalled();
  });
});

describe('effective task scheduling validation',()=>{
  for(const provider of ['local','mstodo'] as const){
    it(`validates stored recurrence and time on ${provider} edits`,async()=>{
      const task=provider==='local'
        ? {id:local.addTask('owner','Scheduled')}
        : parseTasks(JSON.stringify(fixture))[0];
      const input={provider,...(provider==='mstodo'?{connectionId}:{}),id:task.id};
      if(provider==='local')local.editTask('owner',task.id,{...metadata,priority:'high',recur:'monthly'});
      else vi.mocked(mstodo.fetchTasks).mockResolvedValue([{...parseTasks(JSON.stringify(fixture))[0],...metadata,priority:'high'}]);
      const edit=vi.spyOn(mstodo,'editTask').mockResolvedValue(undefined);
      for(const patch of [{due:''},{due:'',recur:'none'},{due:'',time:''}]){
        await expect(run('tasks_edit',{...input,...patch,...mutation()})).rejects.toMatchObject({status:400});
      }
      expect(edit).not.toHaveBeenCalled();
      const clear={...input,due:'',time:'',recur:'none',...mutation()};
      await run('tasks_edit',clear);await run('tasks_edit',clear);
      if(provider==='local')expect(local.listTasks('owner')[0]).toMatchObject({due:'',time:'',recur:''});
      else{expect(edit).toHaveBeenCalledTimes(1);expect(edit).toHaveBeenCalledWith(expect.any(Object),task.id,expect.objectContaining({due:'none',time:'none',recur:'none'}));}
    });
    it(`rejects enabling recurrence without a stored due date on ${provider}`,async()=>{
      const task=provider==='local'?{id:local.addTask('owner','Undated')}:parseTasks(JSON.stringify(fixture))[0];
      if(provider==='mstodo')vi.mocked(mstodo.fetchTasks).mockResolvedValue([{...parseTasks(JSON.stringify(fixture))[0],due:'',time:'',recur:''}]);
      const edit=vi.spyOn(mstodo,'editTask').mockResolvedValue(undefined);
      await expect(run('tasks_edit',{provider,...(provider==='mstodo'?{connectionId}:{}),id:task.id,recur:'daily',...mutation()})).rejects.toMatchObject({status:400});
      expect(edit).not.toHaveBeenCalled();
    });
  }
  it('accepts known monthly provider output while rejecting an unknown recurrence',async()=>{
    const task=parseTasks(JSON.stringify(fixture))[0];
    vi.mocked(mstodo.fetchTasks).mockResolvedValue(parseTasks(JSON.stringify([{...task,recur:'absoluteMonthly'}])));
    expect(await run('tasks_get',{provider:'mstodo',connectionId,id:task.id})).toMatchObject({task:{recur:'monthly'}});
    vi.mocked(mstodo.fetchTasks).mockResolvedValue(parseTasks(JSON.stringify([{...task,recur:'future-pattern'}])));
    await expect(run('tasks_get',{provider:'mstodo',connectionId,id:task.id})).rejects.toMatchObject({code:'invalid_result'});
  });
});

describe('task note colour parity',()=>{
  it('accepts every colour in the maintained paper and pin palettes',async()=>{
    const id=local.addTask('owner','Palette');
    for(const paper of NOTE_PAPERS){
      await run('tasks_edit',{provider:'local',id,boardStyle:{paper},...mutation()});
      expect(await run('tasks_get',{provider:'local',id})).toMatchObject({task:{paper}});
    }
    for(const pin of PIN_COLORS){
      await run('tasks_edit',{provider:'local',id,boardStyle:{pin},...mutation()});
      expect(await run('tasks_get',{provider:'local',id})).toMatchObject({task:{pin}});
    }
  });
  it('rolls back local detail edits when a composite style write fails',async()=>{
    const styles=await import('@/lib/tasks/boardStyle');
    const id=local.addTask('owner','Original');
    vi.spyOn(styles,'setBoardStyle').mockImplementationOnce(()=>{throw new Error('write failure');});
    await expect(run('tasks_edit',{provider:'local',id,title:'Changed',boardStyle:{pin:'blue'},...mutation()})).rejects.toMatchObject({code:'upstream_failed'});
    expect(local.listTasks('owner')[0]).toMatchObject({title:'Original'});
    expect(styles.boardStyleOf('owner',id)).toEqual({paper:null,pin:null});
  });

  it.each(['local','mstodo'] as const)('creates %s tasks with typed paper and pin colours and stable replay',async provider=>{
    const add=vi.spyOn(mstodo,'addTask').mockResolvedValue('created-style');
    const edit=vi.spyOn(mstodo,'editTask').mockResolvedValue(undefined);
    const input={provider,...(provider==='mstodo'?{connectionId}:{}),title:'Coloured task',boardStyle:{paper:'blue',pin:'red'},...mutation()};
    const result=await run('tasks_create',input) as {id:string};
    expect(await run('tasks_create',input)).toEqual(result);
    if(provider==='mstodo')vi.mocked(mstodo.fetchTasks).mockResolvedValue([{...parseTasks(JSON.stringify(fixture))[0],id:result.id}]);
    expect(await run('tasks_get',{provider,...(provider==='mstodo'?{connectionId}:{}),id:result.id})).toMatchObject({task:{paper:'blue',pin:'red'}});
    expect((await run('tasks_list',{provider,...(provider==='mstodo'?{connectionId}:{})}) as {items:unknown[]}).items).toMatchObject([{paper:'blue',pin:'red'}]);
    expect(add).toHaveBeenCalledTimes(provider==='mstodo'?1:0);expect(edit).not.toHaveBeenCalled();
  });
  it.each(['local','mstodo'] as const)('updates and resets %s note colours without a provider write',async provider=>{
    const id=provider==='local'?local.addTask('owner','Coloured task'):parseTasks(JSON.stringify(fixture))[0].id;
    const target={provider,...(provider==='mstodo'?{connectionId}:{}),id};
    const edit=vi.spyOn(mstodo,'editTask').mockResolvedValue(undefined);
    const paper={...target,boardStyle:{paper:'pink'},...mutation()};
    await run('tasks_edit',paper);await run('tasks_edit',paper);
    await run('tasks_edit',{...target,boardStyle:{pin:'green'},...mutation()});
    expect(await run('tasks_get',target)).toMatchObject({task:{paper:'pink',pin:'green'}});
    await run('tasks_edit',{...target,boardStyle:{paper:null},...mutation()});
    expect(await run('tasks_get',target)).toMatchObject({task:{paper:null,pin:'green'}});
    await run('tasks_edit',{...target,boardStyle:{pin:null},...mutation()});
    expect(await run('tasks_get',target)).toMatchObject({task:{paper:null,pin:null}});
    expect(edit).not.toHaveBeenCalled();
    expect(getDb().prepare('SELECT DISTINCT typ_class AS kind FROM tb_mutation_receipt').all()).toEqual([{kind:'local'}]);
  });
  it.each([{paper:'purple'},{pin:'pink'},{paper:42},{unknown:'red'},{}])('rejects invalid colours before effects (%j)',async boardStyle=>{
    const add=vi.spyOn(mstodo,'addTask').mockResolvedValue('created-style');
    for(const name of ['tasks_create','tasks_edit'])await expect(run(name,{provider:'mstodo',connectionId,...(name==='tasks_create'?{title:'New'}:{id:'T1'}),boardStyle,...mutation()})).rejects.toMatchObject({status:400});
    expect(add).not.toHaveBeenCalled();expect(mstodo.fetchTasks).not.toHaveBeenCalled();
  });
  it('fails closed for scope, foreign connections and absent local or remote tasks',async()=>{
    const input={provider:'mstodo',connectionId,id:'T1',boardStyle:{paper:'white'},...mutation()};
    const edit=vi.spyOn(mstodo,'editTask').mockResolvedValue(undefined);
    await expect(run('tasks_edit',input,{...principal,scopes:['tasks:read']})).rejects.toMatchObject({status:403});
    await expect(run('tasks_edit',input,{...principal,userId:'other'})).rejects.toMatchObject({status:404});
    expect(mstodo.fetchTasks).not.toHaveBeenCalled();
    await expect(run('tasks_edit',{...input,id:'absent'})).rejects.toMatchObject({status:404});
    await expect(run('tasks_edit',{...input,provider:'local',id:'absent'})).rejects.toMatchObject({status:404});
    expect(edit).not.toHaveBeenCalled();
    expect(getDb().prepare('SELECT COUNT(*) AS count FROM task_board_style').get()).toEqual({count:0});
  });
  it('rolls back local task creation if its colour cannot be saved',async()=>{
    const styles=await import('@/lib/tasks/boardStyle');
    const save=vi.spyOn(styles,'setBoardStyle').mockImplementationOnce(()=>{throw new Error('write failure');});
    const input={provider:'local',title:'New',boardStyle:{paper:'yellow'},...metadata,...mutation()};
    await expect(run('tasks_create',input)).rejects.toMatchObject({code:'upstream_failed'});
    expect(local.listTasks('owner')).toEqual([]);
    save.mockRestore();await run('tasks_create',input);expect(local.listTasks('owner')).toHaveLength(1);
  });
  it.each(['tasks_create','tasks_edit'])('retains a safe outcome when remote details succeed but %s styling fails',async name=>{
    const styles=await import('@/lib/tasks/boardStyle');
    const save=vi.spyOn(styles,'setBoardStyle').mockImplementation(()=>{throw new Error('private storage error');});
    const add=vi.spyOn(mstodo,'addTask').mockResolvedValue('created-style');
    const edit=vi.spyOn(mstodo,'editTask').mockResolvedValue(undefined);
    const input={provider:'mstodo',connectionId,...(name==='tasks_edit'?{id:'T1'}:{}),title:'Updated',boardStyle:{paper:'grey'},...mutation()};
    for(let attempt=0;attempt<2;attempt++)await expect(run(name,input)).rejects.toMatchObject({code:'uncertain_outcome',cause:{outcome:{id:name==='tasks_create'?'created-style':'T1',code:'task_style_unconfirmed'}}});
    expect(add).toHaveBeenCalledTimes(name==='tasks_create'?1:0);expect(edit).toHaveBeenCalledTimes(name==='tasks_edit'?1:0);expect(save).toHaveBeenCalledTimes(1);
  });
  it.each(['local','mstodo'] as const)('clears %s style on deletion and keeps owner styles isolated',async provider=>{
    const styles=await import('@/lib/tasks/boardStyle');
    const id=provider==='local'?local.addTask('owner','Delete task'):'T1';
    styles.setBoardStyle('owner',id,{paper:'green',pin:'yellow'});
    styles.setBoardStyle('other',id,{paper:'blue'});
    vi.spyOn(mstodo,'deleteTask').mockResolvedValue(undefined);
    await run('tasks_delete',{provider,...(provider==='mstodo'?{connectionId}:{}),id,...mutation()});
    expect(styles.boardStyleOf('owner',id)).toEqual({paper:null,pin:null});
    expect(styles.boardStyleOf('other',id)).toEqual({paper:'blue',pin:null});
  });
});
