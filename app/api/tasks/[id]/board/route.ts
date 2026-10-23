import { NextResponse } from 'next/server';
import { setDoing, setTaskStyle, type BoardStylePatch } from '@/lib/tasks';
import { isNotePaper, isPinColor, isValidTaskId } from '@/lib/api/validation';
import { getCurrentUser } from '@/lib/auth/currentUser';
import { patchCachedState, refreshTasks } from '@/lib/refresher';
import { setTaskStyle as patchTaskStyle } from '@/lib/statePatches';

/**
 * What the board keeps beside the provider's task: the column between "A
 * fazer" and "Fazendo", and the note's paper and pin colour. Any of
 * `status`, `paper` and `pin` may come alone; a colour of null goes back to
 * automatic. "Feito" is not accepted here on purpose: completing goes through
 * PATCH /api/tasks/[id], the same path as the list's checkbox, so a recurring
 * task still rolls over and Microsoft To Do still hears about it.
 */
export async function PATCH(request: Request, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  if (!isValidTaskId(id)) {
    return NextResponse.json({ error: 'id inválido' }, { status: 400 });
  }
  const body = await request.json().catch(() => null);
  const fields = body && typeof body === 'object' ? (body as Record<string, unknown>) : {};
  const hasStatus = 'status' in fields;
  const style: BoardStylePatch = {};
  if ('paper' in fields) {
    if (fields.paper !== null && !isNotePaper(fields.paper)) {
      return NextResponse.json({ error: 'cor de papel inválida' }, { status: 400 });
    }
    style.paper = fields.paper;
  }
  if ('pin' in fields) {
    if (fields.pin !== null && !isPinColor(fields.pin)) {
      return NextResponse.json({ error: 'cor de alfinete inválida' }, { status: 400 });
    }
    style.pin = fields.pin;
  }
  const hasStyle = 'paper' in style || 'pin' in style;
  if (!hasStatus && !hasStyle) {
    return NextResponse.json({ error: 'informe status, paper ou pin' }, { status: 400 });
  }
  const status = fields.status;
  if (hasStatus && status !== 'todo' && status !== 'doing') {
    return NextResponse.json(
      { error: 'coluna inválida: use "todo" ou "doing"; para concluir, marque a tarefa como feita' },
      { status: 400 },
    );
  }
  const user = await getCurrentUser();
  if (!user) return NextResponse.json({ error: 'não autenticado' }, { status: 401 });
  try {
    if (!hasStyle) {
      setDoing(user.id, id, status === 'doing');
      await refreshTasks(user.id);
      return NextResponse.json({ ok: true });
    }
    const saved = setTaskStyle(user.id, id, style);
    if (hasStatus) {
      setDoing(user.id, id, status === 'doing');
      await refreshTasks(user.id);
    } else {
      // A colour changes nothing at the provider. Reloading the tasks would
      // run the Microsoft To Do CLI just to repaint a note, so the cache is
      // corrected in place, which a refresh already in flight replays too.
      patchCachedState(user.id, (state) => patchTaskStyle(state, id, saved));
    }
    return NextResponse.json({ ok: true, paper: saved.paper, pin: saved.pin });
  } catch (err) {
    return NextResponse.json({ error: err instanceof Error ? err.message : String(err) }, { status: 502 });
  }
}
