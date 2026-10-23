import { redirect } from 'next/navigation';
import { headers,cookies } from 'next/headers';
import { getCurrentUser } from '@/lib/auth/currentUser';
import { oauthInternal,BROWSER_BINDING_COOKIE, type ConsentRequest } from '@/lib/oauth/interaction';
import { oauthConfig } from '@/lib/oauth/config';
export const dynamic='force-dynamic';
async function decide(form:FormData) {
  'use server';
  const user=await getCurrentUser();if(!user)redirect('/login');
  if((await headers()).get('origin')!==oauthConfig().origin)throw new Error('Invalid origin');
  const id=String(form.get('interaction')??'');
  const browserSecret=(await cookies()).get(BROWSER_BINDING_COOKIE)?.value??'';
  const current=await oauthInternal<ConsentRequest>('inspect',{id,userId:user.id,browserSecret});
  const scopes=form.getAll('scope').map(String);
  const decision=form.get('decision')==='approve'?'approve':'deny';
  const result=await oauthInternal<{redirect:string}>('decide',{id,nonce:current.nonce,userId:user.id,browserSecret,scopes,decision});
  const destination=new URL(result.redirect);if(destination.origin!==oauthConfig().origin||!destination.pathname.startsWith('/oauth/'))throw new Error('Invalid authorization redirect');
  redirect(result.redirect);
}
export default async function ConsentPage({searchParams}:{searchParams:Promise<{interaction?:string}>}) {
  const user=await getCurrentUser();if(!user)redirect('/login');
  const {interaction}=await searchParams;if(!interaction)return <p>Solicitação de autorização inválida.</p>;
  let request:ConsentRequest;try{request=await oauthInternal<ConsentRequest>('inspect',{id:interaction,userId:user.id,browserSecret:(await cookies()).get(BROWSER_BINDING_COOKIE)?.value??''});}catch{return <p>Esta solicitação expirou ou já foi utilizada. Inicie a conexão novamente no agente.</p>;}
  return <main className="mx-auto max-w-xl space-y-6 p-6"><h1 className="text-2xl font-semibold">Autorizar {request.clientName}</h1><p>O agente terá acesso à sua conta com as permissões selecionadas. Você pode revogar este acesso a qualquer momento.</p><p>Retorno: <strong>{request.redirectHost}</strong></p><form action={decide} className="space-y-4"><input type="hidden" name="interaction" value={request.id}/>{request.scopes.map(scope=><label key={scope} className="flex gap-3"><input type="checkbox" name="scope" value={scope} defaultChecked/>{scope}</label>)}<div className="flex gap-4"><button name="decision" value="approve" className="rounded bg-primary px-4 py-2 text-primary-foreground">Autorizar</button><button name="decision" value="deny" className="rounded border px-4 py-2">Recusar</button></div></form></main>;
}
