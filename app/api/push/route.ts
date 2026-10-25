import { handle,browser } from '@/lib/agents/http';
import { vapid } from '@/lib/push/dispatch';
export async function GET(request:Request) { return handle(async()=>{await browser(request);return {publicKey:vapid()?.publicKey??null};}); }
