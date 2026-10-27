import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { cleanup, fireEvent, render, screen } from '@testing-library/react';
import { AppearancePanel } from '@/components/AppearancePanel';

const toast = vi.hoisted(() => ({ error: vi.fn() }));
vi.mock('sonner', () => ({ toast }));
import { TooltipProvider } from '@/components/ui/tooltip';
import { WIDTH_COOKIE, type ContentWidth } from '@/lib/theme';

let fetchMock: ReturnType<typeof vi.fn>;

beforeEach(() => {
  toast.error.mockClear();
  fetchMock = vi.fn(() => Promise.resolve(new Response('{}', { status: 200 })));
  vi.stubGlobal('fetch', fetchMock);
});

afterEach(() => {
  vi.unstubAllGlobals();
  cleanup();
  delete document.documentElement.dataset.width;
  document.cookie = `${WIDTH_COOKIE}=; path=/; max-age=0`;
});

function panel(initialWidth: ContentWidth = 'full') {
  return (
    <TooltipProvider>
      <AppearancePanel
        initialTheme="system"
        initialDensity="comfortable"
        initialBackdrop="mesh"
        initialWidth={initialWidth}
      />
    </TooltipProvider>
  );
}

describe('largura do conteúdo', () => {
  it('começa desligado: a largura toda é o padrão', () => {
    render(panel());

    expect(screen.getByRole('switch', { name: 'Limitar largura' })).not.toBeChecked();
  });

  it('ligar limita a largura: marca a raiz e grava o cookie', () => {
    render(panel());

    fireEvent.click(screen.getByRole('switch', { name: 'Limitar largura' }));

    expect(screen.getByRole('switch', { name: 'Limitar largura' })).toBeChecked();
    expect(document.documentElement.dataset.width).toBe('limited');
    expect(document.cookie).toContain(`${WIDTH_COOKIE}=limited`);
  });

  it('desligar volta à largura toda', () => {
    document.documentElement.dataset.width = 'limited';
    render(panel('limited'));
    expect(screen.getByRole('switch', { name: 'Limitar largura' })).toBeChecked();

    fireEvent.click(screen.getByRole('switch', { name: 'Limitar largura' }));

    expect(document.documentElement.dataset.width).toBeUndefined();
    expect(document.cookie).not.toContain(WIDTH_COOKIE);
  });

  // A raiz é a verdade: um cookie apagado em outra aba não pode deixar o painel mostrando
  // uma escolha que já não vale.
  it('mostra o que a raiz diz, e não só o que veio do servidor', () => {
    document.documentElement.dataset.width = 'limited';
    render(panel('full'));

    expect(screen.getByRole('switch', { name: 'Limitar largura' })).toBeChecked();
  });

  it('tem o ícone de informação para explicar a opção', () => {
    render(panel());

    expect(screen.getByRole('button', { name: 'Sobre limitar a largura' })).toBeInTheDocument();
  });
});

describe('salvar na conta', () => {
  const bodies = () =>
    fetchMock.mock.calls.map(([, init]) => JSON.parse(String((init as RequestInit).body)));

  it('a largura vai para a conta ao ligar e ao desligar', async () => {
    render(panel());

    fireEvent.click(screen.getByRole('switch', { name: 'Limitar largura' }));
    fireEvent.click(screen.getByRole('switch', { name: 'Limitar largura' }));

    await vi.waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(2));
    expect(bodies()).toEqual([
      { appearance: { width: 'limited' } },
      { appearance: { width: 'full' } },
    ]);
  });

  it('tema, densidade e fundo também vão para a conta', async () => {
    render(panel());

    fireEvent.click(screen.getByRole('button', { name: 'Escuro' }));
    fireEvent.click(screen.getByRole('button', { name: 'Compacto' }));
    fireEvent.click(screen.getByRole('button', { name: 'Catppuccin' }));

    await vi.waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(3));
    expect(bodies()).toEqual([
      { appearance: { theme: 'dark' } },
      { appearance: { density: 'compact' } },
      { appearance: { backdrop: 'catppuccin' } },
    ]);
  });

  it('a escolha aparece na hora, sem esperar o servidor', () => {
    fetchMock.mockImplementation(() => new Promise(() => {}));
    render(panel());

    fireEvent.click(screen.getByRole('switch', { name: 'Limitar largura' }));

    expect(document.documentElement.dataset.width).toBe('limited');
  });

  it('avisa quando o servidor não guardou, e a escolha continua valendo no navegador', async () => {
    fetchMock.mockImplementation(() =>
      Promise.resolve(new Response(JSON.stringify({ error: 'não autenticado' }), { status: 401 })),
    );
    render(panel());

    fireEvent.click(screen.getByRole('switch', { name: 'Limitar largura' }));

    await vi.waitFor(() => expect(toast.error).toHaveBeenCalledTimes(1));
    expect(toast.error.mock.calls[0][0]).toContain('não autenticado');
    expect(document.documentElement.dataset.width).toBe('limited');
  });
});
