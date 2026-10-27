'use client';

import { useEffect, useState } from 'react';
import { Info, Monitor, MoveHorizontal, Moon, Sun } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Label } from '@/components/ui/label';
import { Switch } from '@/components/ui/switch';
import { Tooltip, TooltipContent, TooltipTrigger } from '@/components/ui/tooltip';
import { Section } from './ui/Section';
import { persistAppearance } from '@/lib/appearanceClient';
import {
  LIMITED_CONTENT_WIDTH,
  applyBackdrop,
  applyContentWidth,
  applyDensity,
  applyTheme,
  type Backdrop,
  type ContentWidth,
  type Density,
  type ThemePreference,
} from '@/lib/theme';

interface Props {
  initialTheme: ThemePreference;
  initialDensity: Density;
  initialBackdrop: Backdrop;
  initialWidth: ContentWidth;
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
];

/**
 * Moved out of the account dropdown: appearance is a settings screen's job,
 * not something buried behind the avatar.
 */
export function AppearancePanel({
  initialTheme,
  initialDensity,
  initialBackdrop,
  initialWidth,
}: Props) {
  const [theme, setTheme] = useState<ThemePreference>(initialTheme);
  const [density, setDensity] = useState<Density>(initialDensity);
  const [backdrop, setBackdrop] = useState<Backdrop>(initialBackdrop);
  const [width, setWidth] = useState<ContentWidth>(initialWidth);

  // The root element is the source of truth; a cookie cleared in another tab
  // would otherwise leave this screen showing a choice that is no longer applied.
  useEffect(() => {
    const root = document.documentElement;
    if (root.classList.contains('dark')) setTheme('dark');
    else if (root.classList.contains('light')) setTheme('light');
    else setTheme('system');
    setDensity(root.dataset.density === 'compact' ? 'compact' : 'comfortable');
    setBackdrop(root.dataset.backdrop === 'catppuccin' ? 'catppuccin' : 'mesh');
    setWidth(root.dataset.width === 'limited' ? 'limited' : 'full');
  }, []);

  const chooseTheme = (pref: ThemePreference) => {
    applyTheme(pref);
    setTheme(pref);
    persistAppearance({ theme: pref });
  };
  const chooseDensity = (d: Density) => {
    applyDensity(d);
    setDensity(d);
    persistAppearance({ density: d });
  };
  const chooseBackdrop = (b: Backdrop) => {
    applyBackdrop(b);
    setBackdrop(b);
    persistAppearance({ backdrop: b });
  };
  const chooseWidth = (w: ContentWidth) => {
    applyContentWidth(w);
    setWidth(w);
    persistAppearance({ width: w });
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

      <Section eyebrow="Largura do conteúdo">
        <div className="flex w-56 flex-col gap-6 rounded-xl border border-line-soft bg-glass p-4 shadow-e1">
          <div className="flex items-center justify-between">
            <MoveHorizontal className="size-5 text-ink-mid" aria-hidden />
            {/* The stored choice is the ContentWidth enum; the switch is only how it is picked. */}
            <Switch
              id="content-width"
              checked={width === 'limited'}
              onCheckedChange={(on) => chooseWidth(on ? 'limited' : 'full')}
            />
          </div>
          <div className="flex items-center justify-between gap-2">
            <Label htmlFor="content-width" className="cursor-pointer">
              Limitar largura
            </Label>
            <Tooltip>
              <TooltipTrigger asChild>
                <button
                  type="button"
                  aria-label="Sobre limitar a largura"
                  className="text-ink-dim hover:text-ink-mid"
                >
                  <Info className="size-4" />
                </button>
              </TooltipTrigger>
              <TooltipContent side="top" className="max-w-56">
                {`Ligado, o conteúdo fica com no máximo ${LIMITED_CONTENT_WIDTH}px, centralizado. Desligado, ocupa a largura toda da tela, como o cabeçalho.`}
              </TooltipContent>
            </Tooltip>
          </div>
        </div>
      </Section>
    </div>
  );
}
