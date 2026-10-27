import { NextRequest, NextResponse } from 'next/server';
import { requireUser } from '@/lib/api/context';
import { getCurrentUser } from '@/lib/auth/currentUser';
import { setUserProfile } from '@/lib/auth/users';

export async function GET() {
  const current = await getCurrentUser();
  if (!current) return NextResponse.json({ error: 'não autenticado' }, { status: 401 });
  return NextResponse.json({
    username: current.username,
    isAdmin: current.isAdmin,
    avatarUrl: current.avatarUrl,
    fullName: current.fullName,
    email: current.email,
  });
}

export async function PATCH(request: NextRequest) {
  const auth = await requireUser();
  if (!auth.ok) return auth.response;

  const body = await request.json().catch(() => null);
  if (!body || typeof body !== 'object') {
    return NextResponse.json({ error: 'corpo inválido' }, { status: 400 });
  }

  const fullName = typeof body.fullName === 'string' ? body.fullName.trim() || null : null;
  const email = typeof body.email === 'string' ? body.email.trim() || null : null;
  if (email && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    return NextResponse.json({ error: 'e-mail inválido' }, { status: 400 });
  }

  setUserProfile(auth.value.id, { fullName, email });
  return NextResponse.json({ fullName, email });
}
