import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, within } from '@testing-library/react';
import { StandupDialog } from '@/components/jira/StandupDialog';
import type { StandupSource } from '@/lib/standup';
import type { JiraItem } from '@/lib/types';

function issue(over: Partial<JiraItem>): JiraItem {
  return {
    key: 'A-1',
    summary: 'Resumo',
    status: 'Em andamento',
    statusCategory: 'indeterminate',
    project: 'A',
    url: 'https://example/A-1',
    parent: null,
    role: 'assignee',
    awaitingApproval: false,
    kind: 'História',
    subtask: false,
    hierarchyLevel: 0,
    updatedAt: new Date(2026, 9, 21, 8).toISOString(),
    dueDate: '',
    priority: null,
    flag: 'none',
    ...over,
  };
}

const source: StandupSource = {
  open: [issue({ key: 'A-2', summary: 'Andando' }), issue({ key: 'A-3', summary: 'Travada', flag: 'impediment' })],
  delivered: [],
  approved: [],
  myPulls: [],
};

const writeText = vi.fn<(text: string) => Promise<void>>();

beforeEach(() => {
  vi.useFakeTimers({ toFake: ['Date'] });
  vi.setSystemTime(new Date(2026, 9, 21, 9, 30));
  writeText.mockReset().mockResolvedValue(undefined);
  Object.defineProperty(navigator, 'clipboard', { value: { writeText }, configurable: true });
});

afterEach(() => {
  cleanup();
  vi.useRealTimers();
});

function openDialog() {
  render(<StandupDialog source={source} />);
  fireEvent.click(screen.getByRole('button', { name: 'Resumo para a daily' }));
  return screen.getByRole('dialog', { name: 'Resumo para a daily' });
}

describe('StandupDialog', () => {
  it('shows the summary of yesterday, today and blockers', () => {
    const dialog = openDialog();
    expect(within(dialog).getByRole('textbox', { name: 'texto do resumo' })).toHaveValue(
      'Ontem\n- Nada entregue\n\nHoje\n- A-2 — Andando\n\nBloqueios\n- A-3 — Travada',
    );
  });

  it('copies the summary and says it was copied', async () => {
    const dialog = openDialog();
    fireEvent.click(within(dialog).getByRole('button', { name: 'Copiar' }));

    expect(await within(dialog).findByRole('button', { name: 'Copiado' })).toBeInTheDocument();
    expect(writeText).toHaveBeenCalledWith(
      'Ontem\n- Nada entregue\n\nHoje\n- A-2 — Andando\n\nBloqueios\n- A-3 — Travada',
    );
  });

  it('tells how to copy by hand when the browser refuses the clipboard', async () => {
    writeText.mockRejectedValue(new Error('denied'));
    const dialog = openDialog();
    fireEvent.click(within(dialog).getByRole('button', { name: 'Copiar' }));

    expect(await within(dialog).findByRole('alert')).toHaveTextContent('Ctrl+C');
    expect(within(dialog).getByRole('button', { name: 'Copiar' })).toBeInTheDocument();
  });

  it('starts over without the copied state when reopened', async () => {
    const dialog = openDialog();
    fireEvent.click(within(dialog).getByRole('button', { name: 'Copiar' }));
    await within(dialog).findByRole('button', { name: 'Copiado' });

    fireEvent.click(within(dialog).getByRole('button', { name: 'Close' }));
    fireEvent.click(screen.getByRole('button', { name: 'Resumo para a daily' }));

    const reopened = screen.getByRole('dialog', { name: 'Resumo para a daily' });
    expect(within(reopened).getByRole('button', { name: 'Copiar' })).toBeInTheDocument();
  });

  it('switches to the weekly summary inside the same dialog', () => {
    const dialog = openDialog();
    fireEvent.click(within(dialog).getByRole('button', { name: 'Semanal' }));

    expect(within(dialog).getByRole('button', { name: 'Semanal' })).toHaveAttribute('aria-pressed', 'true');
    expect(within(dialog).getByRole('textbox', { name: 'texto do resumo' })).toHaveValue(
      'Entregue na semana\n- Nada entregue\n\nPRs abertos na semana\n- Nenhum\n\nBloqueios\n- A-3 — Travada',
    );
  });

  it('copies the weekly text once switched', async () => {
    const dialog = openDialog();
    fireEvent.click(within(dialog).getByRole('button', { name: 'Semanal' }));
    fireEvent.click(within(dialog).getByRole('button', { name: 'Copiar' }));

    await within(dialog).findByRole('button', { name: 'Copiado' });
    expect(writeText).toHaveBeenCalledWith(
      'Entregue na semana\n- Nada entregue\n\nPRs abertos na semana\n- Nenhum\n\nBloqueios\n- A-3 — Travada',
    );
  });

  it('opens on the daily summary again after the weekly one', () => {
    const dialog = openDialog();
    fireEvent.click(within(dialog).getByRole('button', { name: 'Semanal' }));
    fireEvent.click(within(dialog).getByRole('button', { name: 'Close' }));
    fireEvent.click(screen.getByRole('button', { name: 'Resumo para a daily' }));

    const reopened = screen.getByRole('dialog', { name: 'Resumo para a daily' });
    expect(within(reopened).getByRole('button', { name: 'Diário' })).toHaveAttribute('aria-pressed', 'true');
    expect(within(reopened).getByRole('textbox', { name: 'texto do resumo' })).toHaveValue(
      'Ontem\n- Nada entregue\n\nHoje\n- A-2 — Andando\n\nBloqueios\n- A-3 — Travada',
    );
  });
});
