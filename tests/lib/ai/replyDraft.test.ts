import { describe, expect, it } from 'vitest';
import { systemPrompt } from '@/lib/ai/replyDraft';

describe('systemPrompt', () => {
  it('writes on behalf of the mailbox the reply is sent from', () => {
    expect(systemPrompt('maria@example.com')).toContain('maria@example.com');
  });

  // The prompt once named the author of the project, so every other user's
  // draft spoke as him.
  it('names no fixed person', () => {
    expect(systemPrompt('maria@example.com')).not.toMatch(/João/);
  });

  it('takes its only identity from the mailbox', () => {
    const forMaria = systemPrompt('maria@example.com').replaceAll('maria@example.com', '<sender>');
    const forPedro = systemPrompt('pedro@example.com').replaceAll('pedro@example.com', '<sender>');
    expect(forMaria).toBe(forPedro);
  });

  it('tells the model not to sign the reply', () => {
    expect(systemPrompt('maria@example.com')).toMatch(/Não assine/);
  });
});
