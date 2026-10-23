import { createServer } from 'node:http';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { performance } from 'node:perf_hooks';
import { randomUUID } from 'node:crypto';
import { getDb } from '../../lib/db';
import { createCredential } from '../../lib/access/credentials';
import { registerAgent, createSession } from '../../lib/agents/operations';
import { cleanupAgents } from '../../lib/agents/retention';
import { RETENTION_MS } from '../../lib/agents/model';
import { GET as getTasks } from '../../app/api/v1/agents/tasks/route';
import { POST as postActivity } from '../../app/api/v1/agents/tasks/[id]/activity/route';

const reportPath=process.argv[2]??'/tmp/daily-agents-performance.json';
const directory=mkdtempSync(path.join(tmpdir(),'daily-performance-'));
process.env.DAILY_WEB_DB_PATH=path.join(directory,'benchmark.db');
const db=getDb();
const users=20,sessions=100,tasks=10000,reportCount=100,rate=10;
const secrets:string[]=[];
const targets:{user:number;taskId:string}[]=[];
const seededAt=new Date(Date.now()-600000).toISOString();
const mutation=()=>({key:randomUUID(),requestedAt:new Date().toISOString()});
for(let user=0;user<users;user++){
 const owner=`benchmark-user-${user}`;
 db.prepare('INSERT INTO users(id,username,password_hash,is_admin,created_at) VALUES(?,?,?,?,?)').run(owner,owner,'benchmark-account-login-disabled',0,seededAt);
 secrets.push(createCredential(owner,{label:'Temporary benchmark',scopes:['agents:read','agents:write']}).secret);
}
const insert=db.prepare("INSERT INTO main.tb_agent_task(uid_task,uid_user,ref_external,nam_title,txt_description,typ_status,uid_session,num_version,tsz_insert,tsz_update) VALUES(?,?,?,?,?,'working',?,1,?,?)");
for(let sessionIndex=0;sessionIndex<sessions;sessionIndex++){
 const user=sessionIndex%users,owner=`benchmark-user-${user}`;
 const agent=registerAgent(owner,{externalId:`agent-${sessionIndex}`,provider:(['claude','codex','gemini'] as const)[sessionIndex%3],displayName:`Benchmark agent ${sessionIndex}`},mutation());
 const session=createSession(owner,{agentId:agent.id,externalId:`session-${sessionIndex}`},mutation());
 db.transaction(()=>{for(let j=0;j<tasks/sessions;j++){
  const id=randomUUID();insert.run(id,owner,`task-${sessionIndex}-${j}`,`Benchmark task ${sessionIndex}-${j}`,'Synthetic benchmark data',session.id,seededAt,seededAt);
  if(j===0)targets.push({user,taskId:id});
 }})();
}
let active=0,peakActive=0;
let peakRss=process.memoryUsage().rss;
const memoryBefore=process.memoryUsage();
const memoryTimer=setInterval(()=>{peakRss=Math.max(peakRss,process.memoryUsage().rss);},100);
const server=createServer(async(req,res)=>{
 active++;peakActive=Math.max(peakActive,active);
 try{
  const chunks:Buffer[]=[];for await(const chunk of req)chunks.push(Buffer.from(chunk));
  const headers=new Headers();for(const [key,value] of Object.entries(req.headers))if(value!==undefined)headers.set(key,Array.isArray(value)?value.join(','):value);
  const web=new Request(`http://127.0.0.1${req.url}`,{method:req.method,headers,...(chunks.length?{body:Buffer.concat(chunks)}:{})});
  const match=/^\/api\/v1\/agents\/tasks\/([^/]+)\/activity$/.exec(req.url??'');
  const result=req.method==='POST'&&match ? await postActivity(web,{params:Promise.resolve({id:match[1]})}) : req.method==='GET'&&req.url==='/api/v1/agents/tasks?limit=100' ? await getTasks(web) : new Response(null,{status:404});
  res.writeHead(result.status,Object.fromEntries(result.headers));res.end(Buffer.from(await result.arrayBuffer()));
 }catch{res.statusCode=500;res.end();}finally{active--;}
});
await new Promise<void>(resolve=>server.listen(0,'127.0.0.1',resolve));
const address=server.address();if(!address||typeof address==='string')throw new Error('Missing benchmark listener');
const origin=`http://127.0.0.1:${address.port}`;
const acceptedMs:number[]=[],visibleMs:number[]=[],queueLagMs:number[]=[];
const errors:Record<string,number>={};
const started=performance.now();
try{
 await Promise.all(Array.from({length:reportCount},async(_,index)=>{
  const scheduled=started+index*(1000/rate);
  await new Promise(resolve=>setTimeout(resolve,Math.max(0,scheduled-performance.now())));
  const begin=performance.now();queueLagMs.push(begin-scheduled);
  const target=targets[index%sessions];
  const response=await fetch(`${origin}/api/v1/agents/tasks/${target.taskId}/activity`,{method:'POST',headers:{'Content-Type':'application/json',Authorization:`Bearer ${secrets[target.user]}`,'Idempotency-Key':randomUUID(),'X-Request-Timestamp':new Date().toISOString()},body:JSON.stringify({kind:'progress',summary:`Synthetic progress ${index}`}),signal:AbortSignal.timeout(5000)});
  if(response.status!==200){const key=`report_http_${response.status}`;errors[key]=(errors[key]??0)+1;return;}
  const accepted=await response.json() as {lastActivityAt:string};acceptedMs.push(performance.now()-begin);
  for(let attempt=0;attempt<50;attempt++){
   const poll=await fetch(`${origin}/api/v1/agents/tasks?limit=100`,{headers:{Authorization:`Bearer ${secrets[target.user]}`},signal:AbortSignal.timeout(5000)});
   if(poll.status!==200){const key=`poll_http_${poll.status}`;errors[key]=(errors[key]??0)+1;return;}
   const snapshot=await poll.json() as {items:{id:string;lastActivityAt:string}[]};
   if(snapshot.items.some(task=>task.id===target.taskId&&task.lastActivityAt===accepted.lastActivityAt)){visibleMs.push(performance.now()-begin);return;}
   await new Promise(resolve=>setTimeout(resolve,100));
  }
  errors.visibility_timeout=(errors.visibility_timeout??0)+1;
 }));
 const wallMs=performance.now()-started;
 const expiredAt=new Date(Date.now()-RETENTION_MS-1).toISOString();
 db.transaction(()=>{for(let i=0;i<500;i++)insert.run(randomUUID(),'benchmark-user-0',`expired-${i}`,'Expired synthetic task','',null,expiredAt,expiredAt);})();
 const cleanupStart=performance.now(),cleanup=cleanupAgents(),cleanupMs=performance.now()-cleanupStart;
 function distribution(values:number[]){const ordered=[...values].sort((a,b)=>a-b);const quantile=(q:number)=>ordered[Math.max(0,Math.ceil(ordered.length*q)-1)]??null;return {samples:values.length,p50:quantile(.5),p95:quantile(.95),p99:quantile(.99),maximum:ordered.at(-1)??null};}
 peakRss=Math.max(peakRss,process.memoryUsage().rss);
 const result={recordedAt:new Date().toISOString(),scope:'Isolated Node HTTP server invokes real reporting Next route handlers; reads use the same owner-scoped listTasks operation as the browser snapshot. This does not measure Next middleware, React rendering, production proxy, or browser-visible latency.',environment:{node:process.version,platform:process.platform,arch:process.arch},workload:{users,sessions,retainedTasks:tasks,reports:reportCount,scheduledReportsPerSecond:rate,wallMs},httpAcceptanceMs:distribution(acceptedMs),reportToSnapshotPollMs:distribution(visibleMs),schedulingLagMs:distribution(queueLagMs),server:{peakConcurrentRequests:peakActive},memory:{rssBeforeBytes:memoryBefore.rss,rssPeakBytes:peakRss,rssAfterBytes:process.memoryUsage().rss,heapUsedBeforeBytes:memoryBefore.heapUsed,heapUsedAfterBytes:process.memoryUsage().heapUsed},cleanup:{batchLimit:500,elapsedMs:cleanupMs,...cleanup},errors,pass:Object.keys(errors).length===0&&visibleMs.length===reportCount&&((distribution(visibleMs).p95??Infinity)<=5000)};
 writeFileSync(reportPath,JSON.stringify(result,null,2)+'\n',{mode:0o600});
 console.log(JSON.stringify({reportPath,pass:result.pass,reports:visibleMs.length,p95SnapshotPollMs:result.reportToSnapshotPollMs.p95,p99SnapshotPollMs:result.reportToSnapshotPollMs.p99,cleanupMs,peakRssBytes:peakRss,errors}));
 if(!result.pass)process.exitCode=1;
}finally{
 clearInterval(memoryTimer);
 await new Promise<void>(resolve=>server.close(()=>resolve()));
 db.close();rmSync(directory,{recursive:true,force:true});
}
