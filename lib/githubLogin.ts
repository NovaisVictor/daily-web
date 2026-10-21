const LOGIN = /^[A-Za-z0-9][A-Za-z0-9-]{0,38}$/;
const BOT_SUFFIX = '[bot]';

/** Any author GitHub shows, apps included (`dependabot[bot]`): filters match on it. */
export function isGithubLogin(value: unknown): value is string {
  if (typeof value !== 'string') return false;
  return LOGIN.test(value.endsWith(BOT_SUFFIX) ? value.slice(0, -BOT_SUFFIX.length) : value);
}

/** A user GitHub accepts as a requested reviewer: apps cannot be asked to review. */
export function isRequestableLogin(value: unknown): value is string {
  return typeof value === 'string' && LOGIN.test(value);
}
