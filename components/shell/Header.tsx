'use client';

import { useState } from 'react';
import { usePathname, useRouter } from 'next/navigation';
import Link from 'next/link';
import { Bot, LogOut, Search, Settings2, Sparkles, User as UserIcon } from 'lucide-react';
import { IconAction } from '@/components/data/IconAction';
import { Avatar, AvatarFallback, AvatarImage } from '@/components/ui/avatar';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import { focusRing, isActivePath } from '@/lib/theme';
import { cn } from '@/lib/utils';
import { HeaderNotifications } from './HeaderNotifications';
import { NAV_ITEMS } from './nav-items';

// The rest (Configuração, Acesso dos agentes) is reached from the avatar menu and from
// the "Conectar agente" item of the avatar menu.
const HEADER_NAV_ITEMS = NAV_ITEMS.filter((item) => item.placement === 'header');

interface Props {
  className?: string;
  username?: string | null;
  onOpenPalette?: () => void;
  avatarSrc?: string | null;
  onShowChangelog: () => void;
}

/**
 * Logo on the left, search + notifications + avatar on the right. The search
 * button keeps a 40px touch target even though its glyph is 20px — the two
 * sizes are independent, per the design spec, so the hit area stays
 * thumb-friendly without inflating the icon.
 */
export function Header({
  className,
  username,
  onOpenPalette,
  avatarSrc: avatarSrcProp,
  onShowChangelog,
}: Props) {
  const router = useRouter();
  const pathname = usePathname() ?? '/';
  const avatarSrc = avatarSrcProp ?? undefined;
  const [leaving, setLeaving] = useState(false);

  const displayName = username ?? 'Conta';
  const fallback = displayName.slice(0, 1).toUpperCase();

  const signOut = async () => {
    setLeaving(true);
    await fetch('/api/logout', { method: 'POST' }).catch(() => {});
    router.push('/login');
  };

  return (
    <header
      className={cn(
        'flex shrink-0 items-center justify-between rounded-2xl border bg-glass px-4 py-3 backdrop-blur-xl backdrop-saturate-150',
        className,
      )}
    >
      {/* The logo and the actions share the free space equally (flex-1 basis-0),
        which is what keeps the nav in the true centre rather than in the
        middle of whatever the two sides leave over. */}
      <div className="flex min-w-0 flex-1 basis-0 items-center">
        <Link href="/" className={cn('flex min-w-0 items-center gap-3 rounded-full', focusRing)}>
          <span className="flex size-10 shrink-0 items-center justify-center overflow-hidden rounded-full border bg-glass-strong shadow-e1">
            <span className="size-2 rounded-full bg-brand" aria-hidden />
          </span>
          <span className="truncate text-[0.975rem] font-semibold tracking-tight">daily-web</span>
        </Link>
      </div>

      {/* Below lg only the glyph fits; the label stays reachable through
        aria-label and the native title. */}
      <nav aria-label="Principal" className="flex shrink-0 items-center gap-1">
        {HEADER_NAV_ITEMS.map((item) => {
          const isActive = isActivePath(pathname, item.href);
          const Icon = item.icon;
          return (
            <Link
              key={item.href}
              href={item.href}
              aria-label={item.label}
              aria-current={isActive ? 'page' : undefined}
              title={item.label}
              className={cn(
                'flex shrink-0 items-center gap-2 rounded-full px-3 py-2 text-sm transition-colors duration-100 ease-brand motion-reduce:transition-none',
                focusRing,
                isActive
                  ? 'bg-glass-strong text-ink shadow-e1'
                  : 'text-ink-mid hover:bg-glass-line hover:text-ink',
              )}
            >
              <Icon className="size-[18px] shrink-0" />
              <span className="hidden lg:inline">{item.label}</span>
            </Link>
          );
        })}
      </nav>

      <div className="flex min-w-0 flex-1 basis-0 items-center justify-end gap-2">
        <IconAction
          label="Buscar"
          variant="outline"
          size="icon"
          className="size-10 border-transparent"
          onClick={onOpenPalette}
          icon={<Search className="size-5" />}
        />

        <HeaderNotifications />

        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <button
              type="button"
              aria-label={displayName}
              className={cn('rounded-full transition-opacity hover:opacity-80', focusRing)}
            >
              <Avatar className="size-10">
                <AvatarImage src={avatarSrc} alt={displayName} />
                <AvatarFallback>{fallback}</AvatarFallback>
              </Avatar>
            </button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end" className="flex flex-col gap-1 py-0">
            <DropdownMenuItem asChild>
              <Link href="/perfil">
                <UserIcon className="size-4" />
                Perfil
              </Link>
            </DropdownMenuItem>
            <DropdownMenuItem asChild>
              <Link href="/access">
                <Bot className="size-4" />
                Conectar agente
              </Link>
            </DropdownMenuItem>
            <DropdownMenuItem asChild>
              <Link href="/config">
                <Settings2 className="size-4" />
                Configurações
              </Link>
            </DropdownMenuItem>
            <DropdownMenuItem onSelect={onShowChangelog}>
              <Sparkles className="size-4" />
              Novidades
            </DropdownMenuItem>
            <DropdownMenuSeparator className="my-0 bg-line" />
            <DropdownMenuItem disabled={leaving} onSelect={() => void signOut()}>
              <LogOut className="size-4" />
              {leaving ? 'Saindo…' : 'Sair'}
            </DropdownMenuItem>
          </DropdownMenuContent>
        </DropdownMenu>
      </div>
    </header>
  );
}
