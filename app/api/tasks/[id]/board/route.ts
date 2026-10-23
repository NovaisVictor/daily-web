import { NextResponse } from 'next/server';
import { setDoing } from '@/lib/tasks';
import { isValidTaskId } from '@/lib/api/validation';
import { getCurrentUser } from '@/lib/auth/currentUser';
import { refreshTasks } from '@/lib/refresher';

/**
 * Moves a task between "A fazer" and "Fazendo" on the board. "Feito" is not
 * accepted here on purpose: completing goes through PATCH /api/tasks/[id], the
 * same path as the list's checkbox, so a recurring task still rolls over and
 * Microsoft To Do still hears about it.
 */
export async function PATCH(request: Request, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  if (!isValidTaskId(id)) {
    return NextResponse.json({ error: 'id inválido' }, { status: 400 });
  }
  const body = await request.json().catch(() => null);
  const status = body && typeof body === 'object' ? body.status : undefined;
  if (status !== 'todo' && status !== 'doing') {
    return NextResponse.json(
      { error: 'coluna inválida: use "todo" ou "doing"; para concluir, marque a tarefa como feita' },
      { status: 400 },
    );
  }
  const user = await getCurrentUser();
  if (!user) return NextResponse.json({ error: 'não autenticado' }, { status: 401 });
  try {
    setDoing(user.id, id, status === 'doing');
    await refreshTasks(user.id);
    return NextResponse.json({ ok: true });
  } catch (err) {
    return NextResponse.json({ error: err instanceof Error ? err.message : String(err) }, { status: 502 });
  }
}
