import {afterEach,beforeEach,describe,expect,it,vi} from 'vitest';
import {cleanup,fireEvent,render,screen,waitFor,within} from '@testing-library/react';
import {TaskDetail} from '@/components/agents/TaskDetail';
import {AgentBoard} from '@/components/agents/AgentBoard';
import {parseSnapshot,parseTaskDetail} from '@/components/agents/contracts';
import captured from '@/tests/fixtures/agents/browser-contract.json';
import hierarchy from '@/tests/fixtures/agents/hierarchy-contract.json';

const navigation=vi.hoisted(()=>({params:new URLSearchParams(),replace:vi.fn(),push:vi.fn(),pathname:'/agents/tasks/root'}));
vi.mock('next/navigation',()=>({useSearchParams:()=>navigation.params,usePathname:()=>navigation.pathname,useRouter:()=>navigation}));
const now=new Date().toISOString();
const root={...hierarchy.parentDetail.task,id:'root',parentTaskId:null,title:'Entregar integração',createdAt:now,lastActivityAt:now};
const child={...hierarchy.childDetail.task,createdAt:now,lastActivityAt:now,id:'child',parentTaskId:'root',title:'Validar permissões',status:'blocked'};
const empty={items:[],nextCursor:null,complete:true};
const detail={task:root,activity:empty,subtasks:{items:[child],nextCursor:'children-next',complete:true}};
const snapshot={...captured.snapshot,tasks:{items:[root,child],nextCursor:null,complete:true}};
const response=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:{'Content-Type':'application/json'}});
beforeEach(()=>{navigation.params=new URLSearchParams();navigation.pathname='/agents/tasks/root';navigation.replace.mockClear();vi.stubGlobal('fetch',vi.fn().mockResolvedValue(response(detail)));});
afterEach(()=>{cleanup();vi.unstubAllGlobals();});

describe('agent task hierarchy wire contract',()=>{
  it('accepts the captured live HTTP root, child and snapshot responses',()=>{
    expect(parseTaskDetail(hierarchy.parentDetail).subtasks.items[0].parentTaskId).toBe(hierarchy.parentDetail.task.id);
    expect(parseTaskDetail(hierarchy.childDetail).activity.items.some(item=>item.kind==='progress')).toBe(true);
    expect(parseSnapshot(hierarchy.roots).tasks.items.every(task=>task.parentTaskId===null)).toBe(true);
    expect(parseSnapshot(hierarchy.snapshot).tasks.items.some(task=>task.parentTaskId!==null)).toBe(true);
  });

  it('keeps the captured old response compatible and normalizes absent parents to roots',()=>{
    expect(parseTaskDetail(captured.detail)).toMatchObject({task:{parentTaskId:null},subtasks:empty});
    expect(parseSnapshot(captured.snapshot).tasks.items.every(task=>task.parentTaskId===null)).toBe(true);
  });
  it('parses child lifecycle and rejects invalid parent types, foreign children and a second level',()=>{
    expect(parseTaskDetail(detail).subtasks.items[0]).toMatchObject({parentTaskId:'root',status:'blocked'});
    for(const parentTaskId of [42,'','root'])expect(()=>parseTaskDetail({...detail,task:{...root,parentTaskId}})).toThrow();
    expect(()=>parseTaskDetail({...detail,subtasks:{...detail.subtasks,items:[{...child,parentTaskId:'another'}]}})).toThrow();
    expect(()=>parseTaskDetail({...detail,task:child,subtasks:{...detail.subtasks,items:[{...child,id:'grandchild',parentTaskId:'child'}]}})).toThrow();
    expect(()=>parseTaskDetail({...detail,subtasks:{...detail.subtasks,items:[{...child,status:'unknown'}]}})).toThrow();
  });
});

describe('agent task hierarchy navigation',()=>{
  it('shows each child status and detail link without changing the parent status',async()=>{
    render(<TaskDetail id="root"/>);
    const section=await screen.findByRole('region',{name:'Subtarefas'});
    expect(within(section).getByText('Bloqueadas')).toBeInTheDocument();
    expect(within(section).getByRole('link',{name:/Validar permissões/})).toHaveAttribute('href','/agents/tasks/child');
    expect(screen.getByRole('heading',{name:'Entregar integração'})).toBeInTheDocument();
    expect(screen.queryByRole('link',{name:'Ver tarefa principal'})).not.toBeInTheDocument();
  });
  it('groups children into status columns showing only statuses that have subtasks',async()=>{
    const children=[{...child,id:'b1',title:'Bloqueio 1'},{...child,id:'b2',title:'Bloqueio 2'},{...child,id:'c1',title:'Feito 1',status:'completed'}];
    vi.mocked(fetch).mockResolvedValue(response({...detail,subtasks:{...detail.subtasks,items:children}}));
    render(<TaskDetail id="root"/>);
    const section=await screen.findByRole('region',{name:'Subtarefas'});
    const blocked=within(section).getByRole('region',{name:'Bloqueadas'});
    expect(within(blocked).getAllByRole('link').map(link=>link.textContent)).toEqual([expect.stringContaining('Bloqueio 1'),expect.stringContaining('Bloqueio 2')]);
    expect(within(within(section).getByRole('region',{name:'Concluídas'})).getByRole('link',{name:/Feito 1/})).toHaveAttribute('href','/agents/tasks/c1');
    expect(within(section).queryByRole('region',{name:'Em andamento'})).not.toBeInTheDocument();
  });
  it('shows the hold reason and note on the card and the detail header, and rejects unknown reasons',async()=>{
    const held={...root,status:'waiting',hold:{reason:'deploy',note:'produção'}};
    vi.mocked(fetch).mockResolvedValue(response({...detail,task:held}));
    render(<TaskDetail id="root"/>);
    const header=(await screen.findByRole('heading',{name:'Entregar integração'})).closest('header')!;
    expect(within(header).getByText('Aguardando processo')).toBeInTheDocument();
    expect(within(header).getByText('Deploy')).toBeInTheDocument();
    expect(within(header).getByText('produção')).toBeInTheDocument();
    expect(()=>parseTaskDetail({...detail,task:{...held,hold:{reason:'decision',note:null}}})).toThrow();
    expect(()=>parseTaskDetail({...detail,task:{...root,status:'working',hold:{reason:'deploy',note:null}}})).toThrow();
    expect(parseTaskDetail({...detail,task:{...root,hold:undefined}}).task.hold).toBeNull();
  });
  it('highlights open tasks waiting on the user, counts them and alternates the tab title, never for finished tasks',{timeout:15000},async()=>{
    const since=new Date(Date.now()-5*60000).toISOString();
    const assignment={sessionId:'session-1',agentId:'agent-1',provider:'claude',displayName:'Claude',freshness:'fresh',attention:{kind:'permission',since}};
    const asking={...root,id:'asking',title:'Pede permissão',status:'working',assignment};
    const deciding={...root,id:'deciding',title:'Precisa decidir',status:'blocked',hold:{reason:'decision',note:'A ou B'},assignment:null};
    const finished={...root,id:'finished',title:'Já terminou',status:'completed',assignment};
    vi.mocked(fetch).mockResolvedValue(response({...snapshot,tasks:{items:[asking,deciding,finished],nextCursor:null,complete:true}}));
    document.title='Daily';
    const view=render(<AgentBoard/>);
    const card=await screen.findByRole('link',{name:/Pede permissão/});
    expect(card).toHaveAttribute('data-needs-you','permission');
    expect(card).toHaveTextContent('Pedindo sua permissão');
    expect(card).toHaveTextContent('há 5 min');
    expect(screen.getByRole('link',{name:/Precisa decidir/})).toHaveAttribute('data-needs-you','decision');
    expect(screen.getByRole('link',{name:/Já terminou/})).not.toHaveAttribute('data-needs-you');
    expect(screen.getByText('2 aguardando você')).toBeInTheDocument();
    await waitFor(()=>expect(document.title).toBe('(2) Aguardando você'),{timeout:3000});
    await waitFor(()=>expect(document.title).toBe('Daily'),{timeout:3000});
    await waitFor(()=>expect(document.title).toBe('(2) Aguardando você'),{timeout:3000});
    view.unmount();
    expect(document.title).toBe('Daily');
  });
  it('uses distinct URL cursors for child pages and activity, preserving the other cursor',async()=>{
    navigation.params=new URLSearchParams('cursor=activity-old&subtaskCursor=children-old');
    vi.mocked(fetch).mockResolvedValue(response({...detail,activity:{...empty,nextCursor:'activity-next'}}));
    render(<TaskDetail id="root"/>);
    fireEvent.click(await screen.findByRole('button',{name:'Ver mais subtarefas'}));
    expect(navigation.replace).toHaveBeenLastCalledWith('/agents/tasks/root?cursor=activity-old&subtaskCursor=children-next',{scroll:false});
    fireEvent.click(screen.getByRole('button',{name:'Ver mais atividade'}));
    expect(navigation.replace).toHaveBeenLastCalledWith('/agents/tasks/root?cursor=activity-next&subtaskCursor=children-old',{scroll:false});
    fireEvent.click(screen.getByRole('button',{name:'Primeiras subtarefas'}));
    expect(navigation.replace).toHaveBeenLastCalledWith('/agents/tasks/root?cursor=activity-old',{scroll:false});
    expect(String(vi.mocked(fetch).mock.calls[0][0])).toContain('cursor=activity-old&subtaskCursor=children-old');
  });
  it('links the child back to its parent and retains its own activity and actions',async()=>{
    vi.mocked(fetch).mockResolvedValue(response({task:child,subtasks:empty,activity:{...empty,items:[{id:'event',taskId:'child',kind:'progress',summary:'Aguardando acesso',receivedAt:now,occurredAt:null}]}}));
    render(<TaskDetail id="child"/>);
    expect(await screen.findByRole('link',{name:'Ver tarefa principal'})).toHaveAttribute('href','/agents/tasks/root');
    expect(screen.getByText('Aguardando acesso')).toBeInTheDocument();
    expect(screen.getByRole('button',{name:'Iniciar'})).toBeInTheDocument();
    expect(screen.queryByRole('region',{name:'Subtarefas'})).not.toBeInTheDocument();
  });
  it('has an empty child state and exposes unavailable or malformed details',async()=>{
    vi.mocked(fetch).mockResolvedValue(response({...detail,subtasks:empty}));
    const view=render(<TaskDetail id="root"/>);
    expect(await screen.findByText('Nenhuma subtarefa criada')).toBeInTheDocument();
    view.unmount();
    vi.mocked(fetch).mockResolvedValue(response({},404));
    const unavailable=render(<TaskDetail id="root"/>);
    expect(await screen.findByRole('alert')).toHaveTextContent('Tarefa indisponível');
    expect(screen.queryByRole('heading',{name:'Entregar integração'})).not.toBeInTheDocument();
    unavailable.unmount();
    vi.mocked(fetch).mockResolvedValue(response({...detail,subtasks:{...detail.subtasks,items:[{...child,status:'unknown'}]}}));
    render(<TaskDetail id="root"/>);
    expect(await screen.findByRole('alert')).toHaveTextContent('Valor não reconhecido');
  });
  it('requests and displays only root macro cards on home, even when the server returns children',async()=>{
    vi.mocked(fetch).mockResolvedValue(response(snapshot));
    render(<AgentBoard/>);
    expect(await screen.findByRole('link',{name:/Entregar integração/})).toBeInTheDocument();
    expect(screen.queryByRole('link',{name:/Validar permissões/})).not.toBeInTheDocument();
    expect(String(vi.mocked(fetch).mock.calls[0][0])).toContain('scope=roots');
  });
  it('shows children as animated progress inside the root card in the workspace',async()=>{
    vi.mocked(fetch).mockResolvedValue(response({...snapshot,subtaskProgress:{root:{total:3,completed:1,active:[{id:'child',title:'Validar permissões',status:'working'}]}}}));
    render(<AgentBoard mode="workspace"/>);
    const card=await screen.findByRole('link',{name:/Entregar integração/});
    expect(within(card).getByRole('group',{name:'Subtarefas: 1 de 3 concluídas'})).toHaveTextContent('Validar permissões');
    expect(screen.getAllByRole('link').filter(link=>link.getAttribute('href')==='/agents/tasks/child')).toHaveLength(0);
    expect(String(vi.mocked(fetch).mock.calls[0][0])).toContain('scope=roots');
  });
  it('rejects malformed or foreign subtask progress in the snapshot',()=>{
    const roots={...snapshot,tasks:{...snapshot.tasks,items:[root]}};
    expect(parseSnapshot(roots).subtaskProgress).toEqual({});
    expect(()=>parseSnapshot({...roots,subtaskProgress:{root:{total:1,completed:2,active:[]}}})).toThrow();
    expect(()=>parseSnapshot({...roots,subtaskProgress:{other:{total:1,completed:0,active:[]}}})).toThrow();
    expect(()=>parseSnapshot({...roots,subtaskProgress:{root:{total:1,completed:0,active:[{id:'c',title:'x',status:'unknown'}]}}})).toThrow();
  });
  it('colors the detail status badge by task status instead of the button color',async()=>{
    vi.mocked(fetch).mockResolvedValue(response({...detail,task:{...root,status:'working'}}));
    render(<TaskDetail id="root"/>);
    const header=(await screen.findByRole('heading',{name:'Entregar integração'})).closest('header')!;
    expect(within(header).getByText('Em andamento')).toHaveClass('text-info');
    expect(within(header).getByText('Em andamento')).not.toHaveClass('bg-secondary');
  });
  it('explains that parent deletion requires removing its children first',async()=>{
    vi.mocked(fetch).mockImplementation(async(_url,init)=>init?.method==='DELETE'?response({...hierarchy.deleteRefusal,error:{...hierarchy.deleteRefusal.error,message:'private server text'}},409):response(detail));
    render(<TaskDetail id="root"/>);
    fireEvent.click(await screen.findByRole('button',{name:/^Excluir$/}));
    fireEvent.click(screen.getByRole('button',{name:'Excluir tarefa'}));
    await waitFor(()=>expect(within(screen.getByRole('dialog')).getByRole('alert')).toHaveTextContent('Exclua as subtarefas antes de excluir a tarefa principal.'));
    expect(navigation.push).not.toHaveBeenCalled();
    expect(screen.queryByText('private server text')).not.toBeInTheDocument();
  });
});
