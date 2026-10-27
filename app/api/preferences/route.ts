import { NextRequest, NextResponse } from 'next/server';
import { requireUser } from '@/lib/api/context';
import { isAgendaRange } from '@/lib/agendaWindow';
import { parseLayout, putSizedLayout } from '@/lib/dashboardLayout';
import {
  dashboardLayouts,
  isTasksView,
  setAgendaDays,
  setTasksView,
  setDashboardLayout,
  setDashboardLayouts,
  resetDashboardLayout,
  savedAppearance,
  setAppearance,
} from '@/lib/preferences';
import { dropCache, patchCachedState, refreshAll } from '@/lib/refresher';
import { parseAppearancePatch } from '@/lib/theme';

/**
 * Preferências de visualização do usuário logado.
 *
 * O período da agenda muda o que o servidor busca, então responde com o
 * estado refeito. O layout não busca nada — só reposiciona o que já está na
 * tela — e por isso corrige o cache em vez de disparar uma volta às
 * integrações a cada painel arrastado.
 */
/** Um tamanho de janela plausível. Zero, negativo ou absurdo não vem de tela
 *  nenhuma e estragaria a conta de distância que escolhe a disposição. */
const MAX_DIMENSAO = 20_000;

function isTamanhoDeTela(
  value: { width?: unknown; height?: unknown } | undefined,
): value is { width: number; height: number } {
  if (!value) return false;
  const { width, height } = value;
  return (
    typeof width === 'number' &&
    typeof height === 'number' &&
    Number.isFinite(width) &&
    Number.isFinite(height) &&
    width > 0 &&
    height > 0 &&
    width <= MAX_DIMENSAO &&
    height <= MAX_DIMENSAO
  );
}

export async function PATCH(request: NextRequest) {
  const auth = await requireUser();
  if (!auth.ok) return auth.response;
  const userId = auth.value.id;

  const body = await request.json().catch(() => null);
  if (!body || typeof body !== 'object') {
    return NextResponse.json({ error: 'corpo inválido' }, { status: 400 });
  }

  if ('layout' in body) {
    if (body.layout === null) {
      resetDashboardLayout(userId);
    } else if (Array.isArray(body.layout)) {
      // O tamanho da janela vem do cliente porque só ele sabe: o servidor
      // nunca vê a tela de quem pediu.
      //
      // Sem tamanho não é erro: um deploy deixa abas abertas rodando o cliente
      // anterior, que gravava a cada arraste e não mandava tamanho nenhum.
      // Recusar essas requisições fazia a aba antiga mostrar "tamanho de tela
      // inválido" enquanto a pessoa arrastava. Elas caem na disposição única,
      // que é o que aquele cliente sempre gravou.
      //
      // parseLayout prende o que vier fora dos limites: um w de 999 ou um id
      // desconhecido não pode virar estado gravado.
      const layout = parseLayout(body.layout);
      const viewport = body.viewport as { width?: unknown; height?: unknown } | undefined;

      if (viewport === undefined || viewport === null) {
        setDashboardLayout(userId, layout);
      } else if (isTamanhoDeTela(viewport)) {
        setDashboardLayouts(
          userId,
          putSizedLayout(dashboardLayouts(userId), viewport.width, viewport.height, layout),
        );
      } else {
        // Tamanho presente e sem sentido é defeito de cliente, não aba velha.
        return NextResponse.json({ error: 'tamanho de tela inválido' }, { status: 400 });
      }
    } else {
      return NextResponse.json({ error: 'layout inválido' }, { status: 400 });
    }

    const { dashboardLayout } = await import('@/lib/preferences');
    const layout = dashboardLayout(userId);
    const layouts = dashboardLayouts(userId);
    patchCachedState(userId, (state) => ({ ...state, layout, layouts }));
    return NextResponse.json({ layout, layouts });
  }

  if ('agendaDays' in body) {
    if (!isAgendaRange(body.agendaDays)) {
      return NextResponse.json({ error: 'período inválido' }, { status: 400 });
    }
    setAgendaDays(userId, body.agendaDays);
    dropCache(userId);
    return NextResponse.json(await refreshAll(userId));
  }

  // Like the layout, the view only changes how the tasks already on screen are
  // drawn, so it patches the cache instead of refetching the integrations.
  if ('tasksView' in body) {
    if (!isTasksView(body.tasksView)) {
      return NextResponse.json({ error: 'visualização inválida' }, { status: 400 });
    }
    const view = body.tasksView;
    setTasksView(userId, view);
    patchCachedState(userId, (state) => ({ ...state, tasksView: view }));
    return NextResponse.json({ tasksView: view });
  }

  // Only how the page looks: nothing on the dashboard changes, so no cache to patch.
  if ('appearance' in body) {
    const patch = parseAppearancePatch(body.appearance);
    if (!patch) return NextResponse.json({ error: 'aparência inválida' }, { status: 400 });
    setAppearance(userId, patch);
    return NextResponse.json({ appearance: savedAppearance(userId) });
  }

  return NextResponse.json({ error: 'nenhuma preferência informada' }, { status: 400 });
}
