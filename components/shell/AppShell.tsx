'use client';

import { Fragment, useState, type ReactNode } from 'react';
import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { Menu, Search } from 'lucide-react';
import { Button } from '@/components/ui/button';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import { isActivePath, type Backdrop, type Density, type ThemePreference } from '@/lib/theme';
import { AccountMenu } from './AccountMenu';
import { ChangelogDialog, useChangelog } from './ChangelogDialog';
import { CommandPalette } from './CommandPalette';
import { Header } from './Header';
import { TooltipProvider } from '@/components/ui/tooltip';
import { Toaster } from '@/components/ui/sonner';
import { DashboardStateProvider } from '@/lib/hooks/DashboardStateProvider';
import type { WelcomeKind } from '@/lib/greeting';
import { ShellUserProvider } from './ShellUser';
import { NAV_ITEMS, groupStart } from './nav-items';

/** The page content uses the whole window, unless the person chose the limited width in
 *  Configuração (`data-width` on <html>, see `lib/theme.ts`). The header stays full width. */
const CONTAINER = 'mx-auto w-full in-data-[width=limited]:max-w-[1216px]';

interface Props {
  theme: ThemePreference;
  density: Density;
  backdrop: Backdrop;
  username: string | null;
  avatarUrl: string | null;
  greetingName: string | null;
  welcome: WelcomeKind;
  children: ReactNode;
}

/**
 * The page never scrolls: h-dvh plus overflow-hidden pins the frame to the
 * viewport so the fixed mesh stays still and only the content moves. Nothing here
 * is sticky or fixed — persistence is structural, because the sidebar and the
 * mobile header are flex siblings outside the single scroll container.
 */
export function AppShell({
  theme,
  density,
  backdrop,
  username,
  avatarUrl,
  greetingName,
  welcome,
  children,
}: Props) {
  const pathname = usePathname() ?? '/';
  const [paletteOpen, setPaletteOpen] = useState(false);
  const changelog = useChangelog();

  const active = NAV_ITEMS.find((item) => isActivePath(pathname, item.href));

  return (
    <TooltipProvider delayDuration={200}>
      <DashboardStateProvider>
        <ShellUserProvider value={{ greetingName, welcome }}>
          <div className="flex h-dvh flex-col overflow-hidden p-4">
            <Header
              className="hidden md:flex"
              onOpenPalette={() => setPaletteOpen(true)}
              username={username}
              avatarSrc={avatarUrl}
              onShowChangelog={changelog.showLatest}
            />

            <div className="flex min-h-0 min-w-0 flex-1 flex-col gap-3 overflow-hidden">
              {/* Below md the sidebar is hidden, so this is the only navigation on a
            phone and cannot be left empty. */}
              <header className="flex h-14 shrink-0 items-center gap-2 rounded-2xl border bg-glass px-3 shadow-e2 backdrop-blur-xl md:hidden">
                <DropdownMenu>
                  <DropdownMenuTrigger asChild>
                    <Button variant="ghost" size="icon" aria-label="Abrir navegação">
                      <Menu className="size-4" />
                    </Button>
                  </DropdownMenuTrigger>
                  <DropdownMenuContent align="start" className="max-h-[70vh] overflow-y-auto">
                    {NAV_ITEMS.map((item, i) => (
                      <Fragment key={item.href}>
                        {groupStart(NAV_ITEMS, i) && (
                          <DropdownMenuLabel>{item.group}</DropdownMenuLabel>
                        )}
                        <DropdownMenuItem asChild>
                          <Link href={item.href}>{item.label}</Link>
                        </DropdownMenuItem>
                      </Fragment>
                    ))}
                  </DropdownMenuContent>
                </DropdownMenu>

                <span className="truncate font-semibold tracking-tight">
                  {active?.label ?? 'daily-web'}
                </span>

                <div className="ml-auto flex items-center gap-1">
                  <Button
                    variant="ghost"
                    size="icon"
                    aria-label="Buscar"
                    onClick={() => setPaletteOpen(true)}
                  >
                    <Search className="size-4" />
                  </Button>
                  <div className="w-40">
                    <AccountMenu
                      initialTheme={theme}
                      initialDensity={density}
                      initialBackdrop={backdrop}
                      username={username}
                      onShowChangelog={changelog.showLatest}
                    />
                  </div>
                </div>
              </header>

              <main className="min-h-0 flex-1 overflow-y-auto">
                <div className={`px-1 pt-3 pb-6 md:px-2 md:pt-10 ${CONTAINER}`}>{children}</div>
              </main>
            </div>

            <CommandPalette open={paletteOpen} onOpenChange={setPaletteOpen} />
            <ChangelogDialog shown={changelog.shown} dismiss={changelog.dismiss} />
            {/* `toast()` only queues a message; without a mounted Toaster nothing
            ever renders it, which is how "Bloco de foco criado" went unseen. */}
            <Toaster />
          </div>
        </ShellUserProvider>
      </DashboardStateProvider>
    </TooltipProvider>
  );
}
