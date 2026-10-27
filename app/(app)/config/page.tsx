import { cookies } from 'next/headers';
import { UsersPanel } from '@/components/UsersPanel';
import { LayoutPanel } from '@/components/LayoutPanel';
import { AppearancePanel } from '@/components/AppearancePanel';
import { PageHeader } from '@/components/data/PageHeader';
import {
  BACKDROP_COOKIE,
  DENSITY_COOKIE,
  THEME_COOKIE,
  parseBackdrop,
  parseDensity,
  parseTheme,
} from '@/lib/theme';

/**
 * No back link and no breadcrumb: the shell's sidebar is the way back, and it is
 * on screen the whole time.
 *
 * Two columns because the topics are independent, not because the viewport is
 * wide — the grid collapses to one below lg.
 */
export default async function ConfigPage() {
  const jar = await cookies();

  return (
    <div className="flex flex-col gap-4">
      <PageHeader
        title="Configuração"
        description="Ajuste a aparência, a disposição dos painéis e quem tem acesso."
      />

      <div className="grid items-start gap-4 lg:grid-cols-[minmax(0,1.4fr)_minmax(0,1fr)]">
        <AppearancePanel
          initialTheme={parseTheme(jar.get(THEME_COOKIE)?.value)}
          initialDensity={parseDensity(jar.get(DENSITY_COOKIE)?.value)}
          initialBackdrop={parseBackdrop(jar.get(BACKDROP_COOKIE)?.value)}
        />
        <div className="flex flex-col gap-4">
          <LayoutPanel />
          <UsersPanel />
        </div>
      </div>
    </div>
  );
}
