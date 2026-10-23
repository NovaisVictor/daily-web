import { readFileSync,writeFileSync } from 'node:fs';
import {execFileSync} from 'node:child_process';
import {randomUUID} from 'node:crypto';
import {performance} from 'node:perf_hooks';
import {chromium} from 'playwright';
import {getDb} from '../../lib/db';
import {createCredential} from '../../lib/access/credentials';
import {createSessionToken,SESSION_COOKIE} from '../../lib/auth/session';
import {registerAgent,createSession} from '../../lib/agents/operations';

const environmentPath=process.argv[2];if(!environmentPath)throw new Error('Pass the disposable acceptance runtime environment file');
const runtime=JSON.parse(readFileSync(environmentPath,'utf8')) as Record<string,string>;
Object.assign(process.env,runtime);
const origin=new URL(runtime.PUBLIC_ORIGIN);if(!['localhost','127.0.0.1'].includes(origin.hostname))throw new Error('Only a disposable loopback acceptance runtime is allowed');
const reportPath=process.argv[3]??'/tmp/daily-agents-browser-performance.json';
const db=getDb(),users=20,sessions=100,tasks=10000,reports=100,rate=10;
const reuse=process.argv.includes('--reuse-seed');
let runId:string=randomUUID();
if(reuse){
 const candidates=db.prepare("SELECT username FROM users WHERE username LIKE 'load-%'").all() as {username:string}[];
 const groups=new Map<string,Set<number>>();
 for(const candidate of candidates){const match=/^load-([a-f0-9-]{36})-(\d+)$/.exec(candidate.username);if(match){const indexes=groups.get(match[1])??new Set<number>();indexes.add(Number(match[2]));groups.set(match[1],indexes);}}
 const complete=[...groups].filter(([,indexes])=>indexes.size===users&&Array.from({length:users},(_,index)=>index).every(index=>indexes.has(index)));
 if(complete.length!==1)throw new Error('Seed reuse requires exactly one complete synthetic benchmark namespace; no records were removed');
 runId=complete[0][0];
}
const owner=(i:number)=>`load-${runId}-${i}`;
const tokens:string[]=[],cookies:string[]=[],targets:{user:number;taskId:string}[]=[];
const at=new Date(Date.now()-600000).toISOString(),mutation=()=>({key:randomUUID(),requestedAt:new Date().toISOString()});
for(let i=0;i<users;i++){
 if(!reuse)db.prepare('INSERT INTO users(id,username,password_hash,is_admin,created_at) VALUES(?,?,?,?,?)').run(owner(i),owner(i),'benchmark-account-login-disabled',0,at);
 tokens.push(createCredential(owner(i),{label:'Temporary browser benchmark',scopes:['agents:read','agents:write']}).secret);
 cookies.push(await createSessionToken(owner(i),owner(i),runtime.SESSION_SECRET));
}
if(reuse){
 const owners=Array.from({length:users},(_,index)=>owner(index)),placeholders=owners.map(()=>'?').join(',');
 const total=db.prepare(`SELECT COUNT(*) AS count FROM main.tb_agent_task WHERE uid_user IN (${placeholders})`).get(...owners) as {count:number};
 const sessionTotal=db.prepare(`SELECT COUNT(*) AS count FROM main.tb_agent_session WHERE uid_user IN (${placeholders})`).get(...owners) as {count:number};
 if(total.count!==tasks||sessionTotal.count!==sessions)throw new Error('The preserved benchmark seed no longer matches the required workload');
 const rows=db.prepare(`SELECT uid_task AS taskId,uid_user AS owner,ref_external AS externalId FROM main.tb_agent_task WHERE uid_user IN (${placeholders}) AND ref_external LIKE 'task-%-0'`).all(...owners) as {taskId:string;owner:string;externalId:string}[];
 rows.sort((a,b)=>Number(a.externalId.split('-')[1])-Number(b.externalId.split('-')[1]));
 for(const row of rows)targets.push({user:owners.indexOf(row.owner),taskId:row.taskId});
 if(targets.length!==sessions)throw new Error('The preserved benchmark seed has unexpected session targets');
}else{
 const insert=db.prepare("INSERT INTO main.tb_agent_task(uid_task,uid_user,ref_external,nam_title,txt_description,typ_status,uid_session,num_version,tsz_insert,tsz_update) VALUES(?,?,?,?,?,'working',?,1,?,?)");
 for(let i=0;i<sessions;i++){
  const user=i%users;
  const agent=registerAgent(owner(user),{externalId:`agent-${i}`,provider:(['claude','codex','gemini'] as const)[i%3],displayName:`Load agent ${i}`},mutation());
  const session=createSession(owner(user),{agentId:agent.id,externalId:`session-${i}`},mutation());
  db.transaction(()=>{for(let j=0;j<tasks/sessions;j++){const id=randomUUID();insert.run(id,owner(user),`task-${i}-${j}`,`Load task ${i}-${j}`,'Synthetic browser benchmark data',session.id,at,at);if(j===0)targets.push({user,taskId:id});}})();
 }
}
const ids=targets.map(t=>t.taskId),wanted=new Set(ids);
const observedDom=new Map<string,number>(),observedSnapshot=new Map<string,number>();
const acceptance:number[]=[],expected:{id:string;at:string;begin:number}[]=[],errors:Record<string,number>={};
const key=(id:string,at:string)=>id+'|'+at;
let appPid='';try{appPid=execFileSync('lsof',['-t','-iTCP:8024','-sTCP:LISTEN'],{encoding:'utf8',timeout:3000}).trim().split('\n')[0];}catch{/* Server RSS remains unavailable when host tooling is absent. */}
let peakAppRss=0;const sampleMemory=()=>{if(appPid)try{const value=Number(execFileSync('ps',['-o','rss=','-p',appPid],{encoding:'utf8',timeout:1000}).trim())*1024;peakAppRss=Math.max(peakAppRss,value);}catch{/* The process may have stopped. */}};sampleMemory();const beforeAppRss=peakAppRss;
const browser=await chromium.launch({executablePath:'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',headless:true});
const pages=[];
try{
 for(let i=0;i<users;i++){
  const context=await browser.newContext({viewport:{width:1280,height:900},serviceWorkers:'block'});
  await context.addCookies([{name:SESSION_COOKIE,value:cookies[i],domain:origin.hostname,path:'/',httpOnly:true,secure:origin.protocol==='https:',sameSite:'Lax'}]);
  const page=await context.newPage();pages.push(page);
  await page.exposeFunction('recordLoadDom',(id:string,at:string)=>{const k=key(id,at);if(!observedDom.has(k))observedDom.set(k,performance.now());});
  await page.addInitScript(({ids})=>{
   const allowed=new Set(ids),seen=new Map<string,string>();
   const scan=()=>{document.querySelectorAll<HTMLAnchorElement>('a[href^="/agents/tasks/"]').forEach(link=>{const id=link.getAttribute('href')!.split('/').at(-1)!;const at=link.querySelector('time')?.getAttribute('datetime');if(allowed.has(id)&&at&&seen.get(id)!==at){seen.set(id,at);void (window as unknown as {recordLoadDom:(id:string,at:string)=>Promise<void>}).recordLoadDom(id,at);}});};
   const start=()=>{new MutationObserver(scan).observe(document.documentElement,{subtree:true,childList:true,attributes:true,attributeFilter:['datetime']});scan();};
   if(document.documentElement)start();else document.addEventListener('DOMContentLoaded',start,{once:true});
  },{ids});
  page.on('response',async response=>{if(!response.url().includes('/api/agents?'))return;try{const body=await response.json() as {tasks:{items:{id:string;lastActivityAt:string}[]}};const observed=performance.now();for(const task of body.tasks.items)if(wanted.has(task.id)&&!observedSnapshot.has(key(task.id,task.lastActivityAt)))observedSnapshot.set(key(task.id,task.lastActivityAt),observed);}catch{/* Non-success replies are counted by the report path and rendered by the UI. */}});
  await page.goto(origin.origin+'/',{waitUntil:'domcontentloaded',timeout:15000});
  await page.locator('h1').waitFor({timeout:15000});
  await page.waitForLoadState('networkidle',{timeout:15000});
 }
 const visibility=await Promise.all(pages.map(async page=>{await page.waitForFunction(()=>document.visibilityState==='visible',undefined,{timeout:15000});return 'visible';}));
 if(visibility.some(value=>value!=='visible'))throw new Error('All measured browser documents must be visible');
 const memoryTimer=setInterval(sampleMemory,500);
 const start=performance.now();
 try{
  await Promise.all(Array.from({length:reports},async(_,index)=>{
   await new Promise(resolve=>setTimeout(resolve,Math.max(0,start+index*(1000/rate)-performance.now())));
   const target=targets[index],begin=performance.now();
   try{
    const response=await fetch(`${origin.origin}/api/v1/agents/tasks/${target.taskId}/activity`,{method:'POST',headers:{'Content-Type':'application/json',Authorization:`Bearer ${tokens[target.user]}`,'Idempotency-Key':randomUUID(),'X-Request-Timestamp':new Date().toISOString()},body:JSON.stringify({kind:'progress',summary:`Synthetic browser progress ${index}`}),signal:AbortSignal.timeout(5000)});
    if(response.status!==200){errors[`report_http_${response.status}`]=(errors[`report_http_${response.status}`]??0)+1;return;}
    const task=await response.json() as {lastActivityAt:string};acceptance.push(performance.now()-begin);expected.push({id:target.taskId,at:task.lastActivityAt,begin});
   }catch{errors.transport_failure=(errors.transport_failure??0)+1;}
  }));
  const deadline=performance.now()+10000;while(expected.some(item=>!observedDom.has(key(item.id,item.at)))&&performance.now()<deadline)await new Promise(resolve=>setTimeout(resolve,100));
 }finally{clearInterval(memoryTimer);sampleMemory();}
 const dom=expected.flatMap(item=>observedDom.has(key(item.id,item.at))?[observedDom.get(key(item.id,item.at))!-item.begin]:[]),snapshot=expected.flatMap(item=>observedSnapshot.has(key(item.id,item.at))?[observedSnapshot.get(key(item.id,item.at))!-item.begin]:[]);
 const distribution=(values:number[])=>{const sorted=[...values].sort((a,b)=>a-b);const q=(p:number)=>sorted[Math.max(0,Math.ceil(sorted.length*p)-1)]??null;return {samples:sorted.length,p50:q(.5),p95:q(.95),p99:q(.99),maximum:sorted.at(-1)??null};};
 const result={recordedAt:new Date().toISOString(),scope:'Real disposable Next production app behind loopback proxy; twenty authenticated headless Chromium contexts with document.visibilityState=visible, service workers blocked for test stability, actual React card time[datetime] mutation observed during 10 accepted reports/second. Browser layout/rendering and its natural 2-second polling are included; physical display paint, production network and interactive real agents are not measured.',environment:{node:process.version,platform:process.platform,arch:process.arch,browser:browser.version(),headless:true},workload:{users,sessions,retainedTasks:tasks,reports,scheduledReportsPerSecond:rate,seedMode:reuse?'reused':'new'},visibility,acceptedHttpMs:distribution(acceptance),reportToBrowserSnapshotMs:distribution(snapshot),reportToReactDomMs:distribution(dom),appMemory:{rssBeforeBytes:beforeAppRss||null,rssPeakBytes:peakAppRss||null},errors,pass:Object.keys(errors).length===0&&dom.length===reports&&((distribution(dom).p95??Infinity)<=5000)};
 writeFileSync(reportPath,JSON.stringify(result,null,2)+'\n',{mode:0o600});
 console.log(JSON.stringify({reportPath,pass:result.pass,accepted:acceptance.length,domSamples:dom.length,p95DomMs:result.reportToReactDomMs.p95,p99DomMs:result.reportToReactDomMs.p99,appPeakRssBytes:peakAppRss,errors}));
 if(!result.pass)process.exitCode=1;
}finally{await browser.close();db.close();}
