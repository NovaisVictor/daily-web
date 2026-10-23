import { getCurrentUser } from '@/lib/auth/currentUser';
import { revokeGrant } from '@/lib/access/grants';
import { oauthConfig } from '@/lib/oauth/config';
import { AccessError } from '@/lib/access/principal';
export async function DELETE(request:Request,{params}:{params:Promise<{id:string}>}){
 const headers={'Cache-Control':'no-store'};
 try{
  const user=await getCurrentUser();if(!user)return Response.json({error:'unauthorized'},{status:401,headers});
  let origin:string;
  try{origin=oauthConfig().origin;}catch{return Response.json({error:'oauth_unavailable'},{status:503,headers});}
  if(request.headers.get('origin')!==origin)return Response.json({error:'invalid_origin'},{status:403,headers});
  revokeGrant(user.id,(await params).id);return Response.json({ok:true},{headers});
 }catch(error){return Response.json({error:error instanceof AccessError?error.code:'operation_failed'},{status:error instanceof AccessError?error.status:500,headers});}
}
