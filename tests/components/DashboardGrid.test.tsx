import { describe, expect, it, vi, afterEach, beforeEach } from 'vitest';
import { render, screen, cleanup, fireEvent, waitFor, act } from '@testing-library/react';

const nav = vi.hoisted(() => ({
  search: '',
  history: [] as string[],
  listeners: new Set<() => void>(),
}));

vi.mock('next/navigation', async () => {
  const { useSyncExternalStore } = await import('react');
  const subscribe = (listener: () => void) => {
    nav.listeners.add(listener);
    return () => nav.listeners.delete(listener);
  };
  const push = (url: string) => {
    nav.history.push(url);
    nav.search = url.split('?')[1] ?? '';
    nav.listeners.forEach((listener) => listener());
  };
  return {
    usePathname: () => '/',
    useRouter: () => ({ push }),
    useSearchParams: () =>
      new URLSearchParams(useSyncExternalStore(subscribe, () => nav.search)),
  };
});

// A grade de verdade precisa medir largura e observar redimensionamento, que
// o jsdom não faz. O que interessa testar aqui é o que decidimos: quando o
// modo de organizar liga, o que é passado para a grade e o que acontece numa
// tela estreita.
const props: Record<string, unknown>[] = [];
vi.mock('react-grid-layout', () => ({
  default: (p: Record<string, unknown>) => {
    props.push(p);
    return <div data-testid="grade">{p.children as React.ReactNode}</div>;
  },
  useContainerWidth: () => ({ width: 1440, mounted: true, containerRef: { current: null } }),
}));

import { DashboardGrid } from '@/components/DashboardGrid';
import { defaultLayout } from '@/lib/dashboardLayout';

const painéis = [
  { id: 'email', node: <p>painel de e-mail</p> },
  { id: 'jira', node: <p>painel do jira</p> },
];

function larguraDaJanela(px: number) {
  window.matchMedia = ((query: string) => ({
    matches: px <= 1023,
    media: query,
    addEventListener: () => {},
    removeEventListener: () => {},
  })) as unknown as typeof window.matchMedia;
}

beforeEach(() => {
  props.length = 0;
  nav.search = '';
  nav.history = [];
  larguraDaJanela(1440);
  vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
});

afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
});

const ultimasProps = () => props[props.length - 1];

const painelDe = (texto: string) =>
  screen.getByText(texto).closest('[data-slot="grid-panel"]') as HTMLElement;

// O modo liga ao segurar um painel por 1 s. Os timers falsos só valem durante o gesto: o resto
// dos testes usa `waitFor`, que precisa do relógio de verdade.
function segurarPainel(texto = 'painel de e-mail', ms = 1000) {
  vi.useFakeTimers();
  fireEvent.pointerDown(painelDe(texto), { button: 0, clientX: 10, clientY: 10 });
  act(() => {
    vi.advanceTimersByTime(ms);
  });
  // A pessoa solta o botão: é a soltura que desfaz o engolidor de clique do fim do gesto.
  fireEvent.pointerUp(painelDe(texto));
  act(() => {
    vi.advanceTimersByTime(10);
  });
  vi.useRealTimers();
}

describe('DashboardGrid', () => {
  it('desenha só os painéis dos módulos ligados', () => {
    render(
      <DashboardGrid layout={defaultLayout()} panels={painéis} onSave={() => {}} />,
    );
    expect(screen.getByText('painel de e-mail')).toBeInTheDocument();
    expect(screen.getByText('painel do jira')).toBeInTheDocument();
    expect((ultimasProps().layout as { i: string }[]).map((p) => p.i).sort()).toEqual([
      'email',
      'jira',
    ]);
  });

  // Fora do modo de organizar o painel é conteúdo comum: clicar num e-mail,
  // marcar uma tarefa e selecionar texto precisam continuar funcionando.
  it('começa com arrastar e redimensionar desligados', () => {
    render(<DashboardGrid layout={defaultLayout()} panels={painéis} onSave={() => {}} />);
    expect((ultimasProps().dragConfig as { enabled: boolean }).enabled).toBe(false);
    expect((ultimasProps().resizeConfig as { enabled: boolean }).enabled).toBe(false);
  });

  // Segurar Ctrl chegou a ligar o modo. Não liga mais: a única entrada é segurar
  // um painel, e uma tecla comum não pode mudar o que o gesto faz.
  it('não liga ao segurar Ctrl', () => {
    render(<DashboardGrid layout={defaultLayout()} panels={painéis} onSave={() => {}} />);

    fireEvent.keyDown(window, { key: 'Control' });
    expect((ultimasProps().dragConfig as { enabled: boolean }).enabled).toBe(false);
    expect((ultimasProps().resizeConfig as { enabled: boolean }).enabled).toBe(false);
  });

  it('segurar um painel por 1 s prende o modo até ser desligado', () => {
    render(<DashboardGrid layout={defaultLayout()} panels={painéis} onSave={() => {}} />);

    segurarPainel();
    expect((ultimasProps().dragConfig as { enabled: boolean }).enabled).toBe(true);
    expect((ultimasProps().resizeConfig as { enabled: boolean }).enabled).toBe(true);

    fireEvent.click(screen.getByRole('button', { name: 'Descartar' }));
    expect((ultimasProps().dragConfig as { enabled: boolean }).enabled).toBe(false);
    expect((ultimasProps().resizeConfig as { enabled: boolean }).enabled).toBe(false);
  });

  // A dica ficava na tela o tempo todo dizendo para segurar Ctrl.
  it('não anuncia o Ctrl fora do modo', () => {
    render(<DashboardGrid layout={defaultLayout()} panels={painéis} onSave={() => {}} />);
    expect(screen.queryByText(/Ctrl/i)).toBeNull();
    expect(screen.queryByRole('status')).toBeNull();

    segurarPainel();
    expect(screen.getByRole('status')).toHaveTextContent(/Arraste para mover/);
  });

  it('numa tela estreita mostra só o primeiro painel e a navegação', () => {
    larguraDaJanela(390);
    const tresPainéis = [
      ...painéis,
      { id: 'tasks', node: <p>painel de tarefas</p> },
    ];
    render(<DashboardGrid layout={defaultLayout()} panels={tresPainéis} onSave={() => {}} />);

    expect(screen.queryByTestId('grade')).toBeNull();
    expect(screen.queryByRole('button', { name: 'Organizar' })).toBeNull();
    expect(screen.getByText('painel de e-mail').parentElement).not.toHaveAttribute('hidden');
    expect(screen.getByText('painel do jira').parentElement).toHaveAttribute('hidden');
    expect(screen.getByText('painel de tarefas').parentElement).toHaveAttribute('hidden');
    expect(screen.getByRole('navigation', { name: 'módulos' })).toBeInTheDocument();
    expect(screen.getAllByRole('button')).toHaveLength(3);
  });

  it('mostra o painel indicado por modulo', () => {
    larguraDaJanela(390);
    nav.search = 'modulo=jira';
    render(<DashboardGrid layout={defaultLayout()} panels={painéis} onSave={() => {}} />);

    expect(screen.getByText('painel de e-mail').parentElement).toHaveAttribute('hidden');
    expect(screen.getByText('painel do jira').parentElement).not.toHaveAttribute('hidden');
  });

  it.each(['modulo=lixo', 'modulo=agenda'])(
    'volta ao primeiro painel quando o parâmetro não vale: %s',
    (search) => {
      larguraDaJanela(390);
      nav.search = search;
      render(<DashboardGrid layout={defaultLayout()} panels={painéis} onSave={() => {}} />);

      expect(screen.getByText('painel de e-mail').parentElement).not.toHaveAttribute('hidden');
      expect(screen.getByText('painel do jira').parentElement).toHaveAttribute('hidden');
    },
  );

  it('troca o módulo na URL sem apagar os outros parâmetros', () => {
    larguraDaJanela(390);
    nav.search = 'filtro=hoje';
    // A página rola dentro do <main> do AppShell, e é ele que volta ao topo.
    const main = document.createElement('main');
    main.scrollTo = vi.fn();
    document.body.appendChild(main);
    render(<DashboardGrid layout={defaultLayout()} panels={painéis} onSave={() => {}} />, {
      container: main,
    });

    fireEvent.click(screen.getByRole('button', { name: 'Jira' }));

    expect(nav.history.at(-1)).toBe('/?filtro=hoje&modulo=jira');
    expect(main.scrollTo).toHaveBeenCalledWith({ top: 0 });
    main.remove();
  });

  it('tira o módulo padrão da URL', () => {
    larguraDaJanela(390);
    nav.search = 'filtro=hoje&modulo=jira';
    render(<DashboardGrid layout={defaultLayout()} panels={painéis} onSave={() => {}} />);

    fireEvent.click(screen.getByRole('button', { name: 'E-mail' }));

    expect(nav.history.at(-1)).toBe('/?filtro=hoje');
  });

  it('não mostra navegação para um painel só', () => {
    larguraDaJanela(390);
    render(
      <DashboardGrid layout={defaultLayout()} panels={[painéis[0]]} onSave={() => {}} />,
    );

    expect(screen.queryByRole('navigation', { name: 'módulos' })).toBeNull();
    expect(screen.getByText('painel de e-mail')).toBeInTheDocument();
  });

  // Arrastar não grava mais nada sozinho: a gravação é do botão.
  it('arrastar não chama o salvamento', () => {
    const onSave = vi.fn();
    render(<DashboardGrid layout={defaultLayout()} panels={painéis} onSave={onSave} />);

    const emitir = ultimasProps().onLayoutChange as (l: unknown) => void;
    emitir([
      { i: 'email', x: 5, y: 0, w: 7, h: 14 },
      { i: 'jira', x: 0, y: 9, w: 5, h: 12 },
    ]);
    expect(onSave).not.toHaveBeenCalled();
  });
});

describe('segurar um painel para organizar', () => {
  const entrou = () => (ultimasProps().dragConfig as { enabled: boolean }).enabled;

  it('não liga antes de 1 s', () => {
    render(<DashboardGrid layout={defaultLayout()} panels={painéis} onSave={() => {}} />);
    segurarPainel('painel de e-mail', 900);

    expect(entrou()).toBe(false);
    expect(screen.queryByRole('button', { name: /Salvar/ })).toBeNull();
  });

  it('soltar antes de 1 s cancela', () => {
    render(<DashboardGrid layout={defaultLayout()} panels={painéis} onSave={() => {}} />);
    vi.useFakeTimers();
    fireEvent.pointerDown(painelDe('painel de e-mail'), { button: 0, clientX: 10, clientY: 10 });
    act(() => {
      vi.advanceTimersByTime(500);
    });
    fireEvent.pointerUp(painelDe('painel de e-mail'));
    act(() => {
      vi.advanceTimersByTime(1000);
    });
    vi.useRealTimers();

    expect(entrou()).toBe(false);
  });

  it('mexer o ponteiro além da folga cancela: é seleção ou arrasto, não o gesto', () => {
    render(<DashboardGrid layout={defaultLayout()} panels={painéis} onSave={() => {}} />);
    vi.useFakeTimers();
    fireEvent.pointerDown(painelDe('painel de e-mail'), { button: 0, clientX: 10, clientY: 10 });
    fireEvent.pointerMove(painelDe('painel de e-mail'), { clientX: 60, clientY: 10 });
    act(() => {
      vi.advanceTimersByTime(1000);
    });
    vi.useRealTimers();

    expect(entrou()).toBe(false);
  });

  it('uma tremidinha dentro da folga não cancela', () => {
    render(<DashboardGrid layout={defaultLayout()} panels={painéis} onSave={() => {}} />);
    vi.useFakeTimers();
    fireEvent.pointerDown(painelDe('painel de e-mail'), { button: 0, clientX: 10, clientY: 10 });
    fireEvent.pointerMove(painelDe('painel de e-mail'), { clientX: 13, clientY: 12 });
    act(() => {
      vi.advanceTimersByTime(1000);
    });
    vi.useRealTimers();

    expect(entrou()).toBe(true);
  });

  // Um painel que é quase todo campo de texto (notas, busca) não pode ficar sem onde segurar.
  it('segurar num campo de texto liga o modo e tira o foco dele', () => {
    render(
      <DashboardGrid
        layout={defaultLayout()}
        panels={[
          { id: 'email', node: <input aria-label="buscar" /> },
          { id: 'jira', node: <p>painel do jira</p> },
        ]}
        onSave={() => {}}
      />,
    );
    const campo = screen.getByLabelText('buscar');
    campo.focus();
    vi.useFakeTimers();
    fireEvent.pointerDown(campo, { button: 0, clientX: 10, clientY: 10 });
    act(() => {
      vi.advanceTimersByTime(1000);
    });
    vi.useRealTimers();

    expect(entrou()).toBe(true);
    expect(campo).not.toHaveFocus();
  });

  // Uma biblioteca de arrastar ou um menu dentro do painel pode interromper a propagação.
  it('um filho que interrompe a propagação não esconde a pressão da grade', () => {
    render(
      <DashboardGrid
        layout={defaultLayout()}
        panels={[
          {
            id: 'email',
            node: (
              <div onPointerDown={(e) => e.stopPropagation()}>
                <p>conteúdo que intercepta</p>
              </div>
            ),
          },
          { id: 'jira', node: <p>painel do jira</p> },
        ]}
        onSave={() => {}}
      />,
    );
    vi.useFakeTimers();
    fireEvent.pointerDown(screen.getByText('conteúdo que intercepta'), {
      button: 0,
      clientX: 10,
      clientY: 10,
    });
    act(() => {
      vi.advanceTimersByTime(1000);
    });
    vi.useRealTimers();

    expect(entrou()).toBe(true);
  });

  // O navegador assume o ponteiro quando um item arrastável começa a ser arrastado.
  it('o arrasto nativo de um item cancela: é um arrasto, não o gesto', () => {
    render(<DashboardGrid layout={defaultLayout()} panels={painéis} onSave={() => {}} />);
    vi.useFakeTimers();
    fireEvent.pointerDown(painelDe('painel de e-mail'), { button: 0, clientX: 10, clientY: 10 });
    fireEvent.dragStart(painelDe('painel de e-mail'));
    act(() => {
      vi.advanceTimersByTime(1000);
    });
    vi.useRealTimers();

    expect(entrou()).toBe(false);
  });

  it('mostra um contador ao lado do ponteiro enquanto segura', () => {
    render(<DashboardGrid layout={defaultLayout()} panels={painéis} onSave={() => {}} />);
    expect(screen.queryByRole('timer')).toBeNull();

    vi.useFakeTimers();
    fireEvent.pointerDown(painelDe('painel de e-mail'), { button: 0, clientX: 10, clientY: 10 });
    expect(screen.getByRole('timer')).toHaveTextContent('1,0 s');
    act(() => {
      vi.advanceTimersByTime(400);
    });
    expect(screen.getByRole('timer')).toHaveTextContent(/0,6 s|0,5 s/);

    fireEvent.pointerUp(painelDe('painel de e-mail'));
    expect(screen.queryByRole('timer')).toBeNull();
    vi.useRealTimers();
  });

  // Um painel cheio de botões e cartões clicáveis quase não teria onde segurar.
  it('segurar em cima de um botão liga o modo', () => {
    render(
      <DashboardGrid
        layout={defaultLayout()}
        panels={[
          { id: 'email', node: <button type="button">arquivar</button> },
          { id: 'jira', node: <p>painel do jira</p> },
        ]}
        onSave={() => {}}
      />,
    );
    vi.useFakeTimers();
    fireEvent.pointerDown(screen.getByRole('button', { name: 'arquivar' }), {
      button: 0,
      clientX: 10,
      clientY: 10,
    });
    act(() => {
      vi.advanceTimersByTime(1000);
    });
    vi.useRealTimers();

    expect(entrou()).toBe(true);
  });

  it('a pressão perdida não engole um clique legítimo depois', () => {
    const onClick = vi.fn();
    render(
      <DashboardGrid
        layout={defaultLayout()}
        panels={[
          { id: 'email', node: <button type="button" onClick={onClick}>arquivar</button> },
          { id: 'jira', node: <p>painel do jira</p> },
        ]}
        onSave={() => {}}
      />,
    );
    const botao = screen.getByRole('button', { name: 'arquivar' });
    vi.useFakeTimers();
    fireEvent.pointerDown(botao, { button: 0, clientX: 10, clientY: 10 });
    act(() => {
      vi.advanceTimersByTime(1000);
    });
    // O pointerup nunca chegou (soltou fora da janela). A próxima pressão é outra.
    fireEvent.pointerDown(botao, { button: 0, clientX: 10, clientY: 10 });
    fireEvent.pointerUp(botao);
    fireEvent.click(botao);
    act(() => {
      vi.advanceTimersByTime(10);
    });
    vi.useRealTimers();

    expect(onClick).toHaveBeenCalledTimes(1);
  });

  it('soltar depois de 1 s não dispara o clique do botão que estava debaixo', () => {
    const onClick = vi.fn();
    render(
      <DashboardGrid
        layout={defaultLayout()}
        panels={[
          { id: 'email', node: <button type="button" onClick={onClick}>arquivar</button> },
          { id: 'jira', node: <p>painel do jira</p> },
        ]}
        onSave={() => {}}
      />,
    );
    const botao = screen.getByRole('button', { name: 'arquivar' });
    vi.useFakeTimers();
    fireEvent.pointerDown(botao, { button: 0, clientX: 10, clientY: 10 });
    act(() => {
      vi.advanceTimersByTime(1000);
    });
    fireEvent.pointerUp(botao);
    fireEvent.click(botao);
    act(() => {
      vi.advanceTimersByTime(10);
    });
    vi.useRealTimers();

    expect(onClick).not.toHaveBeenCalled();
    fireEvent.click(botao);
    expect(onClick).toHaveBeenCalledTimes(1);
  });

  // O painel mudar de tamanho ou de lugar debaixo do ponteiro faz o navegador disparar
  // `pointerleave` nele; isso não pode matar o gesto.
  it('o ponteiro sair do painel no meio do 1 s não cancela', () => {
    render(<DashboardGrid layout={defaultLayout()} panels={painéis} onSave={() => {}} />);
    vi.useFakeTimers();
    fireEvent.pointerDown(painelDe('painel de e-mail'), { button: 0, clientX: 10, clientY: 10 });
    fireEvent.pointerLeave(painelDe('painel de e-mail'));
    act(() => {
      vi.advanceTimersByTime(1000);
    });
    vi.useRealTimers();

    expect(entrou()).toBe(true);
  });

  it('aguenta a mão tremendo até a folga', () => {
    render(<DashboardGrid layout={defaultLayout()} panels={painéis} onSave={() => {}} />);
    vi.useFakeTimers();
    fireEvent.pointerDown(painelDe('painel de e-mail'), { button: 0, clientX: 100, clientY: 100 });
    for (const [x, y] of [[112, 96], [90, 108], [115, 92], [104, 112]]) {
      fireEvent.pointerMove(painelDe('painel de e-mail'), { clientX: x, clientY: y });
    }
    act(() => {
      vi.advanceTimersByTime(1000);
    });
    vi.useRealTimers();

    expect(entrou()).toBe(true);
  });

  it('só o botão principal conta', () => {
    render(<DashboardGrid layout={defaultLayout()} panels={painéis} onSave={() => {}} />);
    vi.useFakeTimers();
    fireEvent.pointerDown(painelDe('painel de e-mail'), { button: 2, clientX: 10, clientY: 10 });
    act(() => {
      vi.advanceTimersByTime(1000);
    });
    vi.useRealTimers();

    expect(entrou()).toBe(false);
  });

  it('marca o painel segurado enquanto o 1 s passa', () => {
    render(<DashboardGrid layout={defaultLayout()} panels={painéis} onSave={() => {}} />);
    vi.useFakeTimers();
    fireEvent.pointerDown(painelDe('painel de e-mail'), { button: 0, clientX: 10, clientY: 10 });

    expect(painelDe('painel de e-mail')).toHaveAttribute('data-pressing', 'true');
    expect(painelDe('painel do jira')).not.toHaveAttribute('data-pressing');

    fireEvent.pointerUp(painelDe('painel de e-mail'));
    expect(painelDe('painel de e-mail')).not.toHaveAttribute('data-pressing');
    vi.useRealTimers();
  });

  it('a grade passa a tremer: ganha a classe do modo', () => {
    render(<DashboardGrid layout={defaultLayout()} panels={painéis} onSave={() => {}} />);
    expect(String(ultimasProps().className)).not.toContain('is-arranging');

    segurarPainel();
    expect(String(ultimasProps().className)).toContain('is-arranging');
  });

  it('Escape sai do modo sem gravar', () => {
    const onSave = vi.fn();
    render(<DashboardGrid layout={defaultLayout()} panels={painéis} onSave={onSave} />);
    segurarPainel();
    expect(entrou()).toBe(true);

    fireEvent.keyDown(window, { key: 'Escape' });

    expect(entrou()).toBe(false);
    expect(onSave).not.toHaveBeenCalled();
  });

  it('não existe mais o botão Organizar', () => {
    render(<DashboardGrid layout={defaultLayout()} panels={painéis} onSave={() => {}} />);
    expect(screen.queryByRole('button', { name: 'Organizar' })).toBeNull();
  });
});

describe('salvar para esta tela', () => {
  // A grade chama isto de fora do React; sem o act, a mudança de estado não
  // é processada antes do clique seguinte.
  function arrastar(para: unknown) {
    act(() => {
      (ultimasProps().onLayoutChange as (l: unknown) => void)(para);
    });
  }
  const MOVIDO = [
    { i: 'email', x: 5, y: 0, w: 7, h: 14 },
    { i: 'jira', x: 0, y: 9, w: 5, h: 12 },
  ];

  it('fora do modo não há botão de organizar nem de salvar', () => {
    render(<DashboardGrid layout={defaultLayout()} panels={painéis} onSave={() => {}} />);
    expect(screen.queryByRole('button', { name: 'Organizar' })).toBeNull();
    expect(screen.queryByRole('button', { name: /Salvar/ })).toBeNull();
  });

  it('no modo, aparecem salvar e descartar', () => {
    render(<DashboardGrid layout={defaultLayout()} panels={painéis} onSave={() => {}} />);
    segurarPainel();

    expect(screen.getByRole('button', { name: 'Salvar para esta tela' })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Descartar' })).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Organizar' })).toBeNull();
  });

  it('salva o que foi arrastado', async () => {
    const onSave = vi.fn();
    render(<DashboardGrid layout={defaultLayout()} panels={painéis} onSave={onSave} />);
    segurarPainel();

    arrastar(MOVIDO);
    fireEvent.click(screen.getByRole('button', { name: 'Salvar para esta tela' }));

    await waitFor(() => expect(onSave).toHaveBeenCalledTimes(1));
    const salvo = onSave.mock.calls[0][0] as { i: string; x: number }[];
    expect(salvo.find((p) => p.i === 'email')?.x).toBe(5);
  });

  // Entrar no modo e não mexer em nada ainda é uma escolha: fixa a disposição
  // atual para esta tela.
  it('salva a disposição atual mesmo sem arrastar', async () => {
    const onSave = vi.fn();
    render(<DashboardGrid layout={defaultLayout()} panels={painéis} onSave={onSave} />);
    segurarPainel();
    fireEvent.click(screen.getByRole('button', { name: 'Salvar para esta tela' }));

    await waitFor(() => expect(onSave).toHaveBeenCalledTimes(1));
  });

  it('descartar sai do modo sem gravar', () => {
    const onSave = vi.fn();
    render(<DashboardGrid layout={defaultLayout()} panels={painéis} onSave={onSave} />);
    segurarPainel();

    arrastar(MOVIDO);
    fireEvent.click(screen.getByRole('button', { name: 'Descartar' }));

    expect(onSave).not.toHaveBeenCalled();
    expect(screen.queryByRole('button', { name: /Salvar/ })).toBeNull();
  });

  // O que foi arrastado e descartado não pode continuar na tela.
  it('descartar devolve a disposição gravada', () => {
    render(<DashboardGrid layout={defaultLayout()} panels={painéis} onSave={() => {}} />);
    segurarPainel();

    arrastar(MOVIDO);
    expect((ultimasProps().layout as { i: string; x: number }[]).find((p) => p.i === 'email')?.x).toBe(5);

    fireEvent.click(screen.getByRole('button', { name: 'Descartar' }));
    const padrao = defaultLayout().find((p) => p.i === 'email')!;
    expect((ultimasProps().layout as { i: string; x: number }[]).find((p) => p.i === 'email')?.x).toBe(
      padrao.x,
    );
  });

  it('salvar fecha o modo', async () => {
    render(<DashboardGrid layout={defaultLayout()} panels={painéis} onSave={() => {}} />);
    segurarPainel();
    fireEvent.click(screen.getByRole('button', { name: 'Salvar para esta tela' }));

    await waitFor(() => expect(screen.queryByRole('button', { name: /Salvar/ })).toBeNull());
  });

  // Sem ver o tamanho, salvar é às cegas.
  it('a dica diz para qual tela vai gravar', () => {
    render(<DashboardGrid layout={defaultLayout()} panels={painéis} onSave={() => {}} />);
    segurarPainel();

    expect(screen.getByRole('status')).toHaveTextContent(
      `${window.innerWidth} × ${window.innerHeight}`,
    );
  });
});
