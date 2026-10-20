'use client';

import { useCallback, useEffect, useState } from 'react';
import { Button } from '@/components/ui/button';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { RELEASES, loadLastSeen, markSeen, unseenReleases, type Release } from '@/lib/changelog';

export interface Changelog {
  shown: Release[];
  showLatest: () => void;
  dismiss: () => void;
}

export function useChangelog(releases: Release[] = RELEASES): Changelog {
  const [shown, setShown] = useState<Release[]>([]);

  // In an effect so the server render never reaches for localStorage.
  useEffect(() => {
    setShown(unseenReleases(loadLastSeen(), releases));
  }, [releases]);

  const showLatest = useCallback(() => setShown(releases.slice(0, 1)), [releases]);

  const dismiss = useCallback(() => {
    if (releases[0]) markSeen(releases[0].id);
    setShown([]);
  }, [releases]);

  return { shown, showLatest, dismiss };
}

function displayDate(date: string): string {
  const [year, month, day] = date.split('-');
  return `${day}/${month}/${year}`;
}

/** Any way out counts as seen: showing it again on every load would be nagging. */
export function ChangelogDialog({ shown, dismiss }: Pick<Changelog, 'shown' | 'dismiss'>) {
  return (
    <Dialog open={shown.length > 0} onOpenChange={(open) => !open && dismiss()}>
      <DialogContent showCloseButton className="motion-reduce:animate-none">
        <DialogHeader>
          <DialogTitle>Novidades</DialogTitle>
          <DialogDescription className="text-ink-dim">
            O que mudou no daily-web desde a sua última visita.
          </DialogDescription>
        </DialogHeader>
        <ul className="-mx-1 flex max-h-[60vh] flex-col gap-5 overflow-y-auto px-1">
          {shown.map((release) => (
            <li key={release.id} className="flex flex-col gap-2">
              <div className="flex flex-col gap-0.5">
                <h3 className="font-semibold">{release.title}</h3>
                <time dateTime={release.date} className="type-caption text-ink-dim">
                  {displayDate(release.date)}
                </time>
              </div>
              <ul className="flex flex-col gap-2 text-sm">
                {release.items.map((item) => (
                  <li key={item.title}>
                    <span className="font-medium">{item.title}</span>
                    <span className="text-ink-mid"> — {item.detail}</span>
                  </li>
                ))}
              </ul>
            </li>
          ))}
        </ul>
        <DialogFooter>
          <Button onClick={dismiss}>Entendi</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
