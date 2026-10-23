'use client';

import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { ChevronDown, Monitor, Moon, Sun } from 'lucide-react';
import { Button } from '@/components/ui/button';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuLabel,
  DropdownMenuItem,
  DropdownMenuRadioGroup,
  DropdownMenuRadioItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import {
  applyBackdrop,
  applyDensity,
  applyTheme,
  parseBackdrop,
  type Backdrop,
  type Density,
  type ThemePreference,
} from '@/lib/theme';

const THEME_ICON = { system: Monitor, light: Sun, dark: Moon } as const;

const THEME_LABEL: Record<ThemePreference, string> = {
  system: 'Sistema',
  light: 'Claro',
  dark: 'Escuro',
};

const DENSITY_LABEL: Record<Density, string> = {
  comfortable: 'Confortável',
  compact: 'Compacto',
};

const BACKDROP_LABEL: Record<Backdrop, string> = {
  mesh: 'Gradiente',
  catppuccin: 'Catppuccin',
  // Dracula only remaps the dark theme, so the hint keeps a light-theme pick from looking broken.
  dracula: 'Dracula (só no tema escuro)',
};

interface Props {
  initialTheme: ThemePreference;
  initialDensity: Density;
  initialBackdrop: Backdrop;
  username: string | null;
  /** On the collapsed rail there is no room for a name: the trigger becomes the
   *  theme icon alone, with the name still reachable inside the menu. */
  collapsed?: boolean;
  onShowChangelog: () => void;
}

/**
 * Theme and density both live on the root element, which the server already
 * stamped. These handlers call the applier before the setter, so the element and
 * the state stay in step no matter which surface changed it.
 */
export function AccountMenu({
  initialTheme,
  initialDensity,
  initialBackdrop,
  username,
  collapsed = false,
  onShowChangelog,
}: Props) {
  const router = useRouter();
  const [theme, setTheme] = useState<ThemePreference>(initialTheme);
  const [density, setDensity] = useState<Density>(initialDensity);
  const [backdrop, setBackdrop] = useState<Backdrop>(initialBackdrop);
  const [leaving, setLeaving] = useState(false);

  // The root element is the source of truth; a cookie cleared in another tab
  // would otherwise leave this menu showing a choice that is no longer applied.
  useEffect(() => {
    const root = document.documentElement;
    if (root.classList.contains('dark')) setTheme('dark');
    else if (root.classList.contains('light')) setTheme('light');
    else setTheme('system');
    setDensity(root.dataset.density === 'compact' ? 'compact' : 'comfortable');
    setBackdrop(parseBackdrop(root.dataset.backdrop));
  }, []);

  const chooseTheme = (pref: ThemePreference) => {
    applyTheme(pref);
    setTheme(pref);
  };

  const chooseDensity = (d: Density) => {
    applyDensity(d);
    setDensity(d);
  };

  const chooseBackdrop = (b: Backdrop) => {
    applyBackdrop(b);
    setBackdrop(b);
  };

  const signOut = async () => {
    setLeaving(true);
    await fetch('/api/logout', { method: 'POST' }).catch(() => {});
    router.push('/login');
  };

  const ThemeIcon = THEME_ICON[theme];

  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button
          variant="ghost"
          size={collapsed ? 'icon-sm' : 'sm'}
          aria-label={collapsed ? (username ?? 'Conta') : undefined}
          className={collapsed ? 'mx-auto' : 'w-full justify-start gap-2 px-2'}
        >
          <ThemeIcon className="size-4 shrink-0 text-ink-dim" />
          {!collapsed && (
            <>
              <span className="min-w-0 flex-1 truncate text-left font-normal">
                {username ?? 'Conta'}
              </span>
              <ChevronDown className="size-4 shrink-0 text-ink-dim" />
            </>
          )}
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="start" side="top" className="min-w-56">
        <DropdownMenuLabel>{username ?? 'Conta'}</DropdownMenuLabel>
        <DropdownMenuSeparator />

        <DropdownMenuLabel className="type-caption text-ink-dim">Tema</DropdownMenuLabel>
        <DropdownMenuRadioGroup
          value={theme}
          onValueChange={(v) => chooseTheme(v as ThemePreference)}
        >
          {(['system', 'light', 'dark'] as const).map((value) => (
            <DropdownMenuRadioItem key={value} value={value}>
              {THEME_LABEL[value]}
            </DropdownMenuRadioItem>
          ))}
        </DropdownMenuRadioGroup>
        <DropdownMenuSeparator />

        <DropdownMenuLabel className="type-caption text-ink-dim">Densidade</DropdownMenuLabel>
        <DropdownMenuRadioGroup value={density} onValueChange={(v) => chooseDensity(v as Density)}>
          {(['comfortable', 'compact'] as const).map((value) => (
            <DropdownMenuRadioItem key={value} value={value}>
              {DENSITY_LABEL[value]}
            </DropdownMenuRadioItem>
          ))}
        </DropdownMenuRadioGroup>
        <DropdownMenuSeparator />

        <DropdownMenuLabel className="type-caption text-ink-dim">Fundo</DropdownMenuLabel>
        <DropdownMenuRadioGroup
          value={backdrop}
          onValueChange={(v) => chooseBackdrop(v as Backdrop)}
        >
          {(['mesh', 'catppuccin', 'dracula'] as const).map((value) => (
            <DropdownMenuRadioItem key={value} value={value}>
              {BACKDROP_LABEL[value]}
            </DropdownMenuRadioItem>
          ))}
        </DropdownMenuRadioGroup>
        <DropdownMenuSeparator />

        <DropdownMenuItem onSelect={onShowChangelog}>Novidades</DropdownMenuItem>
        <DropdownMenuSeparator />

        <DropdownMenuItem disabled={leaving} onSelect={() => void signOut()}>
          {leaving ? 'Saindo…' : 'Sair'}
        </DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
