import { describe, expect, it, vi, afterEach } from 'vitest';
import { render, screen, cleanup, fireEvent, waitFor } from '@testing-library/react';
import { Pomodoro } from '@/components/Pomodoro';

afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
});

const base = {
  enabled: true,
  phase: 'focus' as const,
  running: false,
  remainingSeconds: 90,
  focusMinutes: 25,
  restMinutes: 5,
  completedFocusCount: 2,
};

describe('Pomodoro', () => {
  it('mostra a fase, o tempo restante e o contador de focos', () => {
    render(<Pomodoro pomodoro={base} onChanged={() => {}} />);
    const text = screen.getByTestId('pomodoro').textContent ?? '';
    expect(text).toContain('foco');
    expect(text).toContain('01:30');
    expect(text).toContain('2 focos');
  });

  it('empilha a fase e o contador, e põe o tempo ao lado dos botões', () => {
    render(<Pomodoro pomodoro={base} onChanged={() => {}} />);

    const fase = screen.getByText('foco');
    const contador = screen.getByText('2 focos');
    expect(fase.parentElement).toBe(contador.parentElement);

    const tempo = screen.getByText('01:30');
    const iniciar = screen.getByRole('button', { name: 'iniciar foco' });
    expect(tempo.parentElement).toBe(iniciar.parentElement?.parentElement);
    expect(tempo.parentElement).not.toBe(fase.parentElement);
  });

  it('não desenha a barra de progresso', () => {
    render(<Pomodoro pomodoro={base} onChanged={() => {}} />);
    expect(screen.getByTestId('pomodoro').querySelector('[style*="scaleX"]')).toBeNull();
  });

  it('não renderiza nada quando o pomodoro está desligado', () => {
    render(<Pomodoro pomodoro={{ ...base, enabled: false }} onChanged={() => {}} />);
    expect(screen.queryByTestId('pomodoro')).toBeNull();
  });

  it('clicar em iniciar chama a API de start e avisa onChanged', async () => {
    const fetchSpy = vi.spyOn(global, 'fetch').mockResolvedValue(new Response('{}'));
    const onChanged = vi.fn();
    render(<Pomodoro pomodoro={base} onChanged={onChanged} />);
    fireEvent.click(screen.getByRole('button', { name: 'iniciar foco' }));
    await waitFor(() =>
      expect(fetchSpy).toHaveBeenCalledWith('/api/pomodoro/start', { method: 'POST' }),
    );
    await waitFor(() => expect(onChanged).toHaveBeenCalled());
  });

  it('mostra pausar quando já está rodando', () => {
    render(<Pomodoro pomodoro={{ ...base, running: true }} onChanged={() => {}} />);
    expect(screen.getByRole('button', { name: 'pausar foco' })).toBeInTheDocument();
  });

  it('mostra erro e não avisa onChanged quando a API falha', async () => {
    vi.spyOn(global, 'fetch').mockResolvedValue(
      new Response(JSON.stringify({ error: 'falhou' }), { status: 502 }),
    );
    const onChanged = vi.fn();
    render(<Pomodoro pomodoro={base} onChanged={onChanged} />);
    fireEvent.click(screen.getByRole('button', { name: 'iniciar foco' }));
    await waitFor(() => expect(screen.getByRole('alert').textContent).toContain('falhou'));
    expect(onChanged).not.toHaveBeenCalled();
  });
});
