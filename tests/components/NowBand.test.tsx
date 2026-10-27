import { afterEach, describe, expect, it, vi } from 'vitest';
import { cleanup, render, screen } from '@testing-library/react';
import { NowBand } from '@/components/NowBand';

vi.stubGlobal(
  'fetch',
  vi.fn(() => Promise.resolve({ ok: false })),
);

afterEach(cleanup);

function band(over: Partial<Parameters<typeof NowBand>[0]> = {}) {
  return (
    <NowBand
      greetingName="Philippe"
      welcome="first"
      pomodoro={null}
      onChanged={() => {}}
      {...over}
    />
  );
}

describe('NowBand greeting', () => {
  it('greets the person by name and welcomes a first visit', () => {
    render(band());

    expect(screen.getByRole('heading', { name: 'Olá, Philippe' })).toBeInTheDocument();
    expect(screen.getByText('Bem-vindo')).toBeInTheDocument();
  });

  it('welcomes a returning person back', () => {
    render(band({ welcome: 'returning' }));

    expect(screen.getByText('Bem-vindo de volta')).toBeInTheDocument();
  });

  it('still greets when no name is known', () => {
    render(band({ greetingName: null }));

    expect(screen.getByRole('heading', { name: 'Olá' })).toBeInTheDocument();
  });

  it('no longer shows the last update or the next refresh', () => {
    render(band());

    expect(screen.queryByText(/atualizado/i)).toBeNull();
    expect(screen.queryByText(/próxima em/i)).toBeNull();
  });

  it('has no bell of its own: the header has the only one', () => {
    render(band());

    expect(screen.queryByRole('button', { name: /notificações/ })).toBeNull();
  });

  it('no longer carries the refresh button or the settings link', () => {
    render(band());

    expect(screen.queryByRole('button', { name: /atualizar/i })).toBeNull();
    expect(screen.queryByRole('link', { name: 'configuração' })).toBeNull();
  });
});
