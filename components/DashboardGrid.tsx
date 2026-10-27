'use client';

import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { X } from 'lucide-react';
import { usePathname, useRouter, useSearchParams } from 'next/navigation';
import { IconAction } from '@/components/data/IconAction';
import { MobileModuleNav } from '@/components/MobileModuleNav';
import type { ReactNode } from 'react';
import GridLayout, { useContainerWidth, type Layout } from 'react-grid-layout';
import { Button } from '@/components/ui/button';
import { PanelFrame, cardSurface } from '@/components/data/Panel';
import { cn } from '@/lib/utils';
import { isModuleId, type ModuleId } from '@/lib/modules';
import {
  GRID_COLUMNS,
  GRID_ROW_HEIGHT,
  MIN_PANEL_HEIGHT,
  MIN_PANEL_WIDTH,
  NARROW_BREAKPOINT,
  layoutFor,
  parseLayout,
  serializeLayout,
  type PanelPlacement,
} from '@/lib/dashboardLayout';

const naoFazNada = () => {};

interface Props {
  layout: PanelPlacement[];
  /** Ids dos painéis a desenhar, na ordem em que o layout os posiciona. */
  panels: { id: string; node: ReactNode }[];
  /** Grava a disposição para o tamanho de janela de agora. */
  onSave: (layout: PanelPlacement[]) => Promise<void> | void;
}

/** How long a panel has to be held before the arrange mode starts, as on a phone's home screen. */
const HOLD_MS = 1000;
/** A hand is never perfectly still: the pointer may drift this far before the press is read as a
 *  selection or a drag and not as a hold. */
const HOLD_SLOP_PX = 24;

export function DashboardGrid({ layout, panels, onSave }: Props) {
  const searchParams = useSearchParams();
  const router = useRouter();
  const pathname = usePathname();
  // A v2 mede a largura por hook em vez do antigo WidthProvider.
  const { width, mounted, containerRef } = useContainerWidth();
  const [dragging, setDragging] = useState(false);
  const [narrow, setNarrow] = useState(false);
  const narrowRef = useRef<HTMLDivElement>(null);
  // Segurar um painel por 1 s liga o modo e o deixa preso até a pessoa salvar
  // ou descartar. É o gesto da tela inicial do celular, e funciona igual com
  // mouse e com toque.
  const [pinned, setPinned] = useState(false);
  // O painel segurado e onde está o ponteiro: dá retorno enquanto o 1 s passa.
  const [holding, setHolding] = useState<{ panelId: string; x: number; y: number } | null>(null);
  // Quanto da espera já passou, para o contador ao lado do ponteiro.
  const [heldMs, setHeldMs] = useState(0);
  // Desfaz o gesto em andamento: o timer e os ouvidos da janela.
  const stopHoldRef = useRef<(() => void) | null>(null);
  // O mouse ainda pressionado quando o 1 s completa: o arrasto continua dele, sem soltar.
  const handoffRef = useRef<{ panel: HTMLElement; x: number; y: number; released: boolean } | null>(
    null,
  );
  // O que está sendo arrastado, ainda não gravado. Enquanto existe, é ele que
  // a grade desenha — arrastar deixou de gravar sozinho.
  const [rascunho, setRascunho] = useState<PanelPlacement[] | null>(null);
  const [salvando, setSalvando] = useState(false);
  // `dragging` mantém o modo de pé enquanto um arrasto está em andamento,
  // para desligar o botão no meio não deixar o painel no ar.
  const arranging = dragging || pinned;

  // O tamanho da janela aparece no aviso para a gravação não ser cega: você
  // vê para qual tela está guardando antes de clicar.
  const [janela, setJanela] = useState({ largura: 0, altura: 0 });
  useEffect(() => {
    const medir = () => setJanela({ largura: window.innerWidth, altura: window.innerHeight });
    medir();
    window.addEventListener('resize', medir);
    return () => window.removeEventListener('resize', medir);
  }, []);

  useEffect(() => {
    const media = window.matchMedia(`(max-width: ${NARROW_BREAKPOINT}px)`);
    const sync = () => setNarrow(media.matches);
    sync();
    media.addEventListener('change', sync);
    return () => media.removeEventListener('change', sync);
  }, []);

  // A lista de painéis é reconstruída a cada render da página, então comparar
  // por identidade daria um array novo toda vez. A chave é o conteúdo.
  const panelIds = useMemo(() => panels.map((p) => p.id).join(','), [panels]);

  // `layout` precisa manter a mesma referência entre renders: a grade
  // re-sincroniza quando a prop muda, e um arrasto em andamento morria no
  // primeiro render — que é justamente o que `onDragStart` provoca.
  const visible = useMemo(
    () => layoutFor(rascunho ?? layout, panelIds.split(',')),
    [rascunho, layout, panelIds],
  );

  // A grade emite mudança também ao montar e ao medir a largura. Tratar isso
  // como edição marcaria a disposição como mexida sem ninguém ter arrastado.
  //
  // A comparação usa `serializeLayout` dos dois lados: comparar JSON.stringify
  // direto dava diferença por ordem de chaves — o objeto vindo da grade e o
  // do estado têm os mesmos valores em ordem distinta — e toda montagem
  // parecia uma mudança.
  const ultimo = useRef<string>('');
  useEffect(() => {
    ultimo.current = serializeLayout(layoutFor(layout, panelIds.split(',')));
  }, [layout, panelIds]);

  const handleChange = useCallback(
    (next: Layout) => {
      const limpo = parseLayout(next);
      const serializado = serializeLayout(layoutFor(limpo, panelIds.split(',')));
      if (serializado === ultimo.current) return;
      ultimo.current = serializado;
      setRascunho(limpo);
    },
    [panelIds],
  );

  const salvar = async () => {
    if (!rascunho) {
      // Entrou no modo e não mexeu em nada: fixar a disposição atual para
      // esta tela ainda é uma escolha legítima.
      setSalvando(true);
      await onSave(layout);
      setSalvando(false);
      setPinned(false);
      return;
    }
    setSalvando(true);
    await onSave(rascunho);
    setSalvando(false);
    setRascunho(null);
    setPinned(false);
  };

  const descartar = useCallback(() => {
    setRascunho(null);
    setPinned(false);
  }, []);

  const cancelHold = useCallback(() => {
    stopHoldRef.current?.();
    stopHoldRef.current = null;
    setHolding(null);
  }, []);

  useEffect(() => cancelHold, [cancelHold]);

  const startHold = useCallback(
    (event: PointerEvent, panel: HTMLElement, panelId: string) => {
      if (arranging || event.button > 0) return;
      cancelHold();

      const isMouse = event.pointerType === 'mouse';
      const startedAt = Date.now();
      const start = { x: event.clientX, y: event.clientY };
      let last = start;

      // Moving, releasing, cancelling and the browser taking over for a native drag all end the
      // hold. They are heard on the window, not on the panel: a panel that moves or resizes under
      // the pointer fires `pointerleave` on itself, and that used to kill a still hand's hold.
      const onMove = (move: PointerEvent) => {
        last = { x: move.clientX, y: move.clientY };
        setHolding((current) => (current ? { ...current, x: last.x, y: last.y } : current));
        if (Math.hypot(last.x - start.x, last.y - start.y) > HOLD_SLOP_PX) cancelHold();
      };
      const onEnd = () => cancelHold();
      const ticker = setInterval(() => setHeldMs(Date.now() - startedAt), 100);
      const detach = () => {
        clearTimeout(timer);
        clearInterval(ticker);
        window.removeEventListener('pointermove', onMove);
        window.removeEventListener('pointerup', onEnd);
        window.removeEventListener('pointercancel', onEnd);
        window.removeEventListener('dragstart', onEnd, true);
      };

      const timer = setTimeout(() => {
        detach();
        stopHoldRef.current = null;
        setHolding(null);
        // A field the press landed on keeps the caret and would go on taking keystrokes.
        if (document.activeElement instanceof HTMLElement) document.activeElement.blur();

        // O botão ainda está pressionado. A soltura que vem depois não pode virar um clique no que
        // estava debaixo do ponteiro, e o arrasto continua desta mesma pressão.
        const swallowClick = (click: Event) => {
          click.preventDefault();
          click.stopPropagation();
        };
        const handoff = isMouse ? { panel, x: last.x, y: last.y, released: false } : null;
        handoffRef.current = handoff;
        const stopSwallowing = () => {
          window.removeEventListener('click', swallowClick, true);
          window.removeEventListener('pointerup', onRelease, true);
          window.removeEventListener('pointerdown', stopSwallowing, true);
        };
        // O clique vem logo depois do pointerup, na mesma tarefa: só tirar o engolidor no timeout.
        const onRelease = () => {
          if (handoff) handoff.released = true;
          setTimeout(stopSwallowing, 0);
        };
        window.addEventListener('click', swallowClick, true);
        window.addEventListener('pointerup', onRelease, true);
        // Se a soltura se perdeu (fora da janela, por exemplo), a próxima pressão encerra o
        // engolidor antes do clique dela, em vez de ele comer um clique legítimo.
        window.addEventListener('pointerdown', stopSwallowing, true);
        setPinned(true);
      }, HOLD_MS);

      window.addEventListener('pointermove', onMove);
      window.addEventListener('pointerup', onEnd);
      window.addEventListener('pointercancel', onEnd);
      window.addEventListener('dragstart', onEnd, true);
      stopHoldRef.current = detach;
      setHeldMs(0);
      setHolding({ panelId, x: start.x, y: start.y });
    },
    [arranging, cancelHold],
  );

  // Heard in the capture phase on the window, not as a React handler on the panel: a child that
  // stops propagation (a drag library, a menu) would otherwise hide the press from the grid.
  useEffect(() => {
    const onDown = (event: PointerEvent) => {
      const panel = (event.target as Element | null)?.closest?.('[data-slot="grid-panel"]');
      if (!(panel instanceof HTMLElement)) return;
      const item = panel.parentElement;
      if (!item?.id.startsWith('painel-')) return;
      startHold(event, panel, item.id.slice('painel-'.length));
    };
    window.addEventListener('pointerdown', onDown, true);
    return () => window.removeEventListener('pointerdown', onDown, true);
  }, [startHold]);

  // The grid only starts a drag from a mousedown, and the one that began this press arrived while
  // dragging was still off. Once the mode is on, replay it at the pointer's position: the drag then
  // follows the real mouse moves, so holding and dragging is a single gesture.
  useEffect(() => {
    if (!pinned) return;
    const handoff = handoffRef.current;
    handoffRef.current = null;
    if (!handoff || handoff.released || !handoff.panel.isConnected) return;
    handoff.panel.dispatchEvent(
      new MouseEvent('mousedown', {
        bubbles: true,
        cancelable: true,
        button: 0,
        buttons: 1,
        clientX: handoff.x,
        clientY: handoff.y,
      }),
    );
  }, [pinned]);

  // Escape leaves the mode the way "Descartar" does.
  useEffect(() => {
    if (!pinned) return;
    const onKey = (event: KeyboardEvent) => {
      if (event.key === 'Escape') descartar();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [pinned, descartar]);

  // Objetos de configuração recriados a cada render provocam a mesma
  // re-sincronização que matava o arrasto.
  const gridConfig = useMemo(
    () => ({
      cols: GRID_COLUMNS,
      rowHeight: GRID_ROW_HEIGHT,
      margin: [24, 24] as [number, number],
      containerPadding: [0, 0] as [number, number],
    }),
    [],
  );
  const dragConfig = useMemo(
    () => ({
      enabled: arranging,
      // Controles interativos nunca iniciam arrasto: sem isto, redimensionar
      // um textarea viraria mover o painel.
      cancel: 'input, textarea, select, button, a',
    }),
    [arranging],
  );
  const resizeConfig = useMemo(
    () => ({ enabled: arranging, handles: ['se'] as const }),
    [arranging],
  );

  if (narrow) {
    const ordenados = [...visible].sort((a, b) => a.y - b.y || a.x - b.x);
    const modules = ordenados.flatMap((placement) =>
      isModuleId(placement.i) ? [placement.i] : [],
    );
    const requested = searchParams.get('modulo');
    const active =
      requested && isModuleId(requested) && modules.includes(requested)
        ? requested
        : modules[0];

    if (modules.length < 2 || !active) {
      return (
        <div className="flex flex-col gap-4">
          {ordenados.map((p) => panels.find((painel) => painel.id === p.i)?.node)}
        </div>
      );
    }

    const setActive = (next: ModuleId) => {
      const params = new URLSearchParams(searchParams.toString());
      if (next === modules[0]) params.delete('modulo');
      else params.set('modulo', next);
      const query = params.toString();
      router.push(query ? `${pathname}?${query}` : pathname, { scroll: false });
      // Quem rola é o <main> do AppShell, não a janela.
      narrowRef.current?.closest('main')?.scrollTo({ top: 0 });
    };

    return (
      <>
        <div
          ref={narrowRef}
          className="flex flex-col gap-4 pb-[calc(4.5rem+env(safe-area-inset-bottom))]"
        >
          {ordenados.map((p) => (
            // Os painéis ficam montados para preservar edições ainda não salvas.
            <div key={p.i} hidden={p.i !== active}>
              {panels.find((painel) => painel.id === p.i)?.node}
            </div>
          ))}
        </div>
        <MobileModuleNav modules={modules} active={active} onChange={setActive} />
      </>
    );
  }

  return (
    <div ref={containerRef}>
      {holding && (
        <div
          role="timer"
          aria-live="off"
          className="pointer-events-none fixed z-50 rounded-full border bg-glass-strong px-3 py-1 text-xs text-ink-mid shadow-e3 backdrop-blur-xl"
          style={{ left: holding.x + 18, top: holding.y + 18 }}
        >
          {`Segure para organizar · ${(Math.max(HOLD_MS - heldMs, 0) / 1000).toFixed(1).replace('.', ',')} s`}
        </div>
      )}

      {/* Only while arranging, and floating, so entering the mode does not push the panels down. */}
      {arranging && (
        <div className="fixed bottom-6 left-1/2 z-40 flex max-w-[calc(100vw-2rem)] -translate-x-1/2 items-center gap-3 rounded-full border bg-glass-strong py-2 pr-2 pl-5 shadow-e4 backdrop-blur-xl">
          <p role="status" className="min-w-0 truncate text-sm text-ink-mid">
            {`Arraste para mover, puxe o canto para redimensionar. Salvar guarda para ${janela.largura} × ${janela.altura}.`}
          </p>
          <div className="flex shrink-0 items-center gap-2">
            <Button
              type="button"
              variant="default"
              size="sm"
              disabled={salvando}
              onClick={() => void salvar()}
            >
              {salvando ? 'Salvando…' : 'Salvar para esta tela'}
            </Button>
            <IconAction
              variant="outline"
              label="Descartar"
              onClick={descartar}
              icon={<X className="size-4" />}
            />
          </div>
        </div>
      )}

      {mounted && (
        <GridLayout
          className={`dashboard-grid${arranging ? ' is-arranging' : ''}`}
          width={width}
          layout={visible}
          gridConfig={gridConfig}
          // Fora do modo de organizar, o painel é conteúdo comum: clicar num
          // e-mail, marcar uma tarefa e selecionar texto continuam funcionando.
          dragConfig={dragConfig}
          resizeConfig={resizeConfig}
          onLayoutChange={handleChange}
          onDragStart={() => setDragging(true)}
          // `onDrag` e `onResize` precisam existir mesmo sem fazer nada: com o
          // limiar de 3px, a grade adia o início do arrasto para dentro deles
          // (`if (!onDragProp || !dragging) return`). Sem passá-los, o limiar
          // nunca é ultrapassado e o painel não sai do lugar.
          onDrag={naoFazNada}
          onDragStop={() => setDragging(false)}
          onResizeStart={() => setDragging(true)}
          onResize={naoFazNada}
          onResizeStop={() => setDragging(false)}
        >
          {visible.map((p) => (
            // The outer element is the one the grid positions with a transform; the card
            // inside is what shakes, because a rotation set on the positioned element would
            // swing it around a point far from its own centre.
            <div
              key={p.i}
              // Id estável: é por ele que uma confirmação de outro painel
              // consegue trazer a tela até aqui.
              id={`painel-${p.i}`}
              tabIndex={-1}
              data-grid={{ ...p, minW: MIN_PANEL_WIDTH, minH: MIN_PANEL_HEIGHT }}
            >
              <div
                data-slot="grid-panel"
                data-pressing={holding?.panelId === p.i ? 'true' : undefined}
                className={cn(cardSurface, 'flex size-full min-w-0 flex-col overflow-hidden')}
              >
                <PanelFrame>{panels.find((painel) => painel.id === p.i)?.node}</PanelFrame>
              </div>
            </div>
          ))}
        </GridLayout>
      )}
    </div>
  );
}
