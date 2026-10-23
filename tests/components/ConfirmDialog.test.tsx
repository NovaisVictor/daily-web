import { afterEach, describe, expect, it } from 'vitest';
import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { useConfirm } from '@/components/data/ConfirmDialog';

afterEach(cleanup);

function Harness() {
  const { confirm, dialog } = useConfirm();
  return (
    <>
      <button type="button" onClick={() => void confirm({ title: 'Apagar a nota?', destructive: true })}>
        Apagar
      </button>
      {dialog}
    </>
  );
}

describe('useConfirm', () => {
  // With no DialogTrigger, Radix sent focus to <body> on close; opened from
  // inside another dialog, that left the keyboard outside the form.
  it('returns focus to the element that asked once the answer is given', async () => {
    render(<Harness />);
    const apagar = screen.getByRole('button', { name: 'Apagar' });
    apagar.focus();
    fireEvent.click(apagar);
    fireEvent.click(await screen.findByRole('button', { name: /Cancelar/ }));
    await waitFor(() => expect(apagar).toHaveFocus());
  });
});
