import { toast } from 'sonner';
import type { AppearancePatch } from './theme';

async function saveAppearance(patch: AppearancePatch): Promise<void> {
  const res = await fetch('/api/preferences', {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ appearance: patch }),
  });
  if (!res.ok) {
    const data = await res.json().catch(() => ({}));
    throw new Error(data.error ?? 'falha ao guardar');
  }
}

/**
 * The cookie and the root attribute make the choice show at once; this is what makes it the
 * account's, so it follows the person to another browser. A failure is reported, not swallowed:
 * the choice then holds only for this browser, and the person should know.
 */
export function persistAppearance(patch: AppearancePatch): void {
  saveAppearance(patch).catch((error: unknown) => {
    const reason = error instanceof Error ? error.message : String(error);
    toast.error(`Não deu para guardar na sua conta (${reason}). Vale só neste navegador.`);
  });
}
