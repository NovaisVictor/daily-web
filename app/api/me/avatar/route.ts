import { NextRequest, NextResponse } from 'next/server';
import { requireUser } from '@/lib/api/context';
import { setUserAvatar } from '@/lib/auth/users';

// Guardada como data URL: uma foto de perfil é pequena o bastante para não
// pesar no banco, e isto evita ter que gerenciar arquivos soltos no disco.
const MAX_BYTES = 2 * 1024 * 1024;
const DATA_URL_RE = /^data:image\/(png|jpeg|jpg|webp|gif);base64,([a-zA-Z0-9+/]+={0,2})$/;

export async function POST(request: NextRequest) {
  const auth = await requireUser();
  if (!auth.ok) return auth.response;

  const body = await request.json().catch(() => null);
  const dataUrl = body && typeof body === 'object' ? body.dataUrl : null;
  if (typeof dataUrl !== 'string') {
    return NextResponse.json({ error: 'imagem inválida' }, { status: 400 });
  }

  const match = dataUrl.match(DATA_URL_RE);
  if (!match) {
    return NextResponse.json({ error: 'formato de imagem não suportado' }, { status: 400 });
  }
  // Base64 usa 4 caracteres para cada 3 bytes originais — estimar por aí
  // evita decodificar o arquivo inteiro só para medir o tamanho.
  const approxBytes = (match[2].length * 3) / 4;
  if (approxBytes > MAX_BYTES) {
    return NextResponse.json({ error: 'imagem maior que 2MB' }, { status: 400 });
  }

  setUserAvatar(auth.value.id, dataUrl);
  return NextResponse.json({ avatarUrl: dataUrl });
}

export async function DELETE() {
  const auth = await requireUser();
  if (!auth.ok) return auth.response;

  setUserAvatar(auth.value.id, null);
  return NextResponse.json({ avatarUrl: null });
}
