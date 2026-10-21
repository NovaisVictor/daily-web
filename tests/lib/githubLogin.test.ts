import { describe, expect, it } from 'vitest';
import { isGithubLogin, isRequestableLogin } from '@/lib/githubLogin';

describe('isGithubLogin', () => {
  it.each(['user-1', 'a', 'dependabot[bot]', 'A'.repeat(39)])('accepts %s', (login) => {
    expect(isGithubLogin(login)).toBe(true);
  });

  it.each(['-user', 'user_1', '<script>', '', '[bot]', 'A'.repeat(40), 'x[bot][bot]'])('rejects %j', (login) => {
    expect(isGithubLogin(login)).toBe(false);
  });
});

describe('isRequestableLogin', () => {
  it('accepts a user login', () => {
    expect(isRequestableLogin('user-1')).toBe(true);
  });

  it('rejects an app, which GitHub does not accept as a reviewer', () => {
    expect(isRequestableLogin('dependabot[bot]')).toBe(false);
  });

  it('rejects a login starting with a hyphen', () => {
    expect(isRequestableLogin('-user')).toBe(false);
  });
});
