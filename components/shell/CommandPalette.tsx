'use client';

import { useEffect } from 'react';
import { useRouter } from 'next/navigation';
import { KeyRound, LogOut, Settings2, User as UserIcon } from 'lucide-react';
import { Dialog, DialogContent, DialogTitle } from '@/components/ui/dialog';
import {
  Command,
  CommandEmpty,
  CommandGroup,
  CommandInput,
  CommandItem,
  CommandList,
} from '@/components/ui/command';
import { NAV_ITEMS } from './nav-items';
import {
  applyBackdrop,
  applyDensity,
  applyTheme,
  type Backdrop,
  type Density,
  type ThemePreference,
} from '@/lib/theme';

const THEMES: { value: ThemePreference; label: string }[] = [
  { value: 'system', label: 'Tema do sistema' },
  { value: 'light', label: 'Tema claro' },
  { value: 'dark', label: 'Tema escuro' },
];

const DENSITIES: { value: Density; label: string }[] = [
  { value: 'comfortable', label: 'Densidade confortável' },
  { value: 'compact', label: 'Densidade compacta' },
];

const BACKDROPS: { value: Backdrop; label: string }[] = [
  { value: 'mesh', label: 'Fundo gradiente' },
  { value: 'catppuccin', label: 'Fundo Catppuccin' },
  { value: 'wezterm', label: 'Fundo WezTerm' },
];

/** Coisas que não são uma tela própria, mas ainda devem ser achadas pela
 *  busca — cada uma leva a onde a ação de fato mora. */
const ACTIONS: { key: string; value: string; label: string; icon: typeof UserIcon; href: string }[] = [
  { key: 'perfil', value: 'Perfil', label: 'Perfil', icon: UserIcon, href: '/perfil' },
  {
    key: 'senha',
    value: 'Trocar senha',
    label: 'Trocar senha',
    icon: KeyRound,
    href: '/perfil',
  },
  {
    key: 'foto',
    value: 'Alterar foto de perfil',
    label: 'Alterar foto de perfil',
    icon: UserIcon,
    href: '/perfil',
  },
  {
    key: 'aparencia',
    value: 'Aparência tema densidade fundo',
    label: 'Aparência',
    icon: Settings2,
    href: '/config',
  },
];

export function CommandPalette({
  open,
  onOpenChange,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}) {
  const router = useRouter();

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      // metaKey || ctrlKey covers both platforms with one key; preventDefault stops
      // Firefox stealing it for the address bar; toggling beats open-only.
      if (e.key.toLowerCase() === 'k' && (e.metaKey || e.ctrlKey)) {
        e.preventDefault();
        onOpenChange(!open);
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [open, onOpenChange]);

  /** Every selection closes the palette first, then acts. */
  const run = (action: () => void) => {
    onOpenChange(false);
    action();
  };

  const signOut = async () => {
    await fetch('/api/logout', { method: 'POST' }).catch(() => {});
    router.push('/login');
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent
        showCloseButton={false}
        className="top-[12vh] max-w-2xl translate-y-0 gap-0 overflow-hidden p-0 shadow-e5 sm:max-w-2xl"
      >
        <DialogTitle className="sr-only">Buscar</DialogTitle>
        <Command className="bg-transparent [&_[cmdk-group-heading]]:type-caption [&_[cmdk-group-heading]]:px-3 [&_[cmdk-group-heading]]:py-2 [&_[cmdk-group-heading]]:text-ink-dim">
          <CommandInput placeholder="Buscar telas e ajustes…" />
          <CommandList className="max-h-[60vh]">
            <CommandEmpty className="py-6 text-center text-sm">Nada encontrado.</CommandEmpty>
            <CommandGroup heading="Ir para">
              {NAV_ITEMS.map((item) => (
                // cmdk needs unique values; prefixing with the group also makes the
                // group name itself searchable.
                <CommandItem
                  key={item.href}
                  value={`Ir para ${item.label}`}
                  onSelect={() => run(() => router.push(item.href))}
                >
                  <item.icon className="size-4" />
                  {item.label}
                </CommandItem>
              ))}
            </CommandGroup>
            <CommandGroup heading="Tema">
              {THEMES.map((t) => (
                <CommandItem
                  key={t.value}
                  value={`Tema ${t.label}`}
                  onSelect={() => run(() => applyTheme(t.value))}
                >
                  {t.label}
                </CommandItem>
              ))}
            </CommandGroup>
            <CommandGroup heading="Densidade">
              {DENSITIES.map((d) => (
                <CommandItem
                  key={d.value}
                  value={`Densidade ${d.label}`}
                  onSelect={() => run(() => applyDensity(d.value))}
                >
                  {d.label}
                </CommandItem>
              ))}
            </CommandGroup>
            <CommandGroup heading="Fundo">
              {BACKDROPS.map((b) => (
                <CommandItem
                  key={b.value}
                  value={b.label}
                  onSelect={() => run(() => applyBackdrop(b.value))}
                >
                  {b.label}
                </CommandItem>
              ))}
            </CommandGroup>
            <CommandGroup heading="Conta">
              {ACTIONS.map((action) => (
                <CommandItem
                  key={action.key}
                  value={action.value}
                  onSelect={() => run(() => router.push(action.href))}
                >
                  <action.icon className="size-4" />
                  {action.label}
                </CommandItem>
              ))}
              <CommandItem value="Sair" onSelect={() => run(() => void signOut())}>
                <LogOut className="size-4" />
                Sair
              </CommandItem>
            </CommandGroup>
          </CommandList>
        </Command>
      </DialogContent>
    </Dialog>
  );
}
