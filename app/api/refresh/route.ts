import { NextResponse } from 'next/server';
import { refreshAll } from '@/lib/refresher';
import { getCurrentUser } from '@/lib/auth/currentUser';

export async function POST() {
  const user = await getCurrentUser();
  if (!user) return NextResponse.json({ error: 'não autenticado' }, { status: 401 });

  return NextResponse.json(await refreshAll(user.id, 'user'));
}
