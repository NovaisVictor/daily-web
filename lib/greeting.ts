/** Whether this is the person's first sign-in or a later one. */
export type WelcomeKind = 'first' | 'returning';

export const WELCOME_LABELS: Record<WelcomeKind, string> = {
  first: 'Bem-vindo',
  returning: 'Bem-vindo de volta',
};

/** The first name when the profile has a full name, the username otherwise. */
export function greetingName(fullName: string | null, username: string): string {
  return fullName?.trim().split(/\s+/)[0] || username;
}
