import type { ReactNode } from 'react';

interface Props {
  title: ReactNode;
  description?: ReactNode;
  icon?: ReactNode;
  action?: ReactNode;
}

/**
 * An invitation to act in the interface's voice, not a shrug. The zero state of a
 * list is a first impression, so it points at the primary action.
 *
 * A dashed, translucent well, the same as an empty board lane: an empty box is a
 * hole, not a panel. It used to sit on the opaque recessed surface, which in the
 * dark theme read as a black slab inside the glass cards.
 */
export function EmptyState({ title, description, icon, action }: Props) {
  return (
    <div className="flex flex-col items-center justify-center gap-4 rounded-xl border border-dashed border-line-strong bg-muted/35 py-16 text-center">
      {icon && <div className="text-ink-dim [&_svg]:size-8">{icon}</div>}
      <div className="grid gap-1.5">
        <h2 className="type-subhead">{title}</h2>
        {description && <p className="max-w-sm text-sm text-ink-mid">{description}</p>}
      </div>
      {action}
    </div>
  );
}
