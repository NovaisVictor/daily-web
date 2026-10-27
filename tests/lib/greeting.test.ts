import { describe, expect, it } from 'vitest';
import { greetingName } from '@/lib/greeting';

describe('greetingName', () => {
  it('uses the first name when the profile has a full name', () => {
    expect(greetingName('Philippe Albuquerque', 'philippe.a')).toBe('Philippe');
  });

  it('falls back to the username when there is no full name', () => {
    expect(greetingName(null, 'philippe')).toBe('philippe');
  });

  it('treats a blank full name as missing', () => {
    expect(greetingName('   ', 'philippe')).toBe('philippe');
  });

  it('ignores extra spaces around the first name', () => {
    expect(greetingName('  Maria   da Silva ', 'maria')).toBe('Maria');
  });
});
