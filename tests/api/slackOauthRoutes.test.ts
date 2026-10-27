import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { NextRequest } from 'next/server';
import { signOAuthState } from '@/lib/integrations/oauthState';

const mocks = vi.hoisted(() => ({
  user: null as { id: string } | null,
  exchange: vi.fn(),
  connections: [] as { id: string; values: Record<string, string> }[],
  saves: [] as { id?: string; values: Record<string, string> }[],
  enabled: vi.fn(),
  drop: vi.fn(),
}));

vi.mock('@/lib/api/context', () => ({
  requireUser: async () =>
    mocks.user
      ? { ok: true, value: mocks.user }
      : { ok: false, response: new Response('não autenticado', { status: 401 }) },
}));

vi.mock('@/lib/auth/currentUser', () => ({ getCurrentUser: async () => mocks.user }));

vi.mock('@/lib/integrations/slack/oauth', async (importOriginal) => {
  const original = await importOriginal<typeof import('@/lib/integrations/slack/oauth')>();
  return { ...original, exchangeSlackCode: mocks.exchange };
});

vi.mock('@/lib/vault/connections', () => ({
  listConnections: () => mocks.connections,
  saveConnection: (_userId: string, _module: string, _label: string, values: Record<string, string>, id?: string) => {
    mocks.saves.push({ id, values });
    if (!id) mocks.connections.push({ id: 'conn-1', values });
  },
  setModuleEnabled: mocks.enabled,
}));

vi.mock('@/lib/refresher', () => ({ dropCache: mocks.drop }));

const original = { ...process.env };

beforeEach(() => {
  mocks.user = null;
  mocks.connections = [];
  mocks.saves = [];
  mocks.exchange.mockReset().mockResolvedValue({
    token: 'xoxp-token', userId: 'U1', teamId: 'T1', teamName: 'Equipe', scope: 'search:read',
  });
  mocks.enabled.mockReset();
  mocks.drop.mockReset();
  process.env.SESSION_SECRET = 'segredo';
  process.env.SLACK_CLIENT_ID = 'cliente';
  process.env.SLACK_CLIENT_SECRET = 'chave';
  process.env.PUBLIC_ORIGIN = 'https://painel.exemplo';
});

afterEach(() => {
  process.env = { ...original };
});

describe('rotas OAuth do Slack', () => {
  it('a rota inicial exige login', async () => {
    const { GET } = await import('@/app/api/integrations/slack/start/route');
    expect((await GET()).status).toBe(401);
  });

  it('a rota inicial avisa quando o host não configurou o app', async () => {
    mocks.user = { id: 'u-1' };
    delete process.env.SLACK_CLIENT_SECRET;
    const { GET } = await import('@/app/api/integrations/slack/start/route');
    expect((await GET()).status).toBe(503);
  });

  it('a rota inicial redireciona com user_scope', async () => {
    mocks.user = { id: 'u-1' };
    const { GET } = await import('@/app/api/integrations/slack/start/route');
    const response = await GET();
    const location = new URL(response.headers.get('location') ?? '');
    expect(location.searchParams.get('user_scope')).toBe('search:read,im:read,im:history,users:read');
  });

  it('o retorno recusa state inválido, outra sessão e cancelamento', async () => {
    mocks.user = { id: 'u-1' };
    const { GET } = await import('@/app/api/integrations/slack/callback/route');
    const invalid = await GET(new NextRequest('https://painel.exemplo/api?code=x&state=ruim'));
    expect(invalid.headers.get('location')).toContain('erro=retorno+do+Slack+inv%C3%A1lido');
    const other = signOAuthState('u-2', 'slack', 'segredo');
    const changed = await GET(new NextRequest(`https://painel.exemplo/api?code=x&state=${other}`));
    expect(changed.headers.get('location')).toContain('erro=a+sess%C3%A3o+mudou');
    const denied = await GET(new NextRequest('https://painel.exemplo/api?error=access_denied'));
    expect(denied.headers.get('location')).toContain('autoriza%C3%A7%C3%A3o+cancelada');
    // O parâmetro vem de fora: um valor desconhecido não volta para a tela.
    const unknown = await GET(
      new NextRequest('https://painel.exemplo/api?error=%3Cscript%3Etexto-injetado'),
    );
    const location = unknown.headers.get('location') ?? '';
    expect(location).not.toContain('texto-injetado');
    expect(location).toContain('erro=o+Slack+n%C3%A3o+concluiu');
  });

  it('salva uma conexão, atualiza a mesma ao reconectar e liga o módulo', async () => {
    mocks.user = { id: 'u-1' };
    const { GET } = await import('@/app/api/integrations/slack/callback/route');
    const state = signOAuthState('u-1', 'slack', 'segredo');
    const first = await GET(new NextRequest(`https://painel.exemplo/api?code=x&state=${state}`));
    expect(first.headers.get('location')).toBe('https://painel.exemplo/tools?conectado=slack');
    const second = await GET(new NextRequest(`https://painel.exemplo/api?code=y&state=${state}`));
    expect(mocks.saves).toHaveLength(2);
    expect(mocks.saves[0].id).toBeUndefined();
    expect(mocks.saves[1].id).toBe('conn-1');
    expect(mocks.saves[0].values.token).toBe('xoxp-token');
    expect(mocks.enabled).toHaveBeenCalledWith('u-1', 'slack', true);
    expect(mocks.drop).toHaveBeenCalledWith('u-1');
  });
});
