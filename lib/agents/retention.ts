import { getDb } from '@/lib/db';
import { RETENTION_MS } from './model';
interface CleanupCounts { tasks:number; activity:number; sessions:number; agents:number; receipts:number }
const empty=():CleanupCounts=>({tasks:0,activity:0,sessions:0,agents:0,receipts:0});
let phase:'idle'|'running'='idle';
export function cleanupAgents(now=Date.now(),batch=500):CleanupCounts {
  if(!Number.isInteger(batch)||batch<1||batch>500)throw new Error('Invalid cleanup batch');
  if(phase==='running')return empty();
  phase='running';
  try {
    const db=getDb();
    const result=db.transaction(()=>{
      const before=new Date(now-RETENTION_MS).toISOString();
      let remaining=batch;
      const result=empty();
      result.activity=db.prepare(`DELETE FROM main.tb_agent_activity WHERE uid_activity IN (
        SELECT uid_activity FROM main.tb_agent_activity WHERE tsz_insert<=? ORDER BY tsz_insert,uid_activity LIMIT ?
      )`).run(before,remaining).changes;
      remaining-=result.activity;
      result.receipts=db.prepare(`DELETE FROM main.tb_mutation_receipt WHERE uid_receipt IN (
        SELECT uid_receipt FROM main.tb_mutation_receipt WHERE tsz_expires<=? AND typ_state NOT IN ('pending','unknown') ORDER BY tsz_expires LIMIT ?
      )`).run(new Date(now).toISOString(),remaining).changes;
      remaining-=result.receipts;
      const coupled=db.prepare(`DELETE FROM main.tb_mutation_receipt WHERE uid_receipt IN (
        SELECT r.uid_receipt FROM main.tb_agent_task t JOIN main.tb_mutation_receipt r
        ON r.uid_user=t.uid_user AND r.ref_resource=t.uid_task
        WHERE t.tsz_update<=? AND r.typ_class='local' AND r.typ_state!='deleted' LIMIT ?
      )`).run(before,remaining).changes;
      result.receipts+=coupled;
      remaining-=coupled;
      result.tasks=db.prepare(`DELETE FROM main.tb_agent_task WHERE uid_task IN (
        SELECT t.uid_task FROM main.tb_agent_task t WHERE t.tsz_update<=?
        AND NOT EXISTS(SELECT 1 FROM main.tb_agent_activity a WHERE a.uid_user=t.uid_user AND a.uid_task=t.uid_task)
        AND NOT EXISTS(SELECT 1 FROM main.tb_mutation_receipt r WHERE r.uid_user=t.uid_user AND r.ref_resource=t.uid_task AND r.typ_class='local' AND r.typ_state!='deleted')
        ORDER BY t.tsz_update,t.uid_task LIMIT ?
      )`).run(before,remaining).changes;
      remaining-=result.tasks;
      result.sessions=db.prepare(`DELETE FROM main.tb_agent_session WHERE uid_session IN (
        SELECT s.uid_session FROM main.tb_agent_session s WHERE s.tsz_update<=?
        AND NOT EXISTS(SELECT 1 FROM main.tb_agent_task t WHERE t.uid_session=s.uid_session) LIMIT ?
      )`).run(before,remaining).changes;
      remaining-=result.sessions;
      result.agents=db.prepare(`DELETE FROM main.tb_agent WHERE uid_agent IN (
        SELECT a.uid_agent FROM main.tb_agent a WHERE a.tsz_update<=?
        AND NOT EXISTS(SELECT 1 FROM main.tb_agent_session s WHERE s.uid_agent=a.uid_agent) LIMIT ?
      )`).run(before,remaining).changes;
      return result;
    }).immediate();
    const checkpoint=db.pragma('wal_checkpoint(TRUNCATE)') as {busy:number}[];
    if(checkpoint.some(row=>row.busy!==0))console.error('Agent retention WAL checkpoint remains busy');
    return result;
  } finally { phase='idle'; }
}
const state=globalThis as typeof globalThis & {
  agentCleanupTimer?:ReturnType<typeof setInterval>;
  agentCleanupContinuation?:ReturnType<typeof setTimeout>;
  agentCleanupPhase?:'idle'|'running';
};
export function startAgentCleanup():void {
  if(state.agentCleanupTimer)return;
  const run=async()=>{
    if(state.agentCleanupPhase==='running')return;
    state.agentCleanupPhase='running';
    let more=false;
    try {
      const deadline=Date.now()+5000;
      do {
        const result=cleanupAgents();
        const count=Object.values(result).reduce((sum,value)=>sum+value,0);
        more=count===500;
        if(count)console.info('Agent retention cleanup',result);
        if(more)await new Promise<void>(resolve=>setImmediate(resolve));
      } while(more&&Date.now()<deadline);
    } catch {console.error('Agent retention cleanup failed');}
    finally {
      state.agentCleanupPhase='idle';
      if(more){state.agentCleanupContinuation=setTimeout(()=>void run(),1000);state.agentCleanupContinuation.unref?.();}
    }
  };
  void run();
  state.agentCleanupTimer=setInterval(()=>void run(),3600000);
  state.agentCleanupTimer.unref?.();
}
