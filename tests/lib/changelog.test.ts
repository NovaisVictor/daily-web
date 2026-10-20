import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { RELEASES, loadLastSeen, markSeen, unseenReleases, type Release } from '@/lib/changelog';

const release = (id: string): Release => ({ id, date: '2026-10-20', title: id, items: [] });
const releases = [release('c'), release('b'), release('a')];

describe('unseenReleases', () => {
  it('returns every release when nothing was seen', () => {
    expect(unseenReleases(null, releases)).toEqual(releases);
  });

  it('returns nothing when the newest release was seen', () => {
    expect(unseenReleases('c', releases)).toEqual([]);
  });

  it('returns only the releases newer than the one seen', () => {
    expect(unseenReleases('a', releases).map((r) => r.id)).toEqual(['c', 'b']);
  });

  it('returns only the newest for an unknown id, because the user already saw an older, since removed release', () => {
    expect(unseenReleases('removed', releases).map((r) => r.id)).toEqual(['c']);
  });

  it('defaults to the shipped releases, newest first with unique ids', () => {
    expect(unseenReleases(null)).toBe(RELEASES);
    const dates = RELEASES.map((r) => r.date);
    expect([...dates].sort().reverse()).toEqual(dates);
    expect(new Set(RELEASES.map((r) => r.id)).size).toBe(RELEASES.length);
  });
});

describe('changelog storage', () => {
  beforeEach(() => localStorage.clear());
  afterEach(() => vi.restoreAllMocks());

  it('stores only the release id under its key', () => {
    markSeen('2026-10-20-jira-acoes');
    expect(localStorage.getItem('daily-web:changelog-seen')).toBe('2026-10-20-jira-acoes');
    expect(loadLastSeen()).toBe('2026-10-20-jira-acoes');
  });

  it('reads nothing seen from empty storage', () => {
    expect(loadLastSeen()).toBeNull();
  });

  it('does not let a storage refusal throw', () => {
    vi.spyOn(Storage.prototype, 'getItem').mockImplementation(() => {
      throw new Error('blocked');
    });
    vi.spyOn(Storage.prototype, 'setItem').mockImplementation(() => {
      throw new Error('blocked');
    });
    expect(loadLastSeen()).toBeNull();
    expect(() => markSeen('x')).not.toThrow();
  });
});
