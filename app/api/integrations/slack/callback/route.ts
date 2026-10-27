import { NextRequest, NextResponse } from 'next/server';
import { getCurrentUser } from '@/lib/auth/currentUser';
import { verifyOAuthState } from '@/lib/integrations/oauthState';
import { exchangeSlackCode } from '@/lib/integrations/slack/oauth';
import { dropCache } from '@/lib/refresher';
import { listConnections, saveConnection, setModuleEnabled } from '@/lib/vault/connections';

function back(value: string, ok: boolean): NextResponse {
  const origin = process.env.PUBLIC_ORIGIN ?? 'http://localhost:8010';
  const url = new URL('/tools', origin);
  url.searchParams.set(ok ? 'conectado' : 'erro', value);
  return NextResponse.redirect(url);
}

export async function GET(request: NextRequest) {
  const params = new URL(request.url).searchParams;
  const denied = params.get('error');
  // O `error` chega pela URL, então não volta para a tela como veio: só o
  // valor conhecido ganha mensagem própria.
  if (denied) {
    return back(
      denied === 'access_denied' ? 'autorização cancelada' : 'o Slack não concluiu a autorização',
      false,
    );
  }

  const secret = process.env.SESSION_SECRET;
  const code = params.get('code') ?? '';
  if (!secret || !code) return back('retorno do Slack incompleto', false);

  const verified = verifyOAuthState(params.get('state') ?? '', secret);
  if (!verified || verified.purpose !== 'slack') {
    return back('retorno do Slack inválido ou expirado — tente conectar de novo', false);
  }

  const user = await getCurrentUser();
  if (!user || user.id !== verified.userId) {
    return back('a sessão mudou durante a autorização — entre e conecte de novo', false);
  }

  try {
    const result = await exchangeSlackCode(code);
    const existing = listConnections(user.id, 'slack')[0];
    saveConnection(
      user.id,
      'slack',
      result.teamName || 'Slack',
      {
        token: result.token,
        userId: result.userId,
        teamId: result.teamId,
        teamName: result.teamName,
        scope: result.scope,
      },
      existing?.id,
    );
    setModuleEnabled(user.id, 'slack', true);
    dropCache(user.id);
    return back('slack', true);
  } catch (error) {
    return back(error instanceof Error ? error.message : String(error), false);
  }
}
