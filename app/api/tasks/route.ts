import { NextResponse } from 'next/server';
import { addTask, editTask, setDoing } from '@/lib/tasks';
import { parseDueInput } from '@/lib/dateParsing';
import { isValidTaskPriority, isValidRecur, isSafePositionalValue } from '@/lib/api/validation';
import { getCurrentUser } from '@/lib/auth/currentUser';
import { refreshTasks } from '@/lib/refresher';

export async function POST(request: Request) {
  const user = await getCurrentUser();
  if (!user) return NextResponse.json({ error: 'não autenticado' }, { status: 401 });
  const body = await request.json();
  const title: string = body.title ?? '';
  if (!title.trim()) {
    return NextResponse.json({ error: 'título obrigatório' }, { status: 400 });
  }
  if (!isSafePositionalValue(title.trim())) {
    return NextResponse.json({ error: 'título inválido' }, { status: 400 });
  }

  if (body.priority !== undefined && !isValidTaskPriority(body.priority)) {
    return NextResponse.json({ error: 'prioridade inválida' }, { status: 400 });
  }
  if (body.recur !== undefined && !isValidRecur(body.recur)) {
    return NextResponse.json({ error: 'recorrência inválida' }, { status: 400 });
  }
  // The board's column, for a note added straight into "Fazendo". "Feito" is
  // refused for the same reason the board route refuses it: completing goes
  // through PATCH /api/tasks/[id], where a recurring task rolls over.
  if (body.status !== undefined && body.status !== 'todo' && body.status !== 'doing') {
    return NextResponse.json(
      { error: 'coluna inválida: use "todo" ou "doing"; uma tarefa nova não nasce concluída' },
      { status: 400 },
    );
  }

  let due: string | undefined;
  let time: string | undefined;
  if (typeof body.due === 'string') {
    try {
      const parsed = parseDueInput(body.due);
      due = parsed.due;
      time = parsed.time;
    } catch (err) {
      return NextResponse.json({ error: err instanceof Error ? err.message : String(err) }, { status: 400 });
    }
  }

  // Without a date there is nothing to roll over to: completing a repeating
  // task with no due date completes it for good, while the panel promises it
  // comes back. Refuse the combination instead of keeping that promise.
  if (body.recur !== undefined && body.recur !== 'none' && (due === undefined || due === 'none')) {
    return NextResponse.json({ error: 'uma tarefa que repete precisa de data' }, { status: 400 });
  }

  try {
    const id = await addTask(user.id, title.trim());

    if (due !== undefined || body.priority !== undefined || body.recur !== undefined) {
      await editTask(user.id, id, { due, time, priority: body.priority, recur: body.recur });
    }
    // Here rather than as a second request from the panel: two requests could
    // leave a task created in "A fazer" when the person asked for "Fazendo".
    if (body.status === 'doing') setDoing(user.id, id, true);
    await refreshTasks(user.id);
    return NextResponse.json({ id });
  } catch (err) {
    return NextResponse.json({ error: err instanceof Error ? err.message : String(err) }, { status: 502 });
  }
}
