import { Columns3, House, KeyRound, Plug, Settings2 } from 'lucide-react';
import type { LucideIcon } from 'lucide-react';

/** Where an item is reachable: in the desktop header, or only from the mobile menu, the palette and the places that link to it. */
export type NavPlacement = 'header' | 'secondary';

export interface NavItem {
  href: string;
  label: string;
  icon: LucideIcon;
  placement: NavPlacement;
  group?: string;
}

/** Flat on purpose: no nesting, no collapsible sections. */
export const NAV_ITEMS: NavItem[] = [
  { href: '/', label: 'Início', icon: House, placement: 'header' },
  { href: '/kanban', label: 'Kanban', icon: Columns3, placement: 'header' },
  { href: '/tools', label: 'Ferramentas', icon: Plug, placement: 'header' },
  {
    href: '/access',
    label: 'Acesso dos agentes',
    icon: KeyRound,
    placement: 'secondary',
    group: 'Ajustes',
  },
  {
    href: '/config',
    label: 'Configuração',
    icon: Settings2,
    placement: 'secondary',
    group: 'Ajustes',
  },
];

/** A group heading appears only at a boundary, never above every item. */
export function groupStart(items: NavItem[], i: number): boolean {
  return !!items[i]?.group && items[i]?.group !== items[i - 1]?.group;
}
