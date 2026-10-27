import { cookies } from 'next/headers';
import { UsersPanel } from '@/components/UsersPanel';
import { LayoutPanel } from '@/components/LayoutPanel';
import { AppearancePanel } from '@/components/AppearancePanel';
import { PageHeader } from '@/components/data/PageHeader';
import { getCurrentUser } from '@/lib/auth/currentUser';
import { resolveAppearance } from '@/lib/appearance';

/**
 * No back link and no breadcrumb: the shell's sidebar is the way back, and it is
 * on screen the whole time.
 *
 * Two columns because the topics are independent, not because the viewport is
 * wide — the grid collapses to one below lg.
 */
export default async function ConfigPage() {
  const jar = await cookies();
  const user = await getCurrentUser();
  const appearance = resolveAppearance((name) => jar.get(name)?.value, user?.id ?? null);

  return (
    <div className="flex flex-col gap-4">
      <PageHeader
        title="Configuração"
        description="Ajuste a aparência, a disposição dos painéis e quem tem acesso."
      />

      <div className="grid items-start gap-4 lg:grid-cols-[minmax(0,1.4fr)_minmax(0,1fr)]">
        <AppearancePanel
          initialTheme={appearance.theme}
          initialDensity={appearance.density}
          initialBackdrop={appearance.backdrop}
          initialWidth={appearance.width}
        />
        <div className="flex flex-col gap-4">
          <LayoutPanel />
          <UsersPanel />
        </div>
      </div>
    </div>
  );
}
