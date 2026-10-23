import { describe, expect, it, vi, beforeEach } from 'vitest';

// As rotas resolvem o usuário pelo cookie; aqui basta um usuário fixo para o
// teste focar no que ele mede.
vi.mock('@/lib/auth/currentUser', () => ({
  getCurrentUser: vi.fn(async () => ({
    id: 'u-1', username: 'joao', passwordHash: 'x', isAdmin: true, createdAt: '2026-01-01',
  })),
}));

// O provedor de tarefas é escolhido por conexão (local ou Microsoft To Do);
// as rotas falam com o despachante, que é o que estes testes medem.
vi.mock('@/lib/tasks', () => ({
  addTask: vi.fn(async () => 'NEW-ID'),
  editTask: vi.fn(),
  setCompleted: vi.fn(),
  deleteTask: vi.fn(),
  addSubtask: vi.fn(),
  editSubtask: vi.fn(),
  deleteSubtask: vi.fn(),
  checkSubtask: vi.fn(),
  setDoing: vi.fn(),
  setTaskStyle: vi.fn((_user: string, _id: string, patch: { paper?: string | null; pin?: string | null }) => ({
    paper: patch.paper ?? null,
    pin: patch.pin ?? null,
  })),
}));

// Medir que uma troca de cor não recarrega as tarefas: no Microsoft To Do
// isso rodaria a CLI só para repintar uma nota.
vi.mock('@/lib/refresher', () => ({
  refreshTasks: vi.fn(async () => {}),
  patchCachedState: vi.fn(),
}));

import { addTask, editTask, setCompleted, deleteTask, addSubtask, editSubtask, checkSubtask, setDoing, setTaskStyle } from '@/lib/tasks';
import { patchCachedState, refreshTasks } from '@/lib/refresher';
import type { DashboardState } from '@/lib/types';
import { getCurrentUser } from '@/lib/auth/currentUser';
import { POST as createRoute } from '@/app/api/tasks/route';
import { PATCH as patchRoute, DELETE as deleteRoute } from '@/app/api/tasks/[id]/route';
import { POST as createSubtaskRoute } from '@/app/api/tasks/[id]/subtasks/route';
import { PATCH as patchSubtaskRoute, DELETE as deleteSubtaskRoute } from '@/app/api/tasks/[id]/subtasks/[itemId]/route';
import { PATCH as boardRoute } from '@/app/api/tasks/[id]/board/route';

beforeEach(() => vi.clearAllMocks());

function req(body: unknown): Request {
  return new Request('http://localhost/api', { method: 'POST', body: JSON.stringify(body) });
}

// Genérico para o tipo do objeto sobreviver: os handlers do Next 16.3 exigem
// `Promise<{ id: string }>`, e um `Record<string, string>` não satisfaz isso.
const params = <T extends Record<string, string>>(p: T) => ({ params: Promise.resolve(p) });

describe('POST /api/tasks', () => {
  it('título vazio devolve 400 sem chamar addTask', async () => {
    const res = await createRoute(req({ title: '  ' }));
    expect(res.status).toBe(400);
    expect(addTask).not.toHaveBeenCalled();
  });

  it('cria a tarefa e edita quando há campos extras', async () => {
    const res = await createRoute(req({ title: 'Nova tarefa', due: 'hoje', priority: 'high' }));
    const data = await res.json();
    expect(data.id).toBe('NEW-ID');
    expect(addTask).toHaveBeenCalledWith('u-1', 'Nova tarefa');
    expect(editTask).toHaveBeenCalledWith('u-1', 'NEW-ID', expect.objectContaining({ priority: 'high' }));
  });

  it('data inválida devolve 400 e não cria a tarefa (sem orfão)', async () => {
    const res = await createRoute(req({ title: 'Nova tarefa', due: 'não é uma data' }));
    expect(res.status).toBe(400);
    expect(addTask).not.toHaveBeenCalled();
  });

  it('prioridade inválida devolve 400 sem chamar addTask', async () => {
    const res = await createRoute(req({ title: 'Nova tarefa', priority: 'urgentíssimo' }));
    expect(res.status).toBe(400);
    expect(addTask).not.toHaveBeenCalled();
  });

  it('recorrência inválida devolve 400 sem chamar addTask', async () => {
    const res = await createRoute(req({ title: 'Nova tarefa', recur: 'a cada hora' }));
    expect(res.status).toBe(400);
    expect(addTask).not.toHaveBeenCalled();
  });

  // Completing a repeating task with no date completed it for good, while the
  // panel announced it would come back with its next date.
  it('recorrente sem data devolve 400 sem criar a tarefa', async () => {
    const res = await createRoute(req({ title: 'Pagar fatura', recur: 'monthly' }));
    expect(res.status).toBe(400);
    expect(addTask).not.toHaveBeenCalled();
  });

  it('recorrente com data é criada', async () => {
    const res = await createRoute(req({ title: 'Pagar fatura', recur: 'monthly', due: 'amanhã' }));
    expect(res.status).toBe(200);
    expect(editTask).toHaveBeenCalledWith('u-1', 'NEW-ID', expect.objectContaining({ recur: 'monthly' }));
  });

  it('título iniciado com "-" devolve 400 sem chamar addTask', async () => {
    const res = await createRoute(req({ title: '-rf tudo' }));
    expect(res.status).toBe(400);
    expect(addTask).not.toHaveBeenCalled();
  });
});

describe('POST /api/tasks com coluna do quadro', () => {
  it('status "doing" cria a tarefa já em Fazendo, numa só requisição', async () => {
    const res = await createRoute(req({ title: 'Revisar PR', status: 'doing' }));
    expect(res.status).toBe(200);
    expect(addTask).toHaveBeenCalledWith('u-1', 'Revisar PR');
    expect(setDoing).toHaveBeenCalledWith('u-1', 'NEW-ID', true);
  });

  it('status "todo" cria a tarefa sem marcar Fazendo', async () => {
    const res = await createRoute(req({ title: 'Escrever proposta', status: 'todo' }));
    expect(res.status).toBe(200);
    expect(setDoing).not.toHaveBeenCalled();
  });

  it('sem status, cria em A fazer como antes', async () => {
    await createRoute(req({ title: 'Escrever proposta' }));
    expect(setDoing).not.toHaveBeenCalled();
  });

  it('status "done" devolve 400 sem criar a tarefa', async () => {
    const res = await createRoute(req({ title: 'Pagar boleto', status: 'done' }));
    expect(res.status).toBe(400);
    expect(addTask).not.toHaveBeenCalled();
    expect(setDoing).not.toHaveBeenCalled();
  });

  it('falha ao criar não marca Fazendo', async () => {
    vi.mocked(addTask).mockRejectedValueOnce(new Error('mstodo falhou'));
    const res = await createRoute(req({ title: 'Revisar PR', status: 'doing' }));
    expect(res.status).toBe(502);
    expect(setDoing).not.toHaveBeenCalled();
  });
});

describe('PATCH /api/tasks/[id]', () => {
  it('completed=true conclui a tarefa', async () => {
    await patchRoute(req({ completed: true }), params({ id: 'T1' }));
    expect(setCompleted).toHaveBeenCalledWith('u-1', 'T1', true);
  });

  it('completed=false reabre a tarefa', async () => {
    await patchRoute(req({ completed: false }), params({ id: 'T1' }));
    expect(setCompleted).toHaveBeenCalledWith('u-1', 'T1', false);
  });

  it('edição de campos chama editTask com a data já parseada', async () => {
    await patchRoute(req({ due: 'amanhã' }), params({ id: 'T1' }));
    expect(editTask).toHaveBeenCalledWith('u-1', 'T1', expect.objectContaining({ due: expect.any(String) }));
  });

  it('id iniciado com "-" devolve 400 sem concluir nem editar', async () => {
    const res = await patchRoute(req({ completed: true }), params({ id: '-rf' }));
    expect(res.status).toBe(400);
    expect(setCompleted).not.toHaveBeenCalled();
    expect(editTask).not.toHaveBeenCalled();
  });

  it('prioridade inválida devolve 400 sem chamar editTask', async () => {
    const res = await patchRoute(req({ priority: 'urgentíssimo' }), params({ id: 'T1' }));
    expect(res.status).toBe(400);
    expect(editTask).not.toHaveBeenCalled();
  });

  it('recorrência inválida devolve 400 sem chamar editTask', async () => {
    const res = await patchRoute(req({ recur: 'a cada hora' }), params({ id: 'T1' }));
    expect(res.status).toBe(400);
    expect(editTask).not.toHaveBeenCalled();
  });

  it('limpar a data de uma recorrente devolve 400 sem editar', async () => {
    const res = await patchRoute(req({ recur: 'weekly', due: '' }), params({ id: 'T1' }));
    expect(res.status).toBe(400);
    expect(editTask).not.toHaveBeenCalled();
  });

  it('deixar de repetir e limpar a data juntos é aceito', async () => {
    const res = await patchRoute(req({ recur: 'none', due: '' }), params({ id: 'T1' }));
    expect(res.status).toBe(200);
  });

  it('título iniciado com "-" devolve 400 sem chamar editTask', async () => {
    const res = await patchRoute(req({ title: '-rf tudo' }), params({ id: 'T1' }));
    expect(res.status).toBe(400);
    expect(editTask).not.toHaveBeenCalled();
  });
});

describe('DELETE /api/tasks/[id]', () => {
  it('chama deleteTask', async () => {
    await deleteRoute(req({}), params({ id: 'T1' }));
    expect(deleteTask).toHaveBeenCalledWith('u-1', 'T1');
  });

  it('id iniciado com "-" devolve 400 sem chamar deleteTask', async () => {
    const res = await deleteRoute(req({}), params({ id: '-rf' }));
    expect(res.status).toBe(400);
    expect(deleteTask).not.toHaveBeenCalled();
  });

  it('falha do provedor devolve 502 com mensagem estruturada, em vez de propagar um erro genérico', async () => {
    vi.mocked(deleteTask).mockRejectedValueOnce(new Error('mstodo falhou: sem credenciais'));
    const res = await deleteRoute(req({}), params({ id: 'T1' }));
    expect(res.status).toBe(502);
    const data = await res.json();
    expect(data.error).toBe('mstodo falhou: sem credenciais');
  });
});

describe('POST /api/tasks/[id]/subtasks', () => {
  it('id iniciado com "-" devolve 400 sem chamar addSubtask', async () => {
    const res = await createSubtaskRoute(req({ title: 'Sub' }), params({ id: '-rf' }));
    expect(res.status).toBe(400);
    expect(addSubtask).not.toHaveBeenCalled();
  });

  it('título iniciado com "-" devolve 400 sem chamar addSubtask', async () => {
    const res = await createSubtaskRoute(req({ title: '-rf tudo' }), params({ id: 'T1' }));
    expect(res.status).toBe(400);
    expect(addSubtask).not.toHaveBeenCalled();
  });
});

describe('PATCH /api/tasks/[id]/subtasks/[itemId]', () => {
  it('completed marca a subtarefa', async () => {
    await patchSubtaskRoute(req({ completed: true }), params({ id: 'T1', itemId: 'S1' }));
    expect(checkSubtask).toHaveBeenCalledWith('u-1', 'T1', 'S1', true);
  });

  it('itemId iniciado com "-" devolve 400 sem chamar checkSubtask', async () => {
    const res = await patchSubtaskRoute(req({ completed: true }), params({ id: 'T1', itemId: '-rf' }));
    expect(res.status).toBe(400);
    expect(checkSubtask).not.toHaveBeenCalled();
  });

  it('título iniciado com "-" devolve 400 sem chamar editSubtask', async () => {
    const res = await patchSubtaskRoute(req({ title: '-rf tudo' }), params({ id: 'T1', itemId: 'S1' }));
    expect(res.status).toBe(400);
    expect(editSubtask).not.toHaveBeenCalled();
  });
});

describe('DELETE /api/tasks/[id]/subtasks/[itemId]', () => {
  it('itemId iniciado com "-" devolve 400', async () => {
    const res = await deleteSubtaskRoute(req({}), params({ id: 'T1', itemId: '-rf' }));
    expect(res.status).toBe(400);
  });
});

describe('PATCH /api/tasks/[id]/board', () => {
  it('"doing" põe a tarefa em Fazendo para o usuário logado', async () => {
    const res = await boardRoute(req({ status: 'doing' }), params({ id: 'T1' }));
    expect(res.status).toBe(200);
    expect(setDoing).toHaveBeenCalledWith('u-1', 'T1', true);
  });

  it('"todo" tira a tarefa de Fazendo', async () => {
    await boardRoute(req({ status: 'todo' }), params({ id: 'T1' }));
    expect(setDoing).toHaveBeenCalledWith('u-1', 'T1', false);
  });

  // Concluir passa pela rota da tarefa, a mesma do checkbox: é ela que faz a
  // recorrente pular de data e que avisa o Microsoft To Do.
  it('"done" devolve 400 sem gravar nem concluir', async () => {
    const res = await boardRoute(req({ status: 'done' }), params({ id: 'T1' }));
    expect(res.status).toBe(400);
    expect(setDoing).not.toHaveBeenCalled();
    expect(setCompleted).not.toHaveBeenCalled();
  });

  it('corpo sem status devolve 400', async () => {
    const res = await boardRoute(req({}), params({ id: 'T1' }));
    expect(res.status).toBe(400);
    expect(setDoing).not.toHaveBeenCalled();
  });

  it('id iniciado com "-" devolve 400 sem gravar', async () => {
    const res = await boardRoute(req({ status: 'doing' }), params({ id: '-rf' }));
    expect(res.status).toBe(400);
    expect(setDoing).not.toHaveBeenCalled();
  });

  it('sem sessão devolve 401 sem gravar', async () => {
    vi.mocked(getCurrentUser).mockResolvedValueOnce(null);
    const res = await boardRoute(req({ status: 'doing' }), params({ id: 'T1' }));
    expect(res.status).toBe(401);
    expect(setDoing).not.toHaveBeenCalled();
  });
});

describe('PATCH /api/tasks/[id]/board: cor da nota', () => {
  it('papel válido grava e devolve o estilo salvo', async () => {
    const res = await boardRoute(req({ paper: 'pink' }), params({ id: 'T1' }));
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ ok: true, paper: 'pink', pin: null });
    expect(setTaskStyle).toHaveBeenCalledWith('u-1', 'T1', { paper: 'pink' });
    expect(setDoing).not.toHaveBeenCalled();
  });

  it('papel fora da paleta devolve 400 sem gravar', async () => {
    const res = await boardRoute(req({ paper: 'teal' }), params({ id: 'T1' }));
    expect(res.status).toBe(400);
    expect(setTaskStyle).not.toHaveBeenCalled();
  });

  it('alfinete fora da paleta devolve 400 sem gravar nada, nem o status', async () => {
    const res = await boardRoute(req({ status: 'doing', pin: 'purple' }), params({ id: 'T1' }));
    expect(res.status).toBe(400);
    expect(setTaskStyle).not.toHaveBeenCalled();
    expect(setDoing).not.toHaveBeenCalled();
  });

  it('corpo vazio devolve 400', async () => {
    const res = await boardRoute(req({}), params({ id: 'T1' }));
    expect(res.status).toBe(400);
    expect(setTaskStyle).not.toHaveBeenCalled();
  });

  it('status e cor juntos gravam os dois e recarregam as tarefas', async () => {
    const res = await boardRoute(req({ status: 'doing', paper: 'grey', pin: 'red' }), params({ id: 'T1' }));
    expect(res.status).toBe(200);
    expect(setDoing).toHaveBeenCalledWith('u-1', 'T1', true);
    expect(setTaskStyle).toHaveBeenCalledWith('u-1', 'T1', { paper: 'grey', pin: 'red' });
    expect(refreshTasks).toHaveBeenCalledWith('u-1');
  });

  it('null volta ao automático', async () => {
    const res = await boardRoute(req({ paper: null, pin: null }), params({ id: 'T1' }));
    expect(res.status).toBe(200);
    expect(setTaskStyle).toHaveBeenCalledWith('u-1', 'T1', { paper: null, pin: null });
  });

  it('só a cor corrige o cache no lugar, sem recarregar as tarefas', async () => {
    await boardRoute(req({ pin: 'blue' }), params({ id: 'T1' }));
    expect(refreshTasks).not.toHaveBeenCalled();
    expect(patchCachedState).toHaveBeenCalledTimes(1);

    // O patch registrado aplica o estilo salvo à tarefa certa, e só a ela.
    const patch = vi.mocked(patchCachedState).mock.calls[0][1];
    const before = {
      tasks: {
        data: [
          { id: 'T1', paper: 'white', pin: null },
          { id: 'T2', paper: 'pink', pin: null },
        ],
        error: null,
      },
    } as unknown as DashboardState;
    expect(patch(before).tasks.data).toMatchObject([
      { id: 'T1', paper: null, pin: 'blue' },
      { id: 'T2', paper: 'pink', pin: null },
    ]);
  });

  it('sem sessão devolve 401 sem gravar a cor', async () => {
    vi.mocked(getCurrentUser).mockResolvedValueOnce(null);
    const res = await boardRoute(req({ paper: 'pink' }), params({ id: 'T1' }));
    expect(res.status).toBe(401);
    expect(setTaskStyle).not.toHaveBeenCalled();
  });
});
