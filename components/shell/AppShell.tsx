'use client';

import { Fragment, useCallback, useEffect, useState, type ReactNode } from 'react';
import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { Menu, PanelLeftClose, PanelLeftOpen, Search } from 'lucide-react';
import { Button } from '@/components/ui/button';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import { cn } from '@/lib/utils';
import {
  focusRing,
  isActivePath,
  persistSidebar,
  type Backdrop,
  type Density,
  type SidebarState,
  type ThemePreference,
} from '@/lib/theme';
import { AccountMenu } from './AccountMenu';
import { ChangelogDialog, useChangelog } from './ChangelogDialog';
import { CommandPalette } from './CommandPalette';
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from '@/components/ui/tooltip';
import { NAV_ITEMS, groupStart } from './nav-items';

interface Props {
  theme: ThemePreference;
  density: Density;
  backdrop: Backdrop;
  sidebar: SidebarState;
  username: string | null;
  children: ReactNode;
}

/**
 * The page never scrolls: h-dvh plus overflow-hidden pins the frame to the
 * viewport so the fixed mesh stays still and only the content moves. Nothing here
 * is sticky or fixed — persistence is structural, because the sidebar and the
 * mobile header are flex siblings outside the single scroll container.
 */
/**
 * Wherever a control shows only its glyph, the label has to be reachable some
 * other way: a tooltip on hover, and an aria-label for anyone not hovering.
 * Pass show={false} where the label is already on screen — a tooltip that
 * repeats a visible label is noise.
 */
function RailTooltip({
  show,
  label,
  children,
}: {
  show: boolean;
  label: string;
  children: ReactNode;
}) {
  if (!show) return <>{children}</>;
  return (
    <Tooltip>
      <TooltipTrigger asChild>{children}</TooltipTrigger>
      <TooltipContent side="right">{label}</TooltipContent>
    </Tooltip>
  );
}

export function AppShell({ theme, density, backdrop, sidebar, username, children }: Props) {
  const pathname = usePathname() ?? '/';
  const [paletteOpen, setPaletteOpen] = useState(false);
  const changelog = useChangelog();
  // Server-rendered from the cookie, so a collapsed rail never expands for one
  // frame on reload.
  const [collapsed, setCollapsed] = useState(sidebar === 'collapsed');

  const toggleSidebar = useCallback(() => {
    setCollapsed((v) => {
      const next = !v;
      persistSidebar(next ? 'collapsed' : 'expanded');
      return next;
    });
  }, []);

  // Cmd/Ctrl+B, the shortcut this gesture carries everywhere else.
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key.toLowerCase() === 'b' && (e.metaKey || e.ctrlKey)) {
        e.preventDefault();
        toggleSidebar();
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [toggleSidebar]);

  const active = NAV_ITEMS.find((item) => isActivePath(pathname, item.href));
  const account = (
    <AccountMenu
      initialTheme={theme}
      initialDensity={density}
      initialBackdrop={backdrop}
      username={username}
      collapsed={collapsed}
      onShowChangelog={changelog.showLatest}
    />
  );

  return (
    <TooltipProvider delayDuration={200}>
      <div className="flex h-dvh gap-2 overflow-hidden p-2">
        <aside
          data-state={collapsed ? 'collapsed' : 'expanded'}
          className={cn(
            'hidden shrink-0 flex-col overflow-hidden rounded-2xl border bg-glass shadow-e3 backdrop-blur-xl backdrop-saturate-150 md:flex',
            'transition-[width] duration-150 ease-brand motion-reduce:transition-none',
            collapsed ? 'w-14' : 'w-60',
          )}
        >
          <div
            className={cn(
              'flex shrink-0 items-center gap-3 pt-5 pb-4',
              collapsed ? 'justify-center px-2' : 'px-5',
            )}
          >
            <span className="flex size-10 shrink-0 items-center justify-center overflow-hidden rounded-full border bg-glass-strong shadow-e1">
              <span className="size-2 rounded-full bg-brand" aria-hidden />
            </span>
            {!collapsed && (
              <span className="truncate text-[0.975rem] font-semibold tracking-tight">
                daily-web
              </span>
            )}
          </div>

          <div className={cn('shrink-0 pb-1', collapsed ? 'px-2' : 'px-3')}>
            <RailTooltip show={collapsed} label="Buscar  ⌘K">
              <button
                type="button"
                aria-label="Buscar"
                onClick={() => setPaletteOpen(true)}
                className={cn(
                  'flex w-full items-center rounded-full border bg-glass-strong text-sm text-ink-dim shadow-e1 transition-colors duration-100 ease-brand hover:text-ink-mid motion-reduce:transition-none',
                  collapsed ? 'justify-center p-2' : 'gap-2 py-2 pr-2 pl-3.5',
                  focusRing,
                )}
              >
                <Search className="size-4 shrink-0" />
                {!collapsed && (
                  <>
                    <span className="min-w-0 flex-1 truncate text-left">Buscar</span>
                    {/* border-line, not the bare border: a bare border gives the white
                      glass seal, and this one wants the real gray hairline. */}
                    <kbd className="type-caption shrink-0 rounded-full border border-line px-1.5 py-0.5 text-ink-dim">
                      ⌘K
                    </kbd>
                  </>
                )}
              </button>
            </RailTooltip>
          </div>

          {/* min-h-0 is load-bearing: without it the flex child takes content height
            and the whole page scrolls again, which unpins the background. */}
          <div className="min-h-0 min-w-0 flex-1 overflow-y-auto">
            {/* No horizontal padding here, so the active band bleeds to the panel
              edge. The padding lives on each item. */}
            <nav className="flex flex-col py-3">
              {NAV_ITEMS.map((item, i) => {
                const isActive = isActivePath(pathname, item.href);
                const Icon = item.icon;
                return (
                  <Fragment key={item.href}>
                    {groupStart(NAV_ITEMS, i) &&
                      (collapsed ? (
                        // No room for a heading on the rail; the hairline keeps the
                        // grouping without pretending to be a label.
                        <span className="mx-3 my-2 h-px shrink-0 bg-line" aria-hidden />
                      ) : (
                        <span className="type-caption px-5 pt-5 pb-1 text-ink-dim first:pt-1">
                          {item.group}
                        </span>
                      ))}
                    <RailTooltip show={collapsed} label={item.label}>
                      <Link
                        href={item.href}
                        aria-current={isActive ? 'page' : undefined}
                        className={cn(
                          'relative flex items-center text-sm transition-colors duration-100 ease-brand motion-reduce:transition-none',
                          collapsed ? 'justify-center py-2.5' : 'gap-3 py-2.5 pr-3 pl-5',
                          focusRing,
                          isActive
                            ? [
                                'bg-[linear-gradient(to_right,var(--brand-tint),transparent_68%)] text-ink',
                                "before:absolute before:inset-y-0 before:left-0 before:w-[3px] before:bg-brand before:content-['']",
                                'dark:before:shadow-[0_0_8px_0_var(--brand)]',
                              ]
                            : 'text-ink-mid hover:bg-glass-line hover:text-ink',
                        )}
                      >
                        <Icon className="size-[18px] shrink-0" />
                        {!collapsed && item.label}
                        {collapsed && <span className="sr-only">{item.label}</span>}
                      </Link>
                    </RailTooltip>
                  </Fragment>
                );
              })}
            </nav>
          </div>

          {/* The only internal border in the sidebar. */}
          <div
            className={cn(
              'flex shrink-0 border-t',
              // Expanded, the two controls share one row: the toggle is an icon,
              // and an icon does not need a row of its own. Collapsed, the rail
              // has no width to share, so they stack.
              collapsed ? 'flex-col gap-1 p-2' : 'items-center gap-1 p-2.5',
            )}
          >
            {!collapsed && <div className="min-w-0 flex-1">{account}</div>}
            {/* The label lives in the tooltip and in aria-label in both states:
                the glyph plus the shortcut is the whole affordance. */}
            <RailTooltip show label={collapsed ? 'Expandir menu  ⌘B' : 'Recolher menu  ⌘B'}>
              <Button
                variant="ghost"
                size="icon-sm"
                onClick={toggleSidebar}
                aria-label={collapsed ? 'Expandir menu lateral' : 'Recolher menu lateral'}
                aria-expanded={!collapsed}
                className={cn('shrink-0', collapsed && 'mx-auto')}
              >
                {collapsed ? (
                  <PanelLeftOpen className="size-4 text-ink-dim" />
                ) : (
                  <PanelLeftClose className="size-4 text-ink-dim" />
                )}
              </Button>
            </RailTooltip>
            {collapsed && account}
          </div>
        </aside>

        <div className="flex min-w-0 flex-1 flex-col gap-3 overflow-hidden">
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
            <div className="w-full px-1 pt-3 pb-6 md:px-2">{children}</div>
          </main>
        </div>

        <CommandPalette open={paletteOpen} onOpenChange={setPaletteOpen} />
        <ChangelogDialog shown={changelog.shown} dismiss={changelog.dismiss} />
      </div>
    </TooltipProvider>
  );
}
