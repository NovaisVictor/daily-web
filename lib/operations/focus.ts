import { z } from 'zod';
import { operation, connection, mutationShape, mutate } from './context';
import { requireScope, AccessError } from '@/lib/access/principal';
import { listConnections } from '@/lib/vault/connections';
import { canWriteEvents } from '@/lib/integrations/agenda';
import { createFocusBlock } from '@/lib/integrations/google/calendar';
import { fetchByKeys } from '@/lib/integrations/jiraApi';
import { githubToken, githubRequest } from '@/lib/integrations/githubApi';
import { readPersonalTask } from './tasks';
import { dropCache } from '@/lib/refresher';

export const focusOperations=[
  operation('focus_targets','List writable agenda connections for focus blocks','agenda:focus','read',{},async(p)=>({targets:listConnections(p.userId,'agenda').filter(canWriteEvents).map(c=>({id:c.id,label:c.label}))})),
  operation('focus_create','Schedule a focus block for an authorized task, Jira issue or pull request','agenda:focus','write',{
    ...mutationShape,connectionId:z.string().min(1),kind:z.enum(['task','jira','pull']),taskProvider:z.enum(['local','mstodo']).optional(),sourceConnectionId:z.string().optional(),ref:z.string().min(1).max(100),start:z.iso.datetime({offset:true}),minutes:z.union([z.literal(25),z.literal(50),z.literal(90),z.literal(120)]),
  },async(p,i)=>{
    const agenda=connection(p,i.connectionId,'agenda','agenda:focus');if(!canWriteEvents(agenda))throw new AccessError(409,'reconnect_required','Reconnect this calendar to grant event access');
    return mutate(p,'focus_create',{id:i.ref,connectionId:agenda.id},i,async()=>{
    const start=new Date(i.start);if(start.getTime()<Date.now()-300_000||start.getTime()>Date.now()+60*86400_000)throw new AccessError(400,'invalid_start','Choose a focus start within the next 60 days');
    let title:string;
    if(i.kind==='task'){
      requireScope(p,'tasks:read');if(!i.taskProvider)throw new AccessError(400,'provider_required','Choose the task provider');const task=await readPersonalTask(p,{provider:i.taskProvider,connectionId:i.sourceConnectionId,id:i.ref});title=task.title;
    } else if(i.kind==='jira'){
      if(!i.sourceConnectionId||!/^[A-Z][A-Z0-9_]*-\d+$/.test(i.ref))throw new AccessError(400,'invalid_source','Choose a Jira issue and connection');
      const source=connection(p,i.sourceConnectionId,'jira','jira:read');const [issue]=await fetchByKeys(source,[i.ref]);if(!issue)throw new AccessError(404,'not_found','Issue not found');title=`${issue.key} — ${issue.summary}`;
    } else {
      if(!i.sourceConnectionId)throw new AccessError(400,'invalid_source','Choose a GitHub connection');
      const matched=/^([A-Za-z0-9-]+)\/([A-Za-z0-9_.-]+)#([1-9]\d*)$/.exec(i.ref);if(!matched)throw new AccessError(400,'invalid_source','Use owner/repo#number');
      const source=connection(p,i.sourceConnectionId,'pulls','github:read');const raw=await githubRequest(githubToken(source),`/repos/${encodeURIComponent(matched[1])}/${encodeURIComponent(matched[2])}/pulls/${matched[3]}`);
      const parsed=z.object({title:z.string().min(1)}).parse(raw);title=`${i.ref} — ${parsed.title}`;
    }
      await createFocusBlock(agenda,{title:`🔒 ${title}`.slice(0,200),description:'Bloco de foco criado pelo Daily Web.',start,end:new Date(start.getTime()+i.minutes*60_000)});
      dropCache(p.userId);return {ok:true};
    });
  }),
];
