import { getCurrentUser } from '@/lib/auth/currentUser';
import { listGrants } from '@/lib/access/grants';
export async function GET(){const user=await getCurrentUser();if(!user)return Response.json({error:'unauthorized'},{status:401});return Response.json({grants:listGrants(user.id)},{headers:{'Cache-Control':'no-store'}});}
