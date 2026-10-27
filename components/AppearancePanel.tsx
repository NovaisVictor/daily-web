'use client';

import { useEffect, useState } from 'react';
import { Monitor, Moon, Sun } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Section } from './ui/Section';
import {
  applyBackdrop,
  applyDensity,
  applyTheme,
  parseBackdrop,
  type Backdrop,
  type Density,
  type ThemePreference,
} from '@/lib/theme';

interface Props {
  initialTheme: ThemePreference;
  initialDensity: Density;
  initialBackdrop: Backdrop;
}

const THEME_OPTIONS: { value: ThemePreference; label: string; icon: typeof Monitor }[] = [
  { value: 'system', label: 'Sistema', icon: Monitor },
  { value: 'light', label: 'Claro', icon: Sun },
  { value: 'dark', label: 'Escuro', icon: Moon },
];

const DENSITY_OPTIONS: { value: Density; label: string }[] = [
  { value: 'comfortable', label: 'Confortável' },
  { value: 'compact', label: 'Compacto' },
];

const BACKDROP_OPTIONS: { value: Backdrop; label: string }[] = [
  { value: 'mesh', label: 'Gradiente' },
  { value: 'catppuccin', label: 'Catppuccin' },
  // Only remaps the dark theme, so the hint keeps a light-theme pick from looking broken.
  { value: 'wezterm', label: 'WezTerm (só no tema escuro)' },
];

/**
 * Moved out of the account dropdown: appearance is a settings screen's job,
 * not something buried behind the avatar.
 */
export function AppearancePanel({ initialTheme, initialDensity, initialBackdrop }: Props) {
  const [theme, setTheme] = useState<ThemePreference>(initialTheme);
  const [density, setDensity] = useState<Density>(initialDensity);
  const [backdrop, setBackdrop] = useState<Backdrop>(initialBackdrop);

  // The root element is the source of truth; a cookie cleared in another tab
  // would otherwise leave this screen showing a choice that is no longer applied.
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

  return (
    <div className="flex flex-col gap-4">
      <Section eyebrow="Tema">
        <div className="flex flex-wrap gap-2">
          {THEME_OPTIONS.map(({ value, label, icon: Icon }) => (
            <Button
              key={value}
              type="button"
              variant={theme === value ? 'default' : 'outline'}
              size="sm"
              onClick={() => chooseTheme(value)}
              aria-pressed={theme === value}
            >
              <Icon className="size-4" />
              {label}
            </Button>
          ))}
        </div>
      </Section>

      <Section eyebrow="Densidade">
        <div className="flex flex-wrap gap-2">
          {DENSITY_OPTIONS.map(({ value, label }) => (
            <Button
              key={value}
              type="button"
              variant={density === value ? 'default' : 'outline'}
              size="sm"
              onClick={() => chooseDensity(value)}
              aria-pressed={density === value}
            >
              {label}
            </Button>
          ))}
        </div>
      </Section>

      <Section eyebrow="Fundo">
        <div className="flex flex-wrap gap-2">
          {BACKDROP_OPTIONS.map(({ value, label }) => (
            <Button
              key={value}
              type="button"
              variant={backdrop === value ? 'default' : 'outline'}
              size="sm"
              onClick={() => chooseBackdrop(value)}
              aria-pressed={backdrop === value}
            >
              {label}
            </Button>
          ))}
        </div>
      </Section>
    </div>
  );
}
