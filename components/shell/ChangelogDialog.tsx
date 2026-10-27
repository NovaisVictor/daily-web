'use client';

import { useCallback, useEffect, useState } from 'react';
import { PartyPopper, Rocket, Sparkles, Zap, type LucideIcon } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Dialog, DialogContent, DialogDescription, DialogTitle } from '@/components/ui/dialog';
import { cn } from '@/lib/utils';
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

// The centre card leads, the other two fan out behind it — the same order the release lists them.
// The side cards align their content to the outer edge so it stays readable where the centre
// card covers them.
const HERO_CARDS: { icon: LucideIcon; className: string }[] = [
  { icon: Rocket, className: 'left-1/2 z-10 -translate-x-1/2 scale-105 items-start' },
  { icon: Sparkles, className: 'left-0 translate-y-3 -rotate-6 items-start' },
  { icon: Zap, className: 'right-0 translate-y-3 rotate-6 items-end text-right' },
];

/** Decorative: the same titles are in the list below, so it is hidden from assistive tech. */
function Hero({ release }: { release: Release }) {
  return (
    <div
      aria-hidden
      className="relative flex h-48 items-center justify-center overflow-hidden bg-[radial-gradient(circle_at_15%_25%,color-mix(in_oklab,var(--brand)_22%,transparent),transparent_60%),radial-gradient(circle_at_88%_90%,color-mix(in_oklab,var(--signal-warning)_30%,transparent),transparent_55%)]"
    >
      <div className="relative h-24 w-[26rem] max-w-full">
        {HERO_CARDS.slice(0, release.items.length).map(({ icon: Icon, className }, i) => (
          <div
            key={release.items[i].title}
            className={cn(
              'absolute top-0 flex h-24 w-40 flex-col justify-between gap-2 rounded-2xl border bg-background p-3 shadow-e3',
              // The card under the pointer lifts above its neighbours, which is what reveals the
              // part of its text the centre card covers.
              'transition-[scale,box-shadow] duration-200 ease-brand hover:z-20 hover:scale-110 hover:shadow-e4 motion-reduce:transition-none',
              className,
            )}
          >
            <span className="flex size-8 items-center justify-center rounded-xl bg-brand-tint text-brand">
              <Icon className="size-4" />
            </span>
            <span className="line-clamp-2 text-xs leading-snug font-medium text-ink">
              {release.items[i].title}
            </span>
          </div>
        ))}
        <PartyPopper className="absolute -top-8 left-1 z-20 size-9 -rotate-12 text-brand" />
      </div>
    </div>
  );
}

function ReleaseItems({ release }: { release: Release }) {
  return (
    <ul className="flex flex-col gap-2 text-sm">
      {release.items.map((item) => (
        <li key={item.title}>
          <span className="font-medium">{item.title}</span>
          <span className="text-ink-mid"> — {item.detail}</span>
        </li>
      ))}
    </ul>
  );
}

/** Any way out counts as seen: showing it again on every load would be nagging. */
export function ChangelogDialog({ shown, dismiss }: Pick<Changelog, 'shown' | 'dismiss'>) {
  const [latest, ...older] = shown;

  return (
    <Dialog open={shown.length > 0} onOpenChange={(open) => !open && dismiss()}>
      <DialogContent
        showCloseButton
        className="gap-0 overflow-hidden p-0 motion-reduce:animate-none sm:max-w-md"
      >
        {latest && <Hero release={latest} />}
        <div className="flex flex-col items-center gap-4 px-8 pt-6 pb-8 text-center">
          <DialogTitle className="flex items-center gap-1.5 rounded-full bg-warning-tint px-3 py-1 text-xs font-semibold">
            <Sparkles className="size-3.5" aria-hidden />
            Novidades
          </DialogTitle>
          {latest && (
            <div className="flex flex-col items-center gap-1.5">
              <h3 className="text-2xl font-semibold tracking-tight text-balance">{latest.title}</h3>
              <time dateTime={latest.date} className="type-caption text-ink-dim">
                {displayDate(latest.date)}
              </time>
            </div>
          )}
          <DialogDescription className="text-ink-dim">
            O que mudou no daily-web desde a sua última visita.
          </DialogDescription>
          <div className="-mx-2 flex max-h-[28vh] w-full flex-col gap-5 overflow-y-auto px-2 pb-4 text-left [mask-image:linear-gradient(to_bottom,black_calc(100%-1.5rem),transparent)]">
            {latest && <ReleaseItems release={latest} />}
            {older.map((release) => (
              <section key={release.id} className="flex flex-col gap-2">
                <div className="flex items-baseline justify-between gap-3">
                  <h4 className="font-semibold">{release.title}</h4>
                  <time dateTime={release.date} className="type-caption text-ink-dim">
                    {displayDate(release.date)}
                  </time>
                </div>
                <ReleaseItems release={release} />
              </section>
            ))}
          </div>
          <Button
            onClick={dismiss}
            className="mt-2 rounded-full bg-ink bg-none px-8 text-background shadow-none hover:bg-ink/90"
          >
            Continuar
          </Button>
        </div>
      </DialogContent>
    </Dialog>
  );
}
