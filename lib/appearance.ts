import { savedAppearance } from './preferences';
import {
  BACKDROP_COOKIE,
  DENSITY_COOKIE,
  THEME_COOKIE,
  WIDTH_COOKIE,
  parseBackdrop,
  parseContentWidth,
  parseDensity,
  parseTheme,
  type Appearance,
} from './theme';

/**
 * The appearance to render. What the person saved on their account wins, so it follows them to
 * any browser; the browser's cookie only fills in what was never saved (an account that predates
 * this, or the login screen, where nobody is known yet).
 */
export function resolveAppearance(
  readCookie: (name: string) => string | undefined,
  userId: string | null,
): Appearance {
  const saved = userId ? savedAppearance(userId) : {};
  return {
    theme: saved.theme ?? parseTheme(readCookie(THEME_COOKIE)),
    density: saved.density ?? parseDensity(readCookie(DENSITY_COOKIE)),
    backdrop: saved.backdrop ?? parseBackdrop(readCookie(BACKDROP_COOKIE)),
    width: saved.width ?? parseContentWidth(readCookie(WIDTH_COOKIE)),
  };
}
