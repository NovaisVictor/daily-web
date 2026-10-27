export type ThemePreference = 'system' | 'light' | 'dark';
export type Density = 'comfortable' | 'compact';
/** The page background: the iridescent mesh, or a flat Catppuccin or Dracula base. */
export type Backdrop = 'mesh' | 'catppuccin' | 'dracula';

export const THEME_COOKIE = 'theme';
export const DENSITY_COOKIE = 'density';
export const BACKDROP_COOKIE = 'backdrop';

/** "system" is the absence of everything, so anything unrecognised is system. */
export function parseTheme(raw: string | undefined): ThemePreference {
  return raw === 'light' || raw === 'dark' ? raw : 'system';
}

export function parseDensity(raw: string | undefined): Density {
  return raw === 'compact' ? 'compact' : 'comfortable';
}

/**
 * Both classes come off before either goes on. Leaving both would hand the decision
 * to rule order rather than to the choice the person just made.
 *
 * Choosing "system" deletes the cookie rather than writing the word, so the absence
 * of a cookie and the absence of a class always mean the same thing.
 */
export function applyTheme(
  pref: ThemePreference,
  root: HTMLElement = document.documentElement,
): void {
  root.classList.remove('light', 'dark');
  if (pref !== 'system') root.classList.add(pref);

  document.cookie =
    pref === 'system'
      ? `${THEME_COOKIE}=; path=/; max-age=0; samesite=lax`
      : `${THEME_COOKIE}=${pref}; path=/; max-age=31536000; samesite=lax`;
}

export function applyDensity(d: Density, root: HTMLElement = document.documentElement): void {
  if (d === 'compact') root.dataset.density = 'compact';
  else delete root.dataset.density;

  document.cookie =
    d === 'compact'
      ? `${DENSITY_COOKIE}=compact; path=/; max-age=31536000; samesite=lax`
      : `${DENSITY_COOKIE}=; path=/; max-age=0; samesite=lax`;
}

/** The mesh is the absence of the cookie, like "comfortable" and "system". */
export function parseBackdrop(raw: string | undefined): Backdrop {
  return raw === 'catppuccin' || raw === 'dracula' ? raw : 'mesh';
}

export function applyBackdrop(b: Backdrop, root: HTMLElement = document.documentElement): void {
  if (b === 'mesh') delete root.dataset.backdrop;
  else root.dataset.backdrop = b;

  document.cookie =
    b === 'mesh'
      ? `${BACKDROP_COOKIE}=; path=/; max-age=0; samesite=lax`
      : `${BACKDROP_COOKIE}=${b}; path=/; max-age=31536000; samesite=lax`;
}

/** Matches on a segment boundary, so /config/x keeps /config lit and /configuracao does not. */
export function isActivePath(pathname: string, href: string): boolean {
  if (href === '/') return pathname === '/';
  return pathname === href || pathname.startsWith(`${href}/`);
}

/** Numbers use the body face with tabular figures. Never the mono face. */
export const tabular = 'tabular-nums';

/**
 * shadcn primitives keep their own stock focus block. This one is for everything
 * hand-rolled, and adds the 1px offset the primitives do not have.
 */
export const focusRing =
  'focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/50 focus-visible:ring-offset-1 focus-visible:ring-offset-background';

/** Um select nativo, mantido nativo: as ações em lote leem o evento de
 *  mudança dele. Compartilhado por quem precisa do mesmo controle. */
export const selectClass =
  'h-8 shrink-0 rounded-full border bg-glass px-3 text-sm text-ink shadow-e1 outline-none transition-colors duration-100 ease-brand motion-reduce:transition-none';
