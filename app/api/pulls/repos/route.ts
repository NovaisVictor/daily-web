import { NextRequest, NextResponse } from 'next/server';
import { requireUser } from '@/lib/api/context';
import { isValidRepo } from '@/lib/api/validation';
import { listConnections, saveConnection } from '@/lib/vault/connections';
import { parseRepoList, serializeRepoList, TRACKED_REPOS_MAX } from '@/lib/integrations/githubApi';
import { dropCache } from '@/lib/refresher';
import type { Connection } from '@/lib/vault/connections';

// Os repositórios acompanhados moraram num arquivo da máquina (a config do
// ghpending). Agora são campo da conexão do usuário: cada pessoa acompanha os
// seus, e o painel funciona numa máquina sem CLI nenhuma instalada.
function pullsConnection(userId: string): Connection | null {
  return listConnections(userId, 'pulls')[0] ?? null;
}

function noConnection() {
  return NextResponse.json(
    { error: 'configure o token do GitHub antes de escolher repositórios' },
    { status: 409 },
  );
}

function persist(userId: string, conn: Connection, repos: string[]) {
  saveConnection(
    userId,
    'pulls',
    conn.label,
    { ...conn.values, repos: serializeRepoList(repos) },
    conn.id,
  );
  dropCache(userId);
  return NextResponse.json({ repos });
}

export async function GET() {
  const auth = await requireUser();
  if (!auth.ok) return auth.response;

  const conn = pullsConnection(auth.value.id);
  return NextResponse.json({ repos: conn ? parseRepoList(conn.values.repos ?? '') : [] });
}

export async function POST(request: NextRequest) {
  const auth = await requireUser();
  if (!auth.ok) return auth.response;

  const body = await request.json().catch(() => null);
  if (!isValidRepo(body?.repo)) {
    return NextResponse.json({ error: 'repositório inválido (use owner/nome)' }, { status: 400 });
  }

  const conn = pullsConnection(auth.value.id);
  if (!conn) return noConnection();

  const repos = parseRepoList(conn.values.repos ?? '');
  if (repos.includes(body.repo)) return persist(auth.value.id, conn, repos);
  if (repos.length >= TRACKED_REPOS_MAX) {
    return NextResponse.json(
      { error: `limite de ${TRACKED_REPOS_MAX} repositórios acompanhados — remova um antes de adicionar outro` },
      { status: 400 },
    );
  }
  repos.push(body.repo);
  return persist(auth.value.id, conn, repos);
}

export async function DELETE(request: NextRequest) {
  const auth = await requireUser();
  if (!auth.ok) return auth.response;

  const body = await request.json().catch(() => null);
  if (!isValidRepo(body?.repo)) {
    return NextResponse.json({ error: 'repositório inválido (use owner/nome)' }, { status: 400 });
  }

  const conn = pullsConnection(auth.value.id);
  if (!conn) return noConnection();

  const repos = parseRepoList(conn.values.repos ?? '').filter((r) => r !== body.repo);
  return persist(auth.value.id, conn, repos);
}
