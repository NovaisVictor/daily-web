import { NextRequest, NextResponse } from 'next/server';
import { requireUser } from '@/lib/api/context';
import { verifyPassword } from '@/lib/auth/password';
import { setUserPassword } from '@/lib/auth/users';

export async function POST(request: NextRequest) {
  const auth = await requireUser();
  if (!auth.ok) return auth.response;

  const body = await request.json().catch(() => null);
  const currentPassword = typeof body?.currentPassword === 'string' ? body.currentPassword : '';
  const newPassword = typeof body?.newPassword === 'string' ? body.newPassword : '';

  const ok = await verifyPassword(currentPassword, auth.value.passwordHash);
  if (!ok) {
    return NextResponse.json({ error: 'senha atual incorreta' }, { status: 401 });
  }

  try {
    await setUserPassword(auth.value.username, newPassword);
  } catch (err) {
    const message = err instanceof Error ? err.message : 'falha ao trocar a senha';
    return NextResponse.json({ error: message }, { status: 400 });
  }

  return NextResponse.json({ ok: true });
}
