import {
  CalendarDays,
  GitPullRequest,
  Hash,
  ListChecks,
  Mail,
  SquareKanban,
  StickyNote,
  type LucideIcon,
} from 'lucide-react';
import type { ModuleId } from '@/lib/modules';
import { cn } from '@/lib/utils';

/**
 * Brand artwork per module, served from public/tools. A module without a file
 * falls back to a generic glyph, so a missing logo never leaves an empty tile.
 */
const TOOL_LOGOS: Partial<Record<ModuleId, string>> = {
  email: '/tools/email.png',
  agenda: '/tools/agenda.png',
  jira: '/tools/jira.png',
  pulls: '/tools/pulls.png',
  tasks: '/tools/tasks.png',
  notes: '/tools/notes.png',
  slack: '/tools/slack.png',
};

const FALLBACK_ICONS: Record<ModuleId, LucideIcon> = {
  email: Mail,
  agenda: CalendarDays,
  jira: SquareKanban,
  pulls: GitPullRequest,
  tasks: ListChecks,
  notes: StickyNote,
  slack: Hash,
};

export function ToolLogo({ moduleId, className }: { moduleId: ModuleId; className?: string }) {
  const src = TOOL_LOGOS[moduleId];
  if (src) {
    // Decorative: the module name is always printed next to it.
    return <img src={src} alt="" className={cn('size-12 shrink-0 object-contain', className)} />;
  }

  const Icon = FALLBACK_ICONS[moduleId];
  return (
    <span
      aria-hidden
      className={cn(
        'flex size-12 shrink-0 items-center justify-center rounded-xl bg-brand-tint text-brand',
        className,
      )}
    >
      <Icon className="size-6" />
    </span>
  );
}
