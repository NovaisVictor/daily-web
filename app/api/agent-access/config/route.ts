import { getCurrentUser } from '@/lib/auth/currentUser';
import { oauthConfig } from '@/lib/oauth/config';
export async function GET(){if(!await getCurrentUser())return Response.json({error:'unauthorized'},{status:401});try{return Response.json({mcpUrl:oauthConfig().resource},{headers:{'Cache-Control':'no-store'}});}catch{return Response.json({error:'oauth_not_configured'},{status:503});}}
