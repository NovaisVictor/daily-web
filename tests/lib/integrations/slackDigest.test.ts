import { afterEach, describe, expect, it, vi } from 'vitest';
import { fetchSlack, SlackDigestError } from '@/lib/integrations/slack/digest';
import type { Connection } from '@/lib/vault/connections';

function connection(): Connection {
  return {
    id: 's1',
    module: 'slack',
    label: 'Slack',
    values: { token: 'xoxp-token', userId: 'U1', teamName: 'Equipe' },
  };
}

function response(body: unknown) {
  return new Response(JSON.stringify(body));
}

afterEach(() => vi.restoreAllMocks());

describe('digest do Slack', () => {
  it('busca menções, filtra as próprias e antigas e formata o texto', async () => {
    const recent = String(Date.now() / 1_000);
    const old = String((Date.now() - 8 * 24 * 60 * 60 * 1_000) / 1_000);
    const fetchMock = vi.spyOn(global, 'fetch').mockImplementation(async (input, init) => {
      const method = new URL(String(input)).pathname.split('/').pop();
      if (method === 'search.messages') {
        const body = new URLSearchParams(String(init?.body));
        if (body.get('query') === 'is:dm') return response({ ok: true, messages: { matches: [] } });
        expect(body.get('query')).toBe('<@U1>');
        return response({
          ok: true,
          messages: {
            matches: [
              {
                channel: { id: 'C1', name: 'geral' }, user: 'U2',
                text: 'Oi <@U3> em <#C2|produto> <https://x.test|link> &lt;ok&gt; &amp;',
                ts: recent, permalink: 'https://equipe.slack.com/archives/C1/p1',
              },
              { channel: { id: 'C1' }, user: 'U1', text: 'minha', ts: recent },
              { channel: { id: 'C1' }, user: 'U2', text: 'velha', ts: old },
            ],
          },
        });
      }
      if (method === 'users.info') {
        const id = new URLSearchParams(String(init?.body)).get('user');
        return response({ ok: true, user: { profile: { display_name: id === 'U2' ? 'Ana' : 'Bia' } } });
      }
      throw new Error(`chamada inesperada: ${method}`);
    });

    const digest = await fetchSlack(connection());
    expect(digest.mentions).toHaveLength(1);
    expect(digest.mentions[0]).toMatchObject({
      author: 'Ana', channel: '#geral',
      text: 'Oi @Bia em #produto link <ok> &',
      url: 'https://equipe.slack.com/archives/C1/p1',
    });
    expect(fetchMock).toHaveBeenCalled();
  });

  it('descarta permalink que não pertence ao Slack', async () => {
    vi.spyOn(global, 'fetch').mockImplementation(async (input, init) => {
      if (new URLSearchParams(String(init?.body)).get('query') === 'is:dm') return response({ ok: true, messages: { matches: [] } });
      return response({ ok: true, messages: { matches: [{ channel: { id: 'C1' }, username: 'Ana', text: 'x', ts: String(Date.now() / 1_000), permalink: 'https://evil.test/x' }] } });
    });
    expect((await fetchSlack(connection())).mentions[0].url).toBe('');
  });

  it('pergunta pelas não lidas só nas DMs recentes da busca, e busca histórico só das não lidas', async () => {
    const infos: string[] = [];
    const calls: URLSearchParams[] = [];
    vi.spyOn(global, 'fetch').mockImplementation(async (input, init) => {
      const method = new URL(String(input)).pathname.split('/').pop();
      const body = new URLSearchParams(String(init?.body));
      if (method === 'search.messages' && body.get('query') === 'is:dm') {
        return response({
          ok: true,
          messages: {
            matches: [
              { channel: { id: 'D1', is_im: true }, ts: '3.0' },
              { channel: { id: 'D1', is_im: true }, ts: '2.0' },
              { channel: { id: 'D2', is_im: true }, ts: '1.0' },
              { channel: { id: 'G1', is_mpim: true }, ts: '1.5' },
            ],
          },
        });
      }
      if (method === 'search.messages') return response({ ok: true, messages: { matches: [] } });
      if (method === 'conversations.info') {
        const id = body.get('channel') ?? '';
        infos.push(id);
        return response({ ok: true, channel: { id, user: id === 'D1' ? 'U2' : 'U3', unread_count_display: id === 'D1' ? 2 : 0 } });
      }
      if (method === 'conversations.history') {
        calls.push(body);
        return response({ ok: true, messages: [{ user: 'U2', text: 'Olá', ts: '1000.1' }] });
      }
      if (method === 'users.info') return response({ ok: true, user: { profile: { display_name: 'Ana' } } });
      throw new Error(`chamada inesperada: ${method}`);
    });
    const digest = await fetchSlack(connection());
    expect(infos).toEqual(['D1', 'D2']);
    expect(digest.directs).toEqual([expect.objectContaining({ author: 'Ana', text: 'Olá' })]);
    expect(calls).toHaveLength(1);
    expect(calls[0].get('channel')).toBe('D1');
    expect(calls[0].get('limit')).toBe('1');
  });

  it('não falha quando não há DM recente', async () => {
    vi.spyOn(global, 'fetch').mockImplementation(async () => response({ ok: true, messages: { matches: [] } }));
    expect((await fetchSlack(connection())).directs).toEqual([]);
  });

  it('falha a lista quando o Slack não informa contagem de não lidas', async () => {
    vi.spyOn(global, 'fetch').mockImplementation(async (input, init) => {
      const method = new URL(String(input)).pathname.split('/').pop();
      if (method === 'conversations.info') return response({ ok: true, channel: { id: 'D1', user: 'U2' } });
      const dm = new URLSearchParams(String(init?.body)).get('query') === 'is:dm';
      return response({ ok: true, messages: { matches: dm ? [{ channel: { id: 'D1', is_im: true }, ts: '1.0' }] : [] } });
    });
    const error = await fetchSlack(connection()).catch((value: unknown) => value);
    expect(error).toBeInstanceOf(SlackDigestError);
    expect((error as SlackDigestError).message).toContain('não informou as mensagens não lidas');
  });

  it('preserva as menções quando a lista de diretas falha', async () => {
    vi.spyOn(global, 'fetch').mockImplementation(async (input, init) => {
      if (new URLSearchParams(String(init?.body)).get('query') === 'is:dm') return response({ ok: false, error: 'internal_error' });
      return response({ ok: true, messages: { matches: [{ channel: { id: 'C1' }, username: 'Ana', text: 'Oi', ts: String(Date.now() / 1_000) }] } });
    });
    const error = await fetchSlack(connection()).catch((value: unknown) => value);
    expect(error).toBeInstanceOf(SlackDigestError);
    expect((error as SlackDigestError).digest.mentions).toHaveLength(1);
  });

  it('limita a trinta consultas de nomes por ciclo', async () => {
    let lookups = 0;
    const mentions = Array.from({ length: 31 }, (_, index) => `<@U${index + 10}>`).join(' ');
    vi.spyOn(global, 'fetch').mockImplementation(async (input, init) => {
      const method = new URL(String(input)).pathname.split('/').pop();
      if (new URLSearchParams(String(init?.body)).get('query') === 'is:dm') return response({ ok: true, messages: { matches: [] } });
      if (method === 'search.messages') return response({ ok: true, messages: { matches: [{ channel: { id: 'C1' }, username: 'Ana', text: mentions, ts: String(Date.now() / 1_000) }] } });
      if (method === 'users.info') {
        lookups += 1;
        return response({ ok: true, user: { name: 'pessoa' } });
      }
      throw new Error('chamada inesperada');
    });
    await fetchSlack(connection());
    expect(lookups).toBe(30);
  });
});
