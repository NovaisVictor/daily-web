import { revokeCredential } from '@/lib/access/credentials';
import { handle,browser } from '@/lib/agents/http';
export async function DELETE(request:Request,{params}:{params:Promise<{id:string}>}) { return handle(async()=>revokeCredential(await browser(request,'write'),(await params).id),204); }
